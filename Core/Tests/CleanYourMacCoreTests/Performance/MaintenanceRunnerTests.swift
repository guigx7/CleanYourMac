import Foundation
import Testing
@testable import CleanYourMacCore

/// Grava as chamadas; `slow` simula um comando que só termina no tempo-limite ou no cancelamento.
final class FakeProcessRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var slow: Set<String> = []
    var status: Int32 = 0
    var calls: [[String]] { lock.withLock { _calls } }

    func run(_ executable: String, _ arguments: [String], timeout: Duration) async -> ProcessOutcome {
        lock.withLock { _calls.append([executable] + arguments) }
        guard slow.contains(executable) else { return .exited(status) }
        do {
            try await Task.sleep(for: timeout)
            return .timedOut
        } catch {
            return .cancelled
        }
    }
}

final class RecordingMaintenancePrivileged: PrivilegedRunner, @unchecked Sendable {
    var calls: [[PrivilegedCommand]] = []
    var cancel = false
    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] {
        calls.append(commands)
        if cancel { throw .userCancelled }
        return commands.map { _ in .success(()) }
    }
}

struct FakePurgeable: PurgeableSpace {
    var ok = true
    func recover(timeout: Duration) async -> ProcessOutcome { ok ? .exited(0) : .exited(1) }
}

final class MemoryHistory: MaintenanceHistory, @unchecked Sendable {
    var dates: [MaintenanceTaskID: Date] = [:]
    func record(_ id: MaintenanceTaskID, at date: Date) { dates[id] = date }
}

@Suite struct MaintenanceRunnerTests {
    let home = URL(fileURLWithPath: "/Users/tester")
    let logDir = FileManager.default.temporaryDirectory.appendingPathComponent("cym-maint-\(UUID().uuidString)")

    func task(_ id: MaintenanceTaskID, timeout: Duration? = nil) -> MaintenanceTask {
        MaintenanceTask(id: id, isApplicable: true, isRecommended: true,
                        requiresAdmin: MaintenanceCatalog.adminTasks.contains(id),
                        timeout: timeout ?? MaintenanceCatalog.timeout(id))
    }

    func runner(_ p: FakeProcessRunner, _ priv: RecordingMaintenancePrivileged, dryRun: Bool = false,
                history: MemoryHistory = MemoryHistory(), purgeable: FakePurgeable = FakePurgeable()) -> MaintenanceRunner {
        MaintenanceRunner(processes: p, privileged: priv, purgeable: purgeable, history: history, home: home,
                          dryRun: dryRun, log: CleanupLog(directory: logDir))
    }

    /// Resultado por tarefa: "ok" ou o motivo da falha.
    func results(_ stream: AsyncStream<MaintenanceEvent>) async -> (finished: [MaintenanceTaskID: String], report: MaintenanceReport?) {
        var finished: [MaintenanceTaskID: String] = [:]
        var report: MaintenanceReport?
        for await e in stream {
            switch e {
            case .started: break
            case .finished(let id, let r):
                if case .failure(let f) = r { finished[id] = f.reason } else { finished[id] = "ok" }
            case .completed(let r): report = r
            }
        }
        return (finished, report)
    }

    @Test func runsEachTaskWithSpecCommands() async {
        let p = FakeProcessRunner(), priv = RecordingMaintenancePrivileged()
        let out = await results(runner(p, priv).run([task(.speedUpMail), task(.thinSnapshots), task(.freeUpPurgeable)]))
        #expect(p.calls == [["/usr/bin/mdimport", "/Users/tester/Library/Mail"],
                            ["/usr/bin/tmutil", "thinlocalsnapshots", "/", "1073741824", "3"]])
        #expect(out.finished.count == 3)
        #expect(out.finished.values.allSatisfy { $0 == "ok" })
        #expect(priv.calls.isEmpty)
    }

    @Test func rootTasksGoToPrivilegedBatch() async {
        let p = FakeProcessRunner(), priv = RecordingMaintenancePrivileged()
        _ = await results(runner(p, priv).run([task(.flushDNS), task(.speedUpMail), task(.reindexSpotlight), task(.repairPermissions)]))
        #expect(priv.calls == [[.maintenance(.flushDNS), .maintenance(.reindexSpotlight), .maintenance(.repairPermissions)]])
        #expect(p.calls.count == 1)
    }

    @Test func adminCancelledOnlyFailsRootTasks() async {
        let p = FakeProcessRunner(), priv = RecordingMaintenancePrivileged()
        priv.cancel = true
        let out = await results(runner(p, priv).run([task(.flushDNS), task(.speedUpMail)]))
        #expect(out.finished[.flushDNS] == "cancelled")
        #expect(out.finished[.speedUpMail] == "ok")
        #expect(out.report?.failed == [.flushDNS: "cancelled"])
    }

    @Test func timeoutAndCancelPerTask() async throws {
        let p = FakeProcessRunner(), priv = RecordingMaintenancePrivileged()
        p.slow = ["/usr/bin/mdimport"]
        let timed = await results(runner(p, priv).run([task(.speedUpMail, timeout: .milliseconds(50)), task(.thinSnapshots)]))
        #expect(timed.finished[.speedUpMail] == "timed out")
        #expect(timed.finished[.thinSnapshots] == "ok")

        // Cancelar no meio: a lenta e as seguintes ficam "cancelled" no registro (pasta de registro só desta execução).
        let p2 = FakeProcessRunner()
        p2.slow = ["/usr/bin/mdimport"]
        try FileManager.default.removeItem(at: logDir)
        let r = runner(p2, priv)
        let consumer = Task { await results(r.run([task(.speedUpMail, timeout: .seconds(30)), task(.thinSnapshots)])) }
        try await Task.sleep(for: .milliseconds(100))
        consumer.cancel()
        _ = await consumer.value
        let report = try await waitForLog()
        #expect(report.failed == [.speedUpMail: "cancelled", .thinSnapshots: "cancelled"])
        #expect(p2.calls.count == 1)
    }

    func waitForLog() async throws -> MaintenanceReport {
        for _ in 0..<100 {
            if let f = try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil)
                .first(where: { $0.lastPathComponent.hasPrefix("maintenance-") }) {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(MaintenanceReport.self, from: Data(contentsOf: f))
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CleanFailure(reason: "no log")
    }

    @Test func realProcessTimesOutWithoutLeftovers() async {
        let marker = "7.\(Int.random(in: 100_000...999_999))"
        let outcome = await SystemProcessRunner().run("/bin/sleep", [marker], timeout: .milliseconds(200))
        #expect(outcome == .timedOut)
        let pgrep = SystemCommandRunner().run("/usr/bin/pgrep", ["-f", "sleep \(marker)"])
        #expect(pgrep.status != 0)
    }

    @Test func realProcessCancelled() async {
        let marker = "8.\(Int.random(in: 100_000...999_999))"
        let t = Task { await SystemProcessRunner().run("/bin/sleep", [marker], timeout: .seconds(30)) }
        try? await Task.sleep(for: .milliseconds(200))
        t.cancel()
        #expect(await t.value == .cancelled)
        #expect(SystemCommandRunner().run("/usr/bin/pgrep", ["-f", "sleep \(marker)"]).status != 0)
    }

    @Test func dryRunRunsNothing() async {
        let p = FakeProcessRunner(), priv = RecordingMaintenancePrivileged(), history = MemoryHistory()
        let out = await results(runner(p, priv, dryRun: true, history: history).run([task(.flushDNS), task(.speedUpMail)]))
        #expect(p.calls.isEmpty && priv.calls.isEmpty)
        #expect(out.finished.count == 2)
        #expect(out.report?.dryRun == true)
        #expect(history.dates.isEmpty)
    }

    @Test func recordsLastRunDate() async {
        let p = FakeProcessRunner(), priv = RecordingMaintenancePrivileged(), history = MemoryHistory()
        p.status = 1
        _ = await results(runner(p, priv, history: history).run([task(.flushDNS), task(.speedUpMail)]))
        #expect(history.dates[.flushDNS] != nil)
        #expect(history.dates[.speedUpMail] == nil)
    }

    @Test func purgeableFailureReported() async {
        let out = await results(runner(FakeProcessRunner(), RecordingMaintenancePrivileged(), purgeable: FakePurgeable(ok: false))
            .run([task(.freeUpPurgeable)]))
        #expect(out.finished[.freeUpPurgeable] == "exit 1")
    }
}
