import CoreServices
import Foundation

public enum MaintenanceEvent: Sendable {
    case started(MaintenanceTaskID)
    case finished(MaintenanceTaskID, Result<Void, CleanFailure>)
    case completed(MaintenanceReport)
}

public struct MaintenanceReport: Codable, Sendable, Equatable {
    public let succeeded: [MaintenanceTaskID]
    /// tarefa → motivo ("cancelled", "timed out", "exit 1"…)
    public let failed: [MaintenanceTaskID: String]
    public let dryRun: Bool
    public let date: Date

    public init(succeeded: [MaintenanceTaskID], failed: [MaintenanceTaskID: String], dryRun: Bool, date: Date = Date()) {
        self.succeeded = succeeded
        self.failed = failed
        self.dryRun = dryRun
        self.date = date
    }
}

/// Libera o espaço purgável do volume de inicialização (API pública `CSDiskSpaceStartRecovery`).
public protocol PurgeableSpace: Sendable {
    func recover(timeout: Duration) async -> ProcessOutcome
}

/// Data da última execução de cada tarefa (só informativa; ver maintenance-tasks.md §Recomendada).
public protocol MaintenanceHistory: Sendable {
    func record(_ id: MaintenanceTaskID, at date: Date)
}

public struct UserDefaultsMaintenanceHistory: MaintenanceHistory {
    public init() {}
    public static func key(_ id: MaintenanceTaskID) -> String { "maintenanceLastRun.\(id.rawValue)" }
    public func record(_ id: MaintenanceTaskID, at date: Date) { UserDefaults.standard.set(date, forKey: Self.key(id)) }
}

/// Executa as tarefas: as de root num único lote do ajudante (uma senha), as outras uma a uma, com tempo-limite.
public final class MaintenanceRunner: Sendable {
    private let processes: any ProcessRunner
    private let privileged: any PrivilegedRunner
    private let purgeable: any PurgeableSpace
    private let history: any MaintenanceHistory
    private let home: URL
    private let dryRun: Bool
    private let log: CleanupLog

    public init(processes: any ProcessRunner = SystemProcessRunner(), privileged: any PrivilegedRunner,
                purgeable: any PurgeableSpace = SystemPurgeableSpace(), history: any MaintenanceHistory = UserDefaultsMaintenanceHistory(),
                home: URL = FileManager.default.homeDirectoryForCurrentUser, dryRun: Bool, log: CleanupLog) {
        self.processes = processes
        self.privileged = privileged
        self.purgeable = purgeable
        self.history = history
        self.home = home
        self.dryRun = dryRun
        self.log = log
    }

    /// Comandos sem root de cada tarefa (maintenance-tasks.md §Tabela-resumo). As de root vão para o ajudante.
    func steps(_ id: MaintenanceTaskID) -> [(String, [String])] {
        switch id {
        case .speedUpMail: [("/usr/bin/mdimport", [home.appendingPathComponent("Library/Mail").path])]
        case .thinSnapshots: [("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "1073741824", "3"])]
        default: []
        }
    }

    /// Cancelar a Task que consome o stream encerra o processo em andamento; essa tarefa e as seguintes ficam
    /// "cancelled" no registro.
    public func run(_ tasks: [MaintenanceTask]) -> AsyncStream<MaintenanceEvent> {
        AsyncStream { continuation in
            let work = Task {
                var results: [MaintenanceTaskID: Result<Void, CleanFailure>] = [:]
                func finish(_ id: MaintenanceTaskID, _ r: Result<Void, CleanFailure>) {
                    results[id] = r
                    if case .success = r, !dryRun { history.record(id, at: Date()) }
                    continuation.yield(.finished(id, r))
                }
                let root = tasks.filter(\.requiresAdmin), user = tasks.filter { !$0.requiresAdmin }
                if dryRun {
                    for t in tasks {
                        continuation.yield(.started(t.id))
                        finish(t.id, .success(()))
                    }
                } else {
                    if !root.isEmpty, !Task.isCancelled {
                        for t in root { continuation.yield(.started(t.id)) }
                        do throws(PrivilegedError) {
                            let out = try await privileged.run(root.map { .maintenance($0.id) })
                            for (i, t) in root.enumerated() {
                                finish(t.id, out.indices.contains(i) ? out[i] : .failure(CleanFailure(reason: "no result")))
                            }
                        } catch {
                            let reason = switch error {
                            case .userCancelled: CleanFailure.cancelled
                            case .failed(let message): CleanFailure(reason: message)
                            }
                            for t in root { finish(t.id, .failure(reason)) }
                        }
                    }
                    for t in user {
                        if Task.isCancelled { break }
                        continuation.yield(.started(t.id))
                        finish(t.id, await runUser(t))
                    }
                }
                var failed: [MaintenanceTaskID: String] = [:]
                for t in tasks {
                    if case .failure(let f) = results[t.id] ?? .failure(.cancelled) { failed[t.id] = f.reason }
                }
                let report = MaintenanceReport(succeeded: tasks.map(\.id).filter { failed[$0] == nil }, failed: failed, dryRun: dryRun)
                try? log.write(report)
                continuation.yield(.completed(report))
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private func runUser(_ task: MaintenanceTask) async -> Result<Void, CleanFailure> {
        let start = ContinuousClock.now
        if task.id == .freeUpPurgeable { return Self.result(await purgeable.recover(timeout: task.timeout)) }
        for (exe, args) in steps(task.id) {
            let left = task.timeout - (ContinuousClock.now - start)
            let r = Self.result(await processes.run(exe, args, timeout: max(left, .zero)))
            if case .failure = r { return r }
        }
        return .success(())
    }

    static func result(_ outcome: ProcessOutcome) -> Result<Void, CleanFailure> {
        switch outcome {
        case .exited(0): .success(())
        case .exited(let s): .failure(CleanFailure(reason: "exit \(s)"))
        case .timedOut: .failure(CleanFailure(reason: "timed out"))
        case .cancelled: .failure(.cancelled)
        }
    }
}

public struct SystemPurgeableSpace: PurgeableSpace {
    public init() {}

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func first() -> Bool { lock.withLock { defer { done = true }; return !done } }
    }

    public func recover(timeout: Duration) async -> ProcessOutcome {
        let root = URL(fileURLWithPath: "/")
        let estimate = CSDiskSpaceGetRecoveryEstimate(root as CFURL)
        let free = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map { UInt64($0) } ?? 0
        guard estimate > 0 else { return .exited(0) }
        var operation: Unmanaged<CFUUID>?
        let once = Once()
        let outcome: ProcessOutcome = await withCheckedContinuation { cont in
            CSDiskSpaceStartRecovery(root as CFURL, free + estimate, CSDiskSpaceRecoveryOptions(kCSDiskSpaceRecoveryOptionNoUI),
                                     &operation, DispatchQueue.global()) { ok, _, _ in
                if once.first() { cont.resume(returning: ok ? .exited(0) : .exited(1)) }
            }
            let id = operation?.takeUnretainedValue()
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                if once.first() {
                    if let id { CSDiskSpaceCancelRecovery(id) }
                    cont.resume(returning: .timedOut)
                }
            }
        }
        return outcome
    }
}
