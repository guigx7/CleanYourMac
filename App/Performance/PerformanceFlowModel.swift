import AppKit
import Observation
import CleanYourMacCore

protocol PerformanceScanning: Sendable {
    func run(_ context: ScanContext) -> AsyncThrowingStream<PerformanceScanEvent, Error>
}

extension PerformanceScan: PerformanceScanning {}

protocol MaintenanceRunning: Sendable {
    func run(_ tasks: [MaintenanceTask]) -> AsyncStream<MaintenanceEvent>
}

extension MaintenanceRunner: MaintenanceRunning {}

protocol StartupActing: Sendable {
    func perform(_ action: StartupAction, on items: [StartupItem]) async -> [String: Result<Void, CleanFailure>]
    func warnings(for item: StartupItem) -> [StartupWarning]
}

extension StartupItemsActions: StartupActing {}

/// Máquina de estados do módulo Desempenho: Intro → Análise → Resultados ⇄ Gerenciador → Ação → Concluído.
@MainActor @Observable
final class PerformanceFlowModel {
    enum Phase: Equatable {
        case intro, scanning, results, nothingFound, acting
        case done(Outcome)
    }

    enum Section: String, CaseIterable, Hashable { case maintenance, loginItems, backgroundItems, snapshots }

    enum TaskStatus: Equatable { case waiting, running, succeeded, failed(String) }

    enum OutcomeKind: Equatable {
        case maintenance
        case startup(StartupAction)
        case snapshots
    }

    struct Outcome: Equatable {
        var kind: OutcomeKind
        var succeeded: Int
        /// nome → motivo
        var failed: [String: String]
    }

    enum Confirmation: Equatable {
        /// Tarefas demoradas (Reindexar o Spotlight, Liberar Espaço Purgável): aviso antes de rodar.
        case heavyTasks([MaintenanceTaskID])
        /// Itens e os apps donos que podem recriá-los.
        case startup(StartupAction, [StartupItem], owners: [URL])
        case snapshots([LocalSnapshot])
    }

    static let heavyTasks: [MaintenanceTaskID] = [.freeUpPurgeable, .reindexSpotlight]
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    private(set) var phase: Phase = .intro
    private(set) var report: PerformanceReport?
    private(set) var scanPhase: PerformanceScanPhase?
    var managerOpen = false
    var section: Section = .maintenance
    var selectedTasks: Set<MaintenanceTaskID> = []
    var selectedItems: Set<String> = []
    var selectedSnapshots: Set<String> = []
    private(set) var confirmation: Confirmation?
    private(set) var taskStatus: [MaintenanceTaskID: TaskStatus] = [:]
    /// Itens modernos que só os Ajustes desligam (o guia mostra os nomes).
    private(set) var settingsHint: [String]?
    /// "Abrir no Desinstalador": o RootView troca para o módulo Aplicativos.
    var onOpenUninstaller: ((URL) -> Void)?

    private let scan: any PerformanceScanning
    private let maintenance: any MaintenanceRunning
    private let startup: any StartupActing
    private let deleteSnapshots: @Sendable ([LocalSnapshot]) -> [String: Result<Void, CleanFailure>]
    private let opener: any URLOpening
    let context: ScanContext
    /// Debug simula por padrão: a conclusão avisa que nada foi alterado.
    let dryRun: Bool
    private var task: Task<Void, Never>?
    private var pendingTasks: [MaintenanceTaskID] = []

    init(scan: any PerformanceScanning, maintenance: any MaintenanceRunning, startup: any StartupActing,
         snapshots: @escaping @Sendable ([LocalSnapshot]) -> [String: Result<Void, CleanFailure>], context: ScanContext,
         opener: any URLOpening = WorkspaceOpener(), dryRun: Bool = false) {
        self.dryRun = dryRun
        self.scan = scan
        self.maintenance = maintenance
        self.startup = startup
        self.deleteSnapshots = snapshots
        self.context = context
        self.opener = opener
    }

    // MARK: - Análise

    func start() {
        task?.cancel()
        phase = .scanning
        report = nil
        clearSelection()
        taskStatus = [:]
        let stream = scan.run(context)
        task = Task {
            do {
                for try await event in stream {
                    switch event {
                    case .progress(let p): scanPhase = p
                    case .finished(let r):
                        report = r
                        let empty = r.tasks.isEmpty && r.loginItems.isEmpty && r.backgroundItems.isEmpty && r.snapshots.isEmpty
                        phase = empty ? .nothingFound : .results
                    }
                }
            } catch {
                if phase == .scanning { phase = .intro }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        phase = .intro
    }

    func restart() {
        managerOpen = false
        start()
    }

    private func clearSelection() {
        selectedTasks = []
        selectedItems = []
        selectedSnapshots = []
    }

    // MARK: - Gerenciador

    func openManager(_ section: Section) {
        self.section = section
        managerOpen = true
    }

    func closeManager() { managerOpen = false }

    /// Itens da seção visível (Itens de Início ou em Segundo Plano).
    var visibleItems: [StartupItem] {
        switch section {
        case .loginItems: report?.loginItems ?? []
        case .backgroundItems: report?.backgroundItems ?? []
        default: []
        }
    }

    /// Quantos itens o rodapé conta: só os da seção visível (a ação também só leva esses).
    var footerCount: Int {
        switch section {
        case .maintenance: (report?.tasks ?? []).filter { selectedTasks.contains($0.id) }.count
        case .loginItems, .backgroundItems: visibleItems.filter { selectedItems.contains($0.id) }.count
        case .snapshots: (report?.snapshots ?? []).filter { selectedSnapshots.contains($0.id) }.count
        }
    }

    /// Data da última execução bem-sucedida (gravada pelo MaintenanceRunner).
    func lastRun(_ id: MaintenanceTaskID) -> Date? {
        UserDefaults.standard.object(forKey: UserDefaultsMaintenanceHistory.key(id)) as? Date
    }

    // MARK: - Tarefas

    func runSelectedTasks() { runTasks(Array(selectedTasks)) }

    func runTasks(_ ids: [MaintenanceTaskID]) {
        let order = (report?.tasks ?? []).map(\.id).filter(ids.contains)
        guard !order.isEmpty else { return }
        pendingTasks = order
        let heavy = Self.heavyTasks.filter(order.contains)
        if !heavy.isEmpty {
            confirmation = .heavyTasks(heavy)
            return
        }
        performTasks()
    }

    private func performTasks() {
        let tasks = (report?.tasks ?? []).filter { pendingTasks.contains($0.id) }
        pendingTasks = []
        managerOpen = false
        phase = .acting
        taskStatus = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, .waiting) })
        let stream = maintenance.run(tasks)
        task = Task {
            for await event in stream {
                switch event {
                case .started(let id): taskStatus[id] = .running
                case .finished(let id, let r):
                    if case .failure(let f) = r { taskStatus[id] = .failed(f.reason) } else { taskStatus[id] = .succeeded }
                case .completed: break
                }
            }
            // O que não terminou (Parar no meio) fica como cancelado.
            for (id, s) in taskStatus where s == .waiting || s == .running { taskStatus[id] = .failed("cancelled") }
            selectedTasks = []
            let failed = Dictionary(uniqueKeysWithValues: taskStatus.compactMap { id, s -> (String, String)? in
                if case .failed(let r) = s { (id.rawValue, r) } else { nil }
            })
            phase = .done(Outcome(kind: .maintenance, succeeded: taskStatus.values.filter { $0 == .succeeded }.count, failed: failed))
        }
    }

    /// Parar durante a execução: encerra a tarefa em andamento; as restantes ficam canceladas.
    func stopActing() {
        task?.cancel()
    }

    // MARK: - Itens de início e em segundo plano

    var enabledVisibleItems: [StartupItem] { visibleItems.filter { $0.state == .enabled } }
    /// Grupo "Desativados", com Reativar.
    var disabledVisibleItems: [StartupItem] { visibleItems.filter { $0.state == .disabled } }

    /// Botões do rodapé conforme o que está marcado: Desativar (ativos), Reativar (desativados) e Remover.
    var footerActions: [StartupAction] {
        let marked = visibleItems.filter { selectedItems.contains($0.id) }
        var out: [StartupAction] = []
        if marked.isEmpty || marked.contains(where: { $0.state == .enabled }) { out.append(.disable) }
        if marked.contains(where: { $0.state == .disabled }) { out.append(.enable) }
        out.append(.remove)
        return out
    }

    func requestStartup(_ action: StartupAction) {
        let items = visibleItems.filter { item in
            guard selectedItems.contains(item.id) else { return false }
            switch action {
            case .disable: return item.state == .enabled
            case .enable: return item.state == .disabled
            case .remove: return true
            }
        }
        guard !items.isEmpty else { return }
        let modern = items.filter { $0.kind == .modern }
        if !modern.isEmpty {
            settingsHint = modern.map(\.name)
            opener.open(Self.settingsURL)
            return
        }
        // Ao reativar não há o que avisar; ao desativar ou remover, o app dono pode recolocar o item.
        var owners: [URL] = []
        if action != .enable {
            for item in items {
                for case .ownerMayRecreate(let app) in startup.warnings(for: item) where !owners.contains(app) { owners.append(app) }
            }
        }
        confirmation = .startup(action, items, owners: owners)
    }

    func dismissSettingsHint() { settingsHint = nil }

    private func performStartup(_ action: StartupAction, _ items: [StartupItem]) {
        managerOpen = false
        phase = .acting
        task = Task {
            let results = await startup.perform(action, on: items)
            var failed: [String: String] = [:]
            for item in items { if case .failure(let f) = results[item.id] ?? .failure(.cancelled) { failed[item.name] = f.reason } }
            selectedItems = []
            phase = .done(Outcome(kind: .startup(action), succeeded: items.count - failed.count, failed: failed))
        }
    }

    // MARK: - Capturas

    func requestDeleteSnapshots() {
        let list = (report?.snapshots ?? []).filter { selectedSnapshots.contains($0.id) }
        guard !list.isEmpty else { return }
        confirmation = .snapshots(list)
    }

    private func performSnapshots(_ list: [LocalSnapshot]) {
        managerOpen = false
        phase = .acting
        let delete = deleteSnapshots
        task = Task {
            let results = await Task.detached { delete(list) }.value
            var failed: [String: String] = [:]
            for s in list { if case .failure(let f) = results[s.id] ?? .failure(.cancelled) { failed[s.id] = f.reason } }
            selectedSnapshots = []
            phase = .done(Outcome(kind: .snapshots, succeeded: list.count - failed.count, failed: failed))
        }
    }

    // MARK: - Confirmação

    func confirm() {
        guard let c = confirmation else { return }
        confirmation = nil
        switch c {
        case .heavyTasks: performTasks()
        case .startup(let action, let items, _): performStartup(action, items)
        case .snapshots(let list): performSnapshots(list)
        }
    }

    func cancelConfirmation() {
        confirmation = nil
        pendingTasks = []
    }

    func openUninstaller(_ app: URL) {
        confirmation = nil
        onOpenUninstaller?(app)
    }
}

/// Monta o fluxo de produção. Debug: `CYM_DRY_RUN=0` desliga a simulação.
@MainActor
enum PerformanceEnvironment {
    static func makeModel() -> PerformanceFlowModel {
        let context = ScanContext.current()
        #if DEBUG
        let dryRun = ProcessInfo.processInfo.environment["CYM_DRY_RUN"] != "0"
        #else
        let dryRun = false
        #endif
        let privileged = AppPrivilegedRunner()
        let snapshots = TimeMachineSnapshots()
        return PerformanceFlowModel(
            scan: Registry.performanceScan(),
            maintenance: MaintenanceRunner(privileged: privileged, dryRun: dryRun, log: .standard),
            startup: StartupItemsActions(privileged: privileged, context: context, dryRun: dryRun),
            snapshots: { snapshots.delete($0, dryRun: dryRun) }, context: context, dryRun: dryRun)
    }
}
