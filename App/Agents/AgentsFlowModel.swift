import Foundation
import Observation
import CleanYourMacCore

protocol AgentsScanning: Sendable {
    func run() -> AsyncThrowingStream<AgentsScanEvent, Error>
}

extension AgentsScan: AgentsScanning {}

protocol AgentsRemoving: Sendable {
    /// Resultado por id do alvo.
    func remove(_ targets: [AgentsTarget]) async -> [String: Result<Void, CleanFailure>]
}

extension AgentsRemover: AgentsRemoving {}

/// Máquina de estados de Agentes de IA: Intro → Análise → Resultados ⇄ Gerenciador → Remoção → Concluído.
@MainActor @Observable
final class AgentsFlowModel {
    enum Phase: Equatable {
        case intro, scanning, results, nothingFound, removing
        case done(Outcome)
    }

    enum Section: String, CaseIterable, Hashable { case worktrees, sessions }

    struct Outcome: Equatable {
        var removed: Int
        var freed: Int64
        /// id da sessão ou caminho da pasta → motivo
        var failed: [String: String]
    }

    private(set) var phase: Phase = .intro
    private(set) var report: AgentsReport? { didSet { index() } }
    private(set) var scanStep: String?
    var managerOpen = false
    var section: Section = .worktrees
    private(set) var selection: Set<String> = []
    /// Ids que o usuário desmarcou à mão: o "Limpar" do cartão não os marca de novo. Marcar outra vez tira daqui.
    private(set) var deselectedByUser: Set<String> = []
    /// Tamanho de cada id marcável (caminho da recriável ou id da sessão): o rodapé não percorre o relatório a cada desenho.
    @ObservationIgnored private var sizeByID: [String: Int64] = [:]
    var confirmingRemoval = false

    private let scan: any AgentsScanning
    private let remover: any AgentsRemoving
    let dryRun: Bool
    private var task: Task<Void, Never>?

    init(scan: any AgentsScanning, remover: any AgentsRemoving, dryRun: Bool = false) {
        self.scan = scan
        self.remover = remover
        self.dryRun = dryRun
    }

    // MARK: - Análise

    func start() {
        task?.cancel()
        phase = .scanning
        report = nil
        scanStep = nil
        selection = []
        deselectedByUser = []
        let stream = scan.run()
        task = Task {
            do {
                for try await event in stream {
                    // Parar (ou outra análise) cancela esta: evento que já estava na fila não vale mais.
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .progress(let step): scanStep = step
                    case .finished(let r):
                        report = r
                        phase = r.isEmpty ? .nothingFound : .results
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

    /// Voltar dos Resultados para a Intro sem analisar de novo.
    func back() {
        task?.cancel()
        task = nil
        managerOpen = false
        confirmingRemoval = false
        selection = []
        deselectedByUser = []
        phase = .intro
    }

    func restart() {
        managerOpen = false
        start()
    }

    private func index() {
        sizeByID = [:]
        guard let report else { return }
        for item in report.worktrees.flatMap(\.items) { sizeByID[item.url.path] = item.size }
        for s in report.sessions { sizeByID[s.id] = s.size }
    }

    // MARK: - Gerenciador

    /// Com `autoselect` (cartão), marca os ids dos cartões da seção; sem (revisar tudo), a seleção fica como está.
    func openManager(_ section: Section, autoselect: Bool = false) {
        self.section = section
        if autoselect { selection.formUnion(tileIDs(section)) }
        managerOpen = true
    }

    func closeManager() { managerOpen = false }

    private func tileIDs(_ section: Section) -> Set<String> {
        guard let report else { return [] }
        var ids = Set<String>()
        for tile in report.tiles {
            switch (section, tile.kind) {
            case (.worktrees, .worktrees), (.sessions, .sessions): ids.formUnion(tile.ids)
            default: break
            }
        }
        return ids
    }

    func isSelected(_ id: String) -> Bool { selection.contains(id) }

    func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
            deselectedByUser.insert(id)
        } else {
            selection.insert(id)
            deselectedByUser.remove(id)
        }
    }

    func setAll(_ ids: [String], selected: Bool) {
        if selected {
            selection.formUnion(ids)
            deselectedByUser.subtract(ids)
        } else {
            selection.subtract(ids)
            deselectedByUser.formUnion(ids)
        }
    }

    func clearSelection() {
        deselectedByUser.formUnion(selection)
        selection = []
    }

    /// "Limpar" de um cartão: marca os ids dele (já só os seguros) menos os que o usuário desmarcou à mão, e pede a
    /// confirmação; quem remove é `confirmRemoval`. Sem nada a marcar, a seleção fica como está.
    func cleanTile(_ tile: AgentsTile) {
        let ids = tile.ids.subtracting(deselectedByUser)
        guard !ids.isEmpty else { return }
        selection = ids
        confirmingRemoval = true
    }

    var selectedCount: Int { selection.filter { sizeByID[$0] != nil }.count }

    var selectedSize: Int64 { selection.reduce(0) { $0 + (sizeByID[$1] ?? 0) } }

    var canRemove: Bool { selectedCount > 0 }

    /// Quantas pastas de build a confirmação nomeia.
    static let confirmListLimit = 8

    /// Pastas marcadas que não são `node_modules`, como `<worktree>/<caminho relativo>`, na ordem do relatório: as
    /// primeiras `confirmListLimit` e quantas sobram ("e mais N"). A confirmação mostra o que sai além das dependências.
    var selectedBuildFolders: (names: [String], more: Int) {
        guard let report else { return ([], 0) }
        var names: [String] = []
        for e in report.worktrees {
            let root = e.worktree.url.path
            for item in e.items where item.name != "node_modules" && selection.contains(item.url.path) {
                let path = item.url.path
                let rel = path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
                names.append(e.worktree.url.lastPathComponent + "/" + rel)
            }
        }
        return (Array(names.prefix(Self.confirmListLimit)), max(0, names.count - Self.confirmListLimit))
    }

    // MARK: - Remoção

    func requestRemoval() {
        guard canRemove else { return }
        confirmingRemoval = true
    }

    func confirmRemoval() {
        confirmingRemoval = false
        guard canRemove, let report else { return }
        let targets = report.targets(for: selection)
        managerOpen = false
        phase = .removing
        task = Task {
            var removed = Set<String>(), failed: [String: String] = [:], freed: Int64 = 0
            let results = await remover.remove(targets)
            for t in targets {
                switch results[t.id] ?? .failure(.cancelled) {
                case .success: removed.insert(t.id); freed += t.size
                case .failure(let e): failed[t.id] = e.reason
                }
            }
            // Fora da lista o que saiu (na simulação também, para o fluxo seguir igual).
            self.report = report.removing(removed)
            selection.subtract(removed)
            phase = .done(Outcome(removed: removed.count, freed: freed, failed: failed))
        }
    }

    /// "Revisar Mais Itens": volta ao Gerenciador com o que sobrou.
    func reviewMore() {
        guard let report else { return }
        if report.isEmpty {
            phase = .nothingFound
            return
        }
        phase = .results
        managerOpen = true
    }
}

/// Monta o fluxo de produção. Debug: `CYM_DRY_RUN=0` desliga a simulação.
@MainActor
enum AgentsEnvironment {
    static func makeModel() -> AgentsFlowModel {
        #if DEBUG
        let dryRun = ProcessInfo.processInfo.environment["CYM_DRY_RUN"] != "0"
        #else
        let dryRun = false
        #endif
        return AgentsFlowModel(scan: AgentsScan(), remover: AgentsRemover(dryRun: dryRun, log: .standard), dryRun: dryRun)
    }
}
