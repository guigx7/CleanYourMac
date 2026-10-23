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
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func setAll(_ ids: [String], selected: Bool) {
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func clearSelection() { selection = [] }

    /// "Limpar" de um cartão: marca exatamente os ids dele (já só os seguros) e pede a confirmação; quem remove é `confirmRemoval`.
    func cleanTile(_ tile: AgentsTile) {
        selection = tile.ids
        confirmingRemoval = !tile.ids.isEmpty
    }

    var selectedCount: Int { selection.filter { sizeByID[$0] != nil }.count }

    var selectedSize: Int64 { selection.reduce(0) { $0 + (sizeByID[$1] ?? 0) } }

    var canRemove: Bool { selectedCount > 0 }

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
