import AppKit
import Observation
import CleanYourMacCore

protocol AppsScanning: Sendable {
    func run(_ context: ScanContext) -> AsyncThrowingStream<AppsScanEvent, Error>
}

extension AppsScan: AppsScanning {}

/// Abre URLs e copia texto (injetável nos testes).
protocol URLOpening: Sendable {
    @discardableResult func open(_ url: URL) -> Bool
    func copy(_ text: String)
}

struct WorkspaceOpener: URLOpening {
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Máquina de estados do módulo Aplicativos: Intro → Análise → Resultados ⇄ Gerenciador → Ação → Concluído.
@MainActor @Observable
final class AppsFlowModel {
    enum Phase: Equatable {
        case intro, scanning, results, nothingFound, acting
        case done(CleanReport)
    }

    enum Section: String, CaseIterable, Hashable { case uninstaller, updater, leftovers }

    struct QuitPrompt: Equatable {
        var apps: [RunningApp]
        /// Depois de uma tentativa normal sem sucesso: oferecer forçar (com confirmação).
        var offerForce = false
        /// Só Redefinir envolve esses apps: dá para seguir sem fechar, com aviso (reset.md, removal.md §Apps abertos).
        var canContinue = false
    }

    struct PendingReset: Equatable { var leaves: [JunkItem] }

    private(set) var phase: Phase = .intro
    private(set) var report: AppsReport?
    private(set) var scanPhase: AppsScanPhase?
    private(set) var currentPath = ""
    var managerOpen = false
    var section: Section = .uninstaller
    var filter: AppFilter = .all
    /// Apps mostrados no modo Redefinir (AppRecord.id).
    var resetApps: Set<String> = []
    let selection = AppsSelection()
    /// Grupos sobre os quais a próxima ação age (a seção visível ou o cartão); nil = todos.
    var actionScope: Set<GroupID>?
    /// Seleção anterior à ação direta de um cartão (devolvida se ela for cancelada).
    private var preparedBackup: [JunkItem]?
    #if DEBUG
    /// Linhas abertas ao entrar no Gerenciador (capturas).
    var debugExpanded: [String] = []
    #endif

    private(set) var quitPrompt: QuitPrompt?
    private(set) var resetConfirmation: PendingReset?
    private(set) var actingItem: JunkItem?
    private(set) var processed = 0
    private(set) var toProcess = 0
    private(set) var failures: [String: String] = [:]
    private(set) var removedIDs: Set<String> = []

    private let scan: any AppsScanning
    private let cleaner: any Cleaning
    private let runningApps: any RunningApps
    private let opener: any URLOpening
    private let helperActive: @MainActor () -> Bool
    let context: ScanContext
    private var task: Task<Void, Never>?
    private var pending: [JunkItem] = []

    init(scan: any AppsScanning, cleaner: any Cleaning, runningApps: any RunningApps, context: ScanContext,
         opener: any URLOpening = WorkspaceOpener(), helperActive: @escaping @MainActor () -> Bool = { false }) {
        self.helperActive = helperActive
        self.scan = scan
        self.cleaner = cleaner
        self.runningApps = runningApps
        self.context = context
        self.opener = opener
    }

    // MARK: - Análise

    func start() {
        task?.cancel()
        phase = .scanning
        report = nil
        selection.clear()
        resetApps = []
        failures = [:]
        removedIDs = []
        let stream = scan.run(context)
        task = Task {
            do {
                for try await event in stream {
                    switch event {
                    case .progress(let p, let path):
                        scanPhase = p
                        currentPath = path
                    case .finished(let r):
                        report = r
                        phase = r.apps.isEmpty ? .nothingFound : .results
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

    // MARK: - Gerenciador

    func openManager(_ section: Section, filter: AppFilter? = nil) {
        self.section = section
        if let filter { self.filter = filter }
        managerOpen = true
    }

    func closeManager() { managerOpen = false }

    /// O item do app no modo atual (desinstalar ou redefinir).
    func displayedItem(for item: JunkItem) -> JunkItem {
        guard let id = item.leaves.first.flatMap({ AppItemID.appID(of: $0.id) }), resetApps.contains(id),
              let reset = UninstallerScanner.resetItem(from: item, context: context) else { return item }
        return reset
    }

    func setReset(_ on: Bool, for item: JunkItem) {
        guard let id = item.leaves.first.flatMap({ AppItemID.appID(of: $0.id) }) else { return }
        // Troca de modo: a seleção do outro modo deixa de valer.
        selection.set(selection.selectedLeaves.filter { AppItemID.appID(of: $0.id) == id }, on: false)
        if on { resetApps.insert(id) } else { resetApps.remove(id) }
    }

    // MARK: - Ação

    /// O que a ação vai exigir: Gerenciamento de Apps para mexer em apps de /Applications;
    /// senha (sem o ajudante) para itens fora da pasta do usuário.
    func requirements(_ leaves: [JunkItem]) -> Set<CleanupFlowModel.CleanRequirement> {
        var out: Set<CleanupFlowModel.CleanRequirement> = []
        let apps = PathPolicy.realPath(context.resolve("/Applications").path) + "/"
        let home = PathPolicy.realPath(context.home.path) + "/"
        for leaf in leaves {
            guard let url = leaf.url else { continue }
            let path = PathPolicy.realPath(url.path)
            let inApps = path.hasPrefix(apps)
            if case .trashAppBundle = leaf.removal, inApps { out.insert(.appManagement) }
            guard !helperActive(), !path.hasPrefix(home), !path.hasPrefix("/private/var/folders/") else { continue }
            // Em /Applications, só o que não é do usuário (ex.: apps da App Store, de root) pede senha.
            var st = stat()
            if !inApps || (lstat(path, &st) == 0 && st.st_uid != getuid()) { out.insert(.admin) }
        }
        return out
    }

    /// O que a ação vai levar: a seleção, limitada ao escopo atual.
    var pendingLeaves: [JunkItem] {
        guard let scope = actionScope else { return selection.selectedLeaves }
        return selection.selectedLeaves.filter { scope.contains($0.group) }
    }

    func act() {
        let leaves = pendingLeaves
        preparedBackup = nil
        guard !leaves.isEmpty else { return }
        pending = leaves
        func owners(_ mode: AppItemID.Mode) -> Set<String> {
            Set(leaves.compactMap { AppItemID.mode(of: $0.id) == mode ? AppItemID.owner(of: $0.id) : nil })
        }
        let uninstall = owners(.uninstall), reset = owners(.reset)
        let open = uninstall.union(reset).isEmpty ? [] : runningApps.running(bundleIDs: uninstall.union(reset))
        if !open.isEmpty {
            quitPrompt = QuitPrompt(apps: open, canContinue: open.allSatisfy { !uninstall.contains($0.bundleID) })
            return
        }
        continueAfterQuit()
    }

    /// Redefinir com o app aberto: segue sem fechar (o app pode recriar arquivos; o aviso está no diálogo).
    func continueWithoutQuitting() {
        guard quitPrompt?.canContinue == true else { return }
        quitPrompt = nil
        continueAfterQuit()
    }

    /// Ação direta de um cartão: marca os recomendados dos itens, guardando a seleção anterior.
    func prepare(_ items: [JunkItem], scope: Set<GroupID>) {
        preparedBackup = selection.selectedLeaves
        selection.clear()
        for item in items { selection.set(AppsSelection.selectable(item).filter(\.isRecommended), on: true) }
        actionScope = scope
    }

    /// A confirmação do cartão foi cancelada: volta a seleção de antes.
    func cancelPrepared() {
        guard let backup = preparedBackup else { return }
        selection.clear()
        selection.set(backup, on: true)
        preparedBackup = nil
        actionScope = nil
    }

    func quitAndContinue(force: Bool) async {
        guard var prompt = quitPrompt else { return }
        var stillOpen: [RunningApp] = []
        for app in prompt.apps where !(await runningApps.quit(app, force: force)) { stillOpen.append(app) }
        if stillOpen.isEmpty {
            quitPrompt = nil
            continueAfterQuit()
        } else {
            prompt.apps = stillOpen
            prompt.offerForce = true
            quitPrompt = prompt
        }
    }

    func cancelQuit() {
        quitPrompt = nil
        pending = []
        actionScope = nil
    }

    private func continueAfterQuit() {
        let resetLeaves = pending.filter { AppItemID.mode(of: $0.id) == .reset }
        if UninstallerScanner.needsResetConfirmation(resetLeaves) {
            resetConfirmation = PendingReset(leaves: resetLeaves.filter {
                $0.detail == ResourceKind.container.rawValue || $0.detail == ResourceKind.userData.rawValue
            })
            return
        }
        perform(pending)
    }

    func confirmReset() {
        resetConfirmation = nil
        perform(pending)
    }

    func cancelReset() {
        resetConfirmation = nil
        pending = []
        actionScope = nil
    }

    private func perform(_ leaves: [JunkItem]) {
        pending = []
        actionScope = nil
        managerOpen = false
        phase = .acting
        processed = 0
        toProcess = leaves.count
        failures = [:]
        let stream = cleaner.clean(leaves)
        task = Task {
            var final: CleanReport?
            for await event in stream {
                switch event {
                case .started(let item):
                    actingItem = item
                case .finished(let item, let result):
                    processed += 1
                    switch result {
                    case .success: removedIDs.insert(item.id)
                    case .failure(let f): failures[item.id] = f.reason
                    }
                case .completed(let r):
                    final = r
                }
            }
            actingItem = nil
            selection.clear()
            phase = .done(final ?? CleanReport(freedBytes: 0, removed: Array(removedIDs), failed: failures, dryRun: false))
        }
    }

    // MARK: - Atualizador

    func perform(_ action: UpdateAction) {
        switch action {
        case .openAppStore(let url, let fallback):
            if !opener.open(url), let fallback { opener.open(fallback) }
        case .openSoftwareUpdate:
            opener.open(URL(string: "x-apple.systempreferences:com.apple.preferences.softwareupdate")!)
        case .openApp(let url, _):
            opener.open(url)
        case .copyCommand(let command, _):
            opener.copy(command)
        }
    }
}

/// Monta o fluxo com a análise e a remoção de produção. Debug: `CYM_DRY_RUN=0` desliga a simulação.
@MainActor
enum AppsEnvironment {
    static func makeModel() -> AppsFlowModel {
        let env = ProcessInfo.processInfo.environment
        let context = ScanContext.current()
        #if DEBUG
        let dryRun = env["CYM_DRY_RUN"] != "0"
        #else
        let dryRun = false
        #endif
        let helper = HelperManager.shared.state == .active
        let cleaner = CleanEngine(policyProvider: { Registry.appsPolicies(context: context) }, privileged: AppPrivilegedRunner(),
                                  dryRun: dryRun, log: .standard)
        var scan: any AppsScanning = Registry.appsScan(privilegedAvailable: helper)
        #if DEBUG
        if env["CYM_DEMO"] == "1" { scan = AppsDemoData.scan }
        #endif
        _ = env
        return AppsFlowModel(scan: scan, cleaner: cleaner, runningApps: WorkspaceRunningApps(), context: context,
                             helperActive: { HelperManager.shared.state == .active })
    }
}
