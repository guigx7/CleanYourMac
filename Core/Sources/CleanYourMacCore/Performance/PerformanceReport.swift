import Foundation

/// Resultado da análise do Desempenho.
public struct PerformanceReport: Sendable {
    /// Só as tarefas aplicáveis, na ordem da lista.
    public let tasks: [MaintenanceTask]
    public let loginItems: [StartupItem]
    public let backgroundItems: [StartupItem]
    public let snapshots: [LocalSnapshot]

    public init(tasks: [MaintenanceTask], loginItems: [StartupItem], backgroundItems: [StartupItem], snapshots: [LocalSnapshot]) {
        self.tasks = tasks
        self.loginItems = loginItems
        self.backgroundItems = backgroundItems
        self.snapshots = snapshots
    }

    public var recommendedTasks: [MaintenanceTask] { tasks.filter(\.isRecommended) }

    /// Mesmas chaves de docs/re/parity/perf-baseline-*.json (tarefas por id; compare_perf.py traduz os títulos).
    public func parityJSON() -> [String: Any] {
        [
            "tasks": tasks.map(\.id.rawValue),
            "purgeable": tasks.first { $0.id == .freeUpPurgeable }?.detail as Any? ?? NSNull(),
            "loginItems": loginItems.filter { $0.state == .enabled }.map(\.name),
            "backgroundItems": backgroundItems.map(\.name),
            "tiles": [
                "loginItems": loginItems.filter { $0.state == .enabled }.count,
                "maintenance": recommendedTasks.count,
                "backgroundItems": backgroundItems.count,
            ],
        ]
    }
}

public enum PerformanceScanPhase: String, Sendable {
    case maintenance, loginItems, backgroundItems, timeMachine
}

public enum PerformanceScanEvent: Sendable {
    case progress(PerformanceScanPhase)
    case finished(PerformanceReport)
}

public final class PerformanceScan: Sendable {
    private let facts: @Sendable (ScanContext) -> any MaintenanceFacts
    private let startup: StartupItemsScanner
    private let snapshots: TimeMachineSnapshots

    public init(facts: @escaping @Sendable (ScanContext) -> any MaintenanceFacts = { SystemMaintenanceFacts(home: $0.home) },
                startup: StartupItemsScanner = StartupItemsScanner(), snapshots: TimeMachineSnapshots = TimeMachineSnapshots()) {
        self.facts = facts
        self.startup = startup
        self.snapshots = snapshots
    }

    public func run(_ context: ScanContext) -> AsyncThrowingStream<PerformanceScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.progress(.maintenance))
                    let tasks = MaintenanceCatalog(facts: facts(context)).tasks().filter(\.isApplicable)
                    try Task.checkCancellation()
                    continuation.yield(.progress(.loginItems))
                    let items = startup.items(context)
                    try Task.checkCancellation()
                    continuation.yield(.progress(.backgroundItems))
                    continuation.yield(.progress(.timeMachine))
                    let local = snapshots.list()
                    try Task.checkCancellation()
                    continuation.yield(.finished(PerformanceReport(tasks: tasks, loginItems: items.filter { !$0.isBackground },
                                                                   backgroundItems: items.filter(\.isBackground), snapshots: local)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
