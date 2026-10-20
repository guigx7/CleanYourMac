import Foundation
import Observation
import CleanYourMacCore

/// Máquina de estados do módulo Limpeza: Intro → Análise → Resultados ⇄ Revisão → Limpeza → Concluído.
@MainActor @Observable
final class CleanupFlowModel {
    enum Phase: Equatable {
        case intro, scanning, results, review, cleaning, nothingFound
        case done(CleanReport)
    }

    private(set) var phase: Phase = .intro
    private(set) var currentPath = ""
    private(set) var currentGroup: GroupID?
    private(set) var bytesFound: Int64 = 0
    private(set) var report: ScanReport?
    private(set) var reviewCategory: CategoryID?
    let selection = SelectionModel()

    // Limpeza
    private(set) var cleaningItem: JunkItem?
    private(set) var freedBytes: Int64 = 0
    private(set) var bytesToClean: Int64 = 0
    /// id do item → motivo
    private(set) var failures: [String: String] = [:]
    /// Itens não processados porque o usuário parou a limpeza.
    private(set) var stoppedItems: [JunkItem] = []
    private(set) var cleanedLeaves: [JunkItem] = []
    /// Bytes removidos por cartão, para o estado "concluído" dos Resultados.
    private(set) var completedTiles: [ResultTile.Kind: Int64] = [:]
    /// A análise foi interrompida e o resultado está incompleto.
    private(set) var isPartial = false

    enum FreedKind: Hashable { case junk, mail, trash }

    /// O que a limpeza vai exigir do usuário, para confirmar antes.
    enum CleanRequirement: Hashable { case admin, appManagement }
    enum AdminMeasureState: Equatable { case idle, measuring, done, cancelled }
    private(set) var adminMeasure: AdminMeasureState = .idle

    private let scanEngine: ScanEngine
    private let cleanEngine: any Cleaning
    private var pendingLeaves: [JunkItem] = []
    private var finishedGroups: [GroupID: GroupResult] = [:]
    private let context: ScanContext
    private let groups: Set<GroupID>
    private let privileged: any PrivilegedRunner
    private var task: Task<Void, Never>?
    private var bytesByGroup: [GroupID: Int64] = [:]

    init(scanEngine: ScanEngine, cleanEngine: any Cleaning, context: ScanContext, groups: Set<GroupID>,
         privileged: any PrivilegedRunner = AppleScriptPrivilegedRunner()) {
        self.scanEngine = scanEngine
        self.cleanEngine = cleanEngine
        self.context = context
        self.groups = groups
        self.privileged = privileged
    }

    func cleanRequirements(_ items: [JunkItem]) -> Set<CleanRequirement> {
        let leaves = items.flatMap(\.leaves)
        var out: Set<CleanRequirement> = []
        if leaves.contains(where: { $0.group.requiresAdmin }) { out.insert(.admin) }
        if leaves.contains(where: { [.universalBinaries, .languageFiles].contains($0.group) }) { out.insert(.appManagement) }
        return out
    }

    /// Há grupos que só podem ser medidos com senha de administrador e ainda não foram.
    var canMeasureAdminGroups: Bool {
        report != nil && groups.contains(where: \.requiresAdminToScan) && adminMeasure != .done
    }

    /// Mede o Cache do Sistema com privilégio (uma senha) e atualiza o resultado.
    func measureAdminGroups() async {
        guard let report, adminMeasure != .measuring else { return }
        adminMeasure = .measuring
        do {
            let result = try await AdminMeasure.systemCache(context: context, runner: privileged)
            var groups = report.groups
            groups[.systemCache] = result
            self.report = ScanReport(groups: groups)
            selection.load(self.report!)
            adminMeasure = .done
            if phase == .nothingFound, self.report?.isEmpty == false { phase = .results }
        } catch {
            adminMeasure = .cancelled
        }
    }

    var cleaningFraction: Double {
        bytesToClean > 0 ? min(1, Double(freedBytes) / Double(bytesToClean)) : 0
    }

    func startScan() {
        task?.cancel()
        resetScan()
        completedTiles = [:]
        phase = .scanning
        let stream = scanEngine.scan(groups, context: context)
        task = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(event)
                }
            } catch {
                // Cancelamento: stopScan já levou o fluxo de volta à Intro.
            }
        }
    }

    /// Parar a análise: mostra o que já foi achado (results-screen §5); sem nada, volta à Intro.
    func stopScan() {
        task?.cancel()
        task = nil
        let partial = ScanReport(groups: finishedGroups)
        guard phase == .scanning, !partial.isEmpty else {
            resetScan()
            phase = .intro
            return
        }
        report = partial
        isPartial = true
        selection.load(partial)
        currentPath = ""
        currentGroup = nil
        phase = .results
    }

    /// Recomeçar: descarta resultados e seleção e volta à Intro.
    func restart() {
        task?.cancel()
        task = nil
        resetScan()
        resetCleaning()
        completedTiles = [:]
        selection.clear()
        phase = .intro
    }

    func openReview(category: CategoryID? = nil) {
        guard report != nil else { return }
        reviewCategory = category ?? CategoryID.allCases.first { (report?.totalSize(of: $0) ?? 0) > 0 }
        phase = .review
    }

    /// Voltar do Gerenciador descarta a seleção (a view confirma antes, se houver mudanças).
    func closeReview() {
        selection.clear()
        phase = report?.isEmpty == false ? .results : .nothingFound
    }

    /// OK na tela de conclusão: volta aos Resultados sem os itens removidos.
    func acknowledgeDone() {
        guard let report else { phase = .intro; return }
        let removed = Set(cleanedLeaves.map(\.id))
        var groups: [GroupID: GroupResult] = [:]
        for (g, result) in report.groups {
            groups[g] = GroupResult(group: g, items: result.items.compactMap { Self.removing(removed, from: $0) })
        }
        for kind in ResultTile.Kind.allCases {
            let bytes = cleanedLeaves.filter { kind.groups.contains($0.group) }.reduce(0) { $0 + $1.totalSize }
            if bytes > 0 { completedTiles[kind, default: 0] += bytes }
        }
        self.report = ScanReport(groups: groups)
        selection.load(self.report!)
        resetCleaning()
        phase = .results
    }

    /// "Revisar itens restantes": volta ao Gerenciador com as falhas marcadas.
    func reviewRemaining() {
        let leaves = pendingLeaves.filter { failures[$0.id] != nil } + stoppedItems
        acknowledgeDone()
        reviewCategory = leaves.first?.group.category ?? reviewCategory
        selection.replaceSelection(with: leaves)
        phase = .review
    }

    /// Parar a limpeza: os itens ainda não processados ficam como "parados".
    func stopCleaning() {
        guard phase == .cleaning else { return }
        task?.cancel()
        task = nil
        let processed = Set(cleanedLeaves.map(\.id)).union(failures.keys)
        stoppedItems = pendingLeaves.filter { !processed.contains($0.id) && $0.id != cleaningItem?.id }
        if let current = cleaningItem, !processed.contains(current.id) { stoppedItems.append(current) }
        cleaningItem = nil
        phase = .done(CleanReport(freedBytes: freedBytes, removed: cleanedLeaves.map(\.id), failed: failures,
                                  dryRun: false))
    }

    var freedByKind: [FreedKind: Int64] {
        var out: [FreedKind: Int64] = [:]
        for leaf in cleanedLeaves {
            let kind: FreedKind = switch leaf.group.category {
            case .mailAttachments: .mail
            case .trashBins: .trash
            default: .junk
            }
            out[kind, default: 0] += leaf.totalSize
        }
        return out
    }

    var hasFailures: Bool { !failures.isEmpty || !stoppedItems.isEmpty }

    /// Itens que falharam, com o motivo técnico (a interface traduz com `FailureText`).
    var failedItems: [(JunkItem, String)] {
        pendingLeaves.compactMap { item in failures[item.id].map { (item, $0) } }
    }

    private static func removing(_ ids: Set<String>, from item: JunkItem) -> JunkItem? {
        if ids.contains(item.id) { return nil }
        guard !item.children.isEmpty else { return item }
        let children = item.children.compactMap { removing(ids, from: $0) }
        if children.isEmpty { return nil }
        return JunkItem(id: item.id, group: item.group, name: item.name, detail: item.detail, url: item.url,
                        size: item.size, isRecommended: item.isRecommended, badge: item.badge, icon: item.icon,
                        removal: item.removal, children: children, displaysChildren: item.displaysChildren,
                        titleKey: item.titleKey)
    }

    /// Limpar de um cartão: só os itens recomendados dos grupos do cartão.
    func clean(tile kind: ResultTile.Kind) {
        let groups = Set(kind.groups)
        clean(items: report?.recommendedItems().filter { groups.contains($0.group) } ?? [])
    }

    func clean(items: [JunkItem]) {
        let leaves = items.flatMap(\.leaves).filter { $0.removal != nil }
        guard !leaves.isEmpty else { return }
        task?.cancel()
        resetCleaning()
        bytesToClean = leaves.reduce(0) { $0 + $1.totalSize }
        pendingLeaves = leaves
        phase = .cleaning
        let stream = cleanEngine.clean(leaves)
        task = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .started(let item):
                    self.cleaningItem = item
                case .finished(let item, .success(let bytes)):
                    self.freedBytes += bytes
                    self.cleanedLeaves.append(item)
                case .finished(let item, .failure(let failure)):
                    self.failures[item.id] = failure.reason
                case .completed(let report):
                    self.cleaningItem = nil
                    self.phase = .done(report)
                }
            }
        }
    }

    // MARK: - Privado

    private func handle(_ event: ScanEvent) {
        switch event {
        case .progress(let p):
            currentGroup = p.group
            currentPath = p.currentPath
            bytesByGroup[p.group] = max(bytesByGroup[p.group] ?? 0, p.bytesFound)
            updateBytesFound()
        case .groupFinished(let result):
            finishedGroups[result.group] = result
            bytesByGroup[result.group] = result.totalSize
            updateBytesFound()
        case .finished(let report):
            self.report = report
            isPartial = false
            selection.load(report)
            bytesFound = max(bytesFound, report.totalSize)
            currentPath = ""
            currentGroup = nil
            phase = report.isEmpty ? .nothingFound : .results
        }
    }

    private func updateBytesFound() {
        bytesFound = max(bytesFound, bytesByGroup.values.reduce(0, +))
    }

    private func resetScan() {
        report = nil
        adminMeasure = .idle
        finishedGroups = [:]
        isPartial = false
        bytesFound = 0
        bytesByGroup = [:]
        currentPath = ""
        currentGroup = nil
        reviewCategory = nil
    }

    private func resetCleaning() {
        cleaningItem = nil
        freedBytes = 0
        bytesToClean = 0
        failures = [:]
        stoppedItems = []
        cleanedLeaves = []
        pendingLeaves = []
    }
}
