import AppKit
import Observation
import CleanYourMacCore

protocol SpaceLensScanning: Sendable {
    func run(_ target: SpaceLensTarget) -> AsyncThrowingStream<SpaceLensScanEvent, Error>
}

extension SpaceLensScan: SpaceLensScanning {}

/// Remove (para o Lixo) os nós escolhidos; resultado por caminho.
protocol SpaceRemoving: Sendable {
    func remove(_ nodes: [SpaceNode]) async -> [String: Result<Void, CleanFailure>]
}

/// Máquina de estados da Lupa de Espaço: Intro → Análise → Resultados (navegação por pastas) → Revisão → Remoção → Concluído.
@MainActor @Observable
final class SpaceLensFlowModel {
    enum Phase: Equatable {
        case intro, scanning, results, reviewing, removing
        case done(Outcome)
    }

    struct Outcome: Equatable {
        var removed: Int
        var freed: Int64
        /// nome → motivo
        var failed: [String: String]
    }

    private(set) var phase: Phase = .intro
    var target: SpaceLensTarget = .disk
    private(set) var report: SpaceLensReport?
    private(set) var current: SpaceNode?
    private(set) var scanned = 0
    /// Selecionados, sem sobreposição (uma pasta marcada absorve os descendentes).
    private(set) var selection: [SpaceNode] = []
    private var backStack: [SpaceNode] = []
    private var forwardStack: [SpaceNode] = []

    private let scan: any SpaceLensScanning
    private let remover: any SpaceRemoving
    private let isProtected: @MainActor (SpaceNode) -> Bool
    private var task: Task<Void, Never>?

    init(scan: any SpaceLensScanning, remover: any SpaceRemoving, isProtected: @escaping @MainActor (SpaceNode) -> Bool = { _ in false }) {
        self.scan = scan
        self.remover = remover
        self.isProtected = isProtected
    }

    // MARK: - Análise

    func start() {
        task?.cancel()
        phase = .scanning
        scanned = 0
        reset()
        let stream = scan.run(target)
        task = Task {
            do {
                for try await event in stream {
                    switch event {
                    case .progress(let n): scanned = n
                    case .finished(let r):
                        report = r
                        current = r.root
                        phase = .results
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

    /// Voltar para a Intro sem analisar de novo.
    func back() {
        stop()
        reset()
    }

    func restart() { start() }

    private func reset() {
        report = nil
        current = nil
        selection = []
        backStack = []
        forwardStack = []
    }

    // MARK: - Navegação

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func open(_ node: SpaceNode) {
        guard node.isDirectory, node !== current, let current else { return }
        backStack.append(current)
        forwardStack = []
        self.current = node
    }

    func goBack() {
        guard let previous = backStack.popLast(), let current else { return }
        forwardStack.append(current)
        self.current = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast(), let current else { return }
        backStack.append(current)
        self.current = next
    }

    /// Clique no caminho.
    func jump(to node: SpaceNode) { open(node) }

    // MARK: - Seleção

    func isSelected(_ node: SpaceNode) -> Bool {
        let chain = node.ancestry
        return selection.contains { s in chain.contains { $0 === s } }
    }

    /// Itens protegidos, e itens dentro de uma pasta já marcada, não mudam sozinhos.
    func canToggle(_ node: SpaceNode) -> Bool {
        guard !isProtected(node), node.parent != nil else { return false }
        return !node.ancestry.dropLast().contains { a in selection.contains { $0 === a } }
    }

    func toggle(_ node: SpaceNode) {
        guard canToggle(node) else { return }
        if let i = selection.firstIndex(where: { $0 === node }) {
            selection.remove(at: i)
            return
        }
        // A pasta absorve os descendentes já marcados.
        selection.removeAll { s in s.ancestry.contains { $0 === node } }
        selection.append(node)
    }

    func clearSelection() { selection = [] }

    var selectionSize: Int64 { selection.reduce(0) { $0 + $1.size } }

    // MARK: - Revisão e remoção

    func review() {
        guard !selection.isEmpty else { return }
        phase = .reviewing
    }

    func cancelReview() { phase = .results }

    /// Tira um item da revisão.
    func deselect(_ node: SpaceNode) {
        selection.removeAll { $0 === node }
        if selection.isEmpty { phase = .results }
    }

    func confirmRemoval() {
        let nodes = selection
        guard !nodes.isEmpty else { return }
        phase = .removing
        task = Task {
            let results = await remover.remove(nodes)
            var failed: [String: String] = [:]
            var freed: Int64 = 0, removed = 0
            for node in nodes {
                if case .failure(let f) = results[node.path] ?? .failure(.cancelled) {
                    failed[node.name] = f.reason
                } else {
                    freed += node.size
                    removed += 1
                    // Se a pasta atual (ou um ancestral dela) sumiu, volta para o pai que ficou.
                    if let current, current.ancestry.contains(where: { $0 === node }) { self.current = node.parent }
                    node.detach()
                }
            }
            backStack.removeAll { $0.parent == nil && $0 !== report?.root }
            forwardStack = []
            selection = []
            phase = .done(Outcome(removed: removed, freed: freed, failed: failed))
        }
    }

    /// Da tela final de volta aos Resultados, com a árvore já atualizada.
    func backToResults() { phase = .results }
}
