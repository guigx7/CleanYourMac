import AppKit
import Observation
import CleanYourMacCore

protocol ClutterScanning: Sendable {
    func run(_ target: ClutterTarget) -> AsyncThrowingStream<ClutterScanEvent, Error>
}

extension ClutterScan: ClutterScanning {}

protocol ClutterRemoving: Sendable {
    func remove(_ files: [ClutterFile]) async -> [String: Result<Void, CleanFailure>]
}

extension ClutterRemover: ClutterRemoving {}

/// Fotos da fototeca: só pelo PhotoKit (vão para Apagados Recentemente, com a confirmação do sistema).
protocol PhotoRemoving: Sendable {
    func remove(_ ids: [String]) async -> Result<Void, CleanFailure>
}

/// Máquina de estados do Acúmulos: Intro → Análise → Resultados ⇄ Gerenciador → Remoção → Concluído.
@MainActor @Observable
final class ClutterFlowModel {
    enum Phase: Equatable {
        case intro, scanning, results, nothingFound, removing
        case done(Outcome)
    }

    enum Section: String, CaseIterable, Hashable { case largeOld, duplicates, similar, downloads }

    struct Outcome: Equatable {
        var removed: Int
        var freed: Int64
        /// nome → motivo
        var failed: [String: String]
    }

    private(set) var phase: Phase = .intro
    private(set) var report: ClutterReport?
    private(set) var scanStep: String?
    var target: ClutterTarget = .home
    var managerOpen = false
    var section: Section = .largeOld
    private(set) var selection: Set<String> = []
    /// Grupos em que o usuário confirmou marcar todas as cópias.
    private(set) var confirmedFull: Set<String> = []
    /// Grupo à espera do alerta de "Selecionar Tudo" e o que ficaria marcado.
    private(set) var pendingFull: (group: String, ids: Set<String>)?
    var confirmingRemoval = false

    private let scan: any ClutterScanning
    private let remover: any ClutterRemoving
    private let photos: any PhotoRemoving
    private let now: () -> Date
    let dryRun: Bool
    private var task: Task<Void, Never>?

    init(scan: any ClutterScanning, remover: any ClutterRemoving, photos: any PhotoRemoving, dryRun: Bool = false,
         now: @escaping () -> Date = { Date() }) {
        self.scan = scan
        self.remover = remover
        self.photos = photos
        self.dryRun = dryRun
        self.now = now
    }

    // MARK: - Análise

    func start() {
        task?.cancel()
        phase = .scanning
        report = nil
        scanStep = nil
        resetSelection()
        let stream = scan.run(target)
        task = Task {
            do {
                for try await event in stream {
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
        resetSelection()
        phase = .intro
    }

    func restart() {
        managerOpen = false
        start()
    }

    func choose(folder: URL?) { target = folder.map(ClutterTarget.folder) ?? .home }

    private func resetSelection() {
        selection = []
        confirmedFull = []
        pendingFull = nil
    }

    // MARK: - Gerenciador

    /// "Revisar Todos os Arquivos": seleção vazia. Cartão "Revisar": abre a categoria com a marcação automática dela.
    func openManager(_ section: Section, autoselect: Bool = false) {
        self.section = section
        if autoselect { selection.formUnion(autoselected(section)) }
        managerOpen = true
    }

    func closeManager() { managerOpen = false }

    /// Marcação automática da categoria: todas as cópias menos a que fica; todas as similares menos a melhor; downloads
    /// com mais de 30 dias. O Fundo do Baú não tem.
    func autoselected(_ section: Section) -> Set<String> {
        guard let report else { return [] }
        switch section {
        case .largeOld: return []
        case .duplicates: return Set(report.duplicates.flatMap(\.autoselected).map(\.url.path))
        case .similar: return Set(report.similar.flatMap(\.autoselected).map(\.id))
        case .downloads: return Set(report.downloads.flatMap(\.autoselected).map(\.url.path))
        }
    }

    func isSelected(_ id: String) -> Bool { selection.contains(id) }

    /// Marca ou desmarca um item. Num grupo de cópias, marcar a última que faltava pede o alerta de "Selecionar Tudo".
    func toggle(_ id: String, group: (id: String, items: [String])? = nil) {
        if selection.contains(id) {
            selection.remove(id)
            if let group { confirmedFull.remove(group.id) }
            return
        }
        if let group, !confirmedFull.contains(group.id), Set(group.items).subtracting(selection) == [id] {
            pendingFull = (group.id, Set(group.items))
            return
        }
        selection.insert(id)
    }

    /// Menu "Selecionar:" de um grupo de cópias.
    func pick(_ pick: ClutterPick, group id: String, items: [ClutterPick.Item]) {
        setGroup(items.map(\.id), chosen: pick.select(items), group: id)
    }

    /// Troca a marcação de um grupo de cópias pelos `chosen` (todos = alerta de "Selecionar Tudo").
    func setGroup(_ all: [String], chosen: Set<String>, group id: String) {
        if chosen == Set(all), !confirmedFull.contains(id) {
            pendingFull = (id, chosen)
            return
        }
        selection.subtract(all)
        selection.formUnion(chosen)
        if chosen != Set(all) { confirmedFull.remove(id) }
    }

    /// Itens soltos (Fundo do Baú, Downloads): marca ou desmarca todos de uma vez.
    func setAll(_ ids: [String], selected: Bool) {
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func confirmSelectAll() {
        guard let p = pendingFull else { return }
        confirmedFull.insert(p.group)
        selection.formUnion(p.ids)
        pendingFull = nil
    }

    func cancelSelectAll() { pendingFull = nil }

    func clearSelection() {
        selection = []
        confirmedFull = []
    }

    /// Arquivos marcados (sem repetir caminhos) e fotos da fototeca marcadas.
    var selectedFiles: [ClutterFile] {
        guard let report else { return [] }
        var seen = Set<String>(), out: [ClutterFile] = []
        func add(_ f: ClutterFile) { if selection.contains(f.url.path), seen.insert(f.url.path).inserted { out.append(f) } }
        report.largeOld.forEach(add)
        report.duplicates.flatMap(\.files).forEach(add)
        report.downloads.flatMap(\.files).map(\.file).forEach(add)
        for image in report.similar.flatMap(\.images) {
            guard let url = image.url, selection.contains(image.id), seen.insert(url.path).inserted else { continue }
            out.append(ClutterFile(url: url, size: image.size, modified: nil))
        }
        return out
    }

    var selectedPhotoIDs: [String] {
        (report?.similar.flatMap(\.images) ?? []).filter { $0.url == nil && selection.contains($0.id) }.map(\.id)
    }

    var selectedCount: Int { selectedFiles.count + selectedPhotoIDs.count }

    var selectedSize: Int64 {
        let photos = (report?.similar.flatMap(\.images) ?? []).filter { $0.url == nil && selection.contains($0.id) }
        return selectedFiles.reduce(0) { $0 + $1.size } + photos.reduce(0) { $0 + $1.size }
    }

    /// Remover só com algo marcado e sem grupo inteiro marcado sem a confirmação.
    var canRemove: Bool {
        guard selectedCount > 0, let report else { return false }
        return Set(report.fullySelectedGroups(in: selection)).isSubset(of: confirmedFull)
    }

    // MARK: - Remoção

    func requestRemoval() {
        guard canRemove else { return }
        confirmingRemoval = true
    }

    func confirmRemoval() {
        confirmingRemoval = false
        guard canRemove, let report else { return }
        let files = selectedFiles, photoIDs = selectedPhotoIDs
        let photoSizes = Dictionary(report.similar.flatMap(\.images).map { ($0.id, $0.size) }, uniquingKeysWith: { a, _ in a })
        managerOpen = false
        phase = .removing
        task = Task {
            var removed = Set<String>(), failed: [String: String] = [:], freed: Int64 = 0
            let results = await remover.remove(files)
            for f in files {
                switch results[f.url.path] ?? .failure(.cancelled) {
                case .success: removed.insert(f.url.path); freed += f.size
                case .failure(let e): failed[f.url.lastPathComponent] = e.reason
                }
            }
            if !photoIDs.isEmpty {
                switch dryRun ? .success(()) : await photos.remove(photoIDs) {
                case .success:
                    removed.formUnion(photoIDs)
                    freed += photoIDs.reduce(0) { $0 + (photoSizes[$1] ?? 0) }
                case .failure(let e):
                    for id in photoIDs { failed[id] = e.reason }
                }
            }
            // Fora da lista o que saiu (na simulação também, para o fluxo seguir igual).
            self.report = report.removing(removed, now: now())
            selection.subtract(removed)
            confirmedFull = []
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

/// Monta o fluxo de produção. Debug: `CYM_DRY_RUN=0` desliga a simulação; `CYM_PHOTOS=1` inclui a fototeca.
@MainActor
enum ClutterEnvironment {
    static func makeModel() -> ClutterFlowModel {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let dryRun = env["CYM_DRY_RUN"] != "0"
        let usePhotos = env["CYM_PHOTOS"] == "1"
        #else
        let dryRun = false
        let usePhotos = true
        #endif
        let photos = PhotoLibrarySource()
        let candidates: (@Sendable () -> [SimilarCandidate])? = usePhotos ? { @Sendable in photos.candidates() } : nil
        return ClutterFlowModel(scan: ClutterScan(photoCandidates: candidates),
                                remover: ClutterRemover(dryRun: dryRun, log: .standard), photos: photos, dryRun: dryRun)
    }
}
