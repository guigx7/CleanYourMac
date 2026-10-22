import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

struct StubPerformanceScan: PerformanceScanning {
    var report: PerformanceReport
    var delay: Duration = .zero

    func run(_ context: ScanContext) -> AsyncThrowingStream<PerformanceScanEvent, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                cont.yield(.progress(.maintenance))
                if delay > .zero {
                    do { try await Task.sleep(for: delay) } catch { cont.finish(throwing: error); return }
                }
                cont.yield(.finished(report))
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

/// Responde sucesso para tudo, menos as tarefas em `failing`.
final class StubMaintenance: MaintenanceRunning, @unchecked Sendable {
    private(set) var requested: [[MaintenanceTaskID]] = []
    var failing: Set<MaintenanceTaskID> = []

    func run(_ tasks: [MaintenanceTask]) -> AsyncStream<MaintenanceEvent> {
        requested.append(tasks.map(\.id))
        let failing = failing
        return AsyncStream { cont in
            var ok: [MaintenanceTaskID] = [], failed: [MaintenanceTaskID: String] = [:]
            for t in tasks {
                cont.yield(.started(t.id))
                if failing.contains(t.id) {
                    failed[t.id] = "exit 1"
                    cont.yield(.finished(t.id, .failure(CleanFailure(reason: "exit 1"))))
                } else {
                    ok.append(t.id)
                    cont.yield(.finished(t.id, .success(())))
                }
            }
            cont.yield(.completed(MaintenanceReport(succeeded: ok, failed: failed, dryRun: true)))
            cont.finish()
        }
    }
}

final class StubStartup: StartupActing, @unchecked Sendable {
    private(set) var performed: [(StartupAction, [String])] = []
    var ownerWarnings: [String: URL] = [:]

    func perform(_ action: StartupAction, on items: [StartupItem]) async -> [String: Result<Void, CleanFailure>] {
        performed.append((action, items.map(\.id)))
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, .success(())) })
    }

    func warnings(for item: StartupItem) -> [StartupWarning] {
        ownerWarnings[item.id].map { [.ownerMayRecreate($0)] } ?? []
    }
}

func perfTask(_ id: MaintenanceTaskID, detail: Int64? = nil) -> MaintenanceTask {
    MaintenanceTask(id: id, isApplicable: true, isRecommended: true, requiresAdmin: MaintenanceCatalog.adminTasks.contains(id),
                    detail: detail, timeout: .seconds(1))
}

let warpApp = URL(fileURLWithPath: "/Applications/Warp.app")
let googleApp = URL(fileURLWithPath: "/Applications/Google Chrome.app")

func perfReport(tasks: [MaintenanceTask] = [perfTask(.speedUpMail), perfTask(.flushDNS), perfTask(.freeUpPurgeable, detail: 3_800_000_000),
                                            perfTask(.reindexSpotlight), perfTask(.repairPermissions)],
                login: [StartupItem]? = nil, background: [StartupItem]? = nil, snapshots: [LocalSnapshot] = []) -> PerformanceReport {
    PerformanceReport(
        tasks: tasks,
        loginItems: login ?? [StartupItem(kind: .sessionLoginItem, name: "Warp.app", program: warpApp, ownerApp: warpApp, ownerBundleID: "dev.warp")],
        backgroundItems: background ?? [
            StartupItem(kind: .systemDaemon, name: "GoogleUpdater.app", label: "com.google.updater",
                        plist: URL(fileURLWithPath: "/Library/LaunchDaemons/com.google.updater.plist"), ownerApp: googleApp,
                        ownerBundleID: "com.google.Chrome"),
            StartupItem(kind: .userAgent, name: "x.plist", label: "com.example.x",
                        plist: URL(fileURLWithPath: "/Users/me/Library/LaunchAgents/x.plist"), state: .disabled),
        ],
        snapshots: snapshots)
}

@MainActor
struct PerfSetup {
    let maintenance = StubMaintenance()
    let startup = StubStartup()
    let opener = StubOpener()
    let model: PerformanceFlowModel

    init(report: PerformanceReport = perfReport(), delay: Duration = .zero) {
        model = PerformanceFlowModel(scan: StubPerformanceScan(report: report, delay: delay), maintenance: maintenance, startup: startup,
                                     snapshots: { _ in [:] }, context: ScanContext.current(), opener: opener)
    }

    func scanned() async -> PerformanceFlowModel {
        model.start()
        while model.phase == .scanning { await Task.yield() }
        return model
    }
}

@MainActor
@Suite struct PerformanceFlowModelTests {
    @Test func scanThenResults() async {
        let m = await PerfSetup().scanned()
        #expect(m.phase == .results)
        #expect(m.report?.tasks.count == 5)
    }

    @Test func nothingFound() async {
        let m = await PerfSetup(report: perfReport(tasks: [], login: [], background: [])).scanned()
        #expect(m.phase == .nothingFound)
    }

    @Test func stopReturnsToIntro() async {
        let s = PerfSetup(delay: .seconds(5))
        s.model.start()
        #expect(s.model.phase == .scanning)
        s.model.stop()
        #expect(s.model.phase == .intro)
    }

    @Test func runSelectedTasksShowsProgressAndDone() async {
        let s = PerfSetup()
        let m = await s.scanned()
        s.maintenance.failing = [.flushDNS]
        m.runTasks([.speedUpMail, .flushDNS])
        #expect(m.confirmation == nil)
        while m.phase == .acting { await Task.yield() }
        #expect(s.maintenance.requested == [[.speedUpMail, .flushDNS]])
        #expect(m.taskStatus[.speedUpMail] == .succeeded)
        #expect(m.taskStatus[.flushDNS] == .failed("exit 1"))
        guard case .done(let outcome) = m.phase else { Issue.record("sem conclusão"); return }
        #expect(outcome.kind == .maintenance && outcome.succeeded == 1 && outcome.failed.count == 1)
    }

    @Test func heavyTasksAskBeforeRunning() async {
        let s = PerfSetup()
        let m = await s.scanned()
        m.runTasks([.flushDNS, .reindexSpotlight, .freeUpPurgeable])
        #expect(m.confirmation == .heavyTasks([.freeUpPurgeable, .reindexSpotlight]))
        #expect(s.maintenance.requested.isEmpty)
        m.cancelConfirmation()
        #expect(m.confirmation == nil && m.phase == .results)
        m.runTasks([.reindexSpotlight])
        m.confirm()
        while m.phase == .acting { await Task.yield() }
        #expect(s.maintenance.requested == [[.reindexSpotlight]])
    }

    @Test func disableAsksConfirmationWithOwnerWarning() async {
        let s = PerfSetup()
        let m = await s.scanned()
        let google = m.report!.backgroundItems[0]
        s.startup.ownerWarnings[google.id] = googleApp
        m.openManager(.backgroundItems)
        m.selectedItems = [google.id]
        m.requestStartup(.disable)
        #expect(m.confirmation == .startup(.disable, [google], owners: [googleApp]))
        #expect(s.startup.performed.isEmpty)
        m.confirm()
        while m.phase == .acting { await Task.yield() }
        #expect(s.startup.performed.map(\.1) == [[google.id]])
    }
}
