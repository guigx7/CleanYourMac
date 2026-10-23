import AppKit
import Observation
import CleanYourMacCore

protocol ClutterScanning: Sendable {
    func run(_ target: ClutterTarget) -> AsyncThrowingStream<ClutterScanEvent, Error>
}

extension ClutterScan: ClutterScanning {}

protocol ClutterRemoving: Sendable {
    /// `keeping`: grupos de cópias; se a que fica sumiu ou mudou, as do grupo não saem.
    func remove(_ files: [ClutterFile], keeping groups: [[ClutterFile]]) async -> [String: Result<Void, CleanFailure>]
}

extension ClutterRemover: ClutterRemoving {}

/// Fotos da fototeca: só pelo PhotoKit (vão para Apagados Recentemente, com a confirmação do sistema).
protocol PhotoRemoving: Sendable {
    /// Resultado por id de foto.
    func remove(_ ids: [String]) async -> [String: Result<Void, CleanFailure>]
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
        /// caminho (ou id de foto) → motivo
        var failed: [String: String]
    }

    private(set) var phase: Phase = .intro
    private(set) var report: ClutterReport? { didSet { index() } }
    private(set) var scanStep: String?
    var target: ClutterTarget = .home
    var managerOpen = false
    var section: Section = .largeOld
    private(set) var selection: Set<String> = []
    /// Grupos em que o usuário confirmou marcar todas as cópias.
    private(set) var confirmedFull: Set<String> = []
    /// À espera do alerta de "Selecionar Tudo": os grupos que ficariam inteiros e a seleção que valeria.
    private(set) var pendingFull: (groups: Set<String>, selection: Set<String>)?
    /// Arquivo de cada id marcável (na ordem das seções) e tamanho das fotos: o rodapé não percorre o relatório a cada desenho.
    @ObservationIgnored private var fileByID: [String: (order: Int, file: ClutterFile)] = [:]
    @ObservationIgnored private var photoSize: [String: Int64] = [:]
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

    private func index() {
        fileByID = [:]
        photoSize = [:]
        guard let report else { return }
        var n = 0
        func add(_ f: ClutterFile) {
            guard fileByID[f.url.path] == nil else { return }
            fileByID[f.url.path] = (n, f)
            n += 1
        }
        report.largeOld.forEach(add)
        report.duplicates.flatMap(\.files).forEach(add)
        report.downloads.flatMap(\.files).map(\.file).forEach(add)
        for image in report.similar.flatMap(\.images) {
            if let url = image.url {
                add(ClutterFile(url: url, size: image.size, modified: image.modified))
            } else {
                photoSize[image.id] = image.size
            }
        }
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

    /// Marca ou desmarca um item. Se a marcação deixar um grupo de cópias ou de similares inteiro (por esta ou por outra
    /// seção), pede antes o alerta de "Selecionar Tudo".
    func toggle(_ id: String) {
        if selection.contains(id) { apply(selection.subtracting([id])) } else { apply(selection.union([id])) }
    }

    /// Menu "Selecionar:" de um grupo.
    func pick(_ pick: ClutterPick, group id: String, items: [ClutterPick.Item]) {
        setGroup(items.map(\.id), chosen: pick.select(items), group: id)
    }

    /// Troca a marcação de um grupo pelos `chosen`.
    func setGroup(_ all: [String], chosen: Set<String>, group id: String) {
        apply(selection.subtracting(all).union(chosen))
    }

    /// Itens soltos (Fundo do Baú, Downloads): marca ou desmarca todos de uma vez.
    func setAll(_ ids: [String], selected: Bool) {
        apply(selected ? selection.union(ids) : selection.subtracting(ids))
    }

    private func fullGroups(_ s: Set<String>) -> Set<String> { Set(report?.fullySelectedGroups(in: s) ?? []) }

    /// Troca a seleção; grupo que ficaria inteiro sem ter sido confirmado espera o alerta.
    private func apply(_ next: Set<String>) {
        let newlyFull = fullGroups(next).subtracting(fullGroups(selection)).subtracting(confirmedFull)
        if !newlyFull.isEmpty {
            pendingFull = (newlyFull, next)
            return
        }
        selection = next
        // Grupo que deixou de estar inteiro perde a confirmação.
        confirmedFull.formIntersection(fullGroups(next))
    }

    func confirmSelectAll() {
        guard let p = pendingFull else { return }
        confirmedFull.formUnion(p.groups)
        selection = p.selection
        confirmedFull.formIntersection(fullGroups(selection))
        pendingFull = nil
    }

    func cancelSelectAll() { pendingFull = nil }

    func clearSelection() {
        selection = []
        confirmedFull = []
    }

    /// Arquivos marcados (sem repetir caminhos, na ordem das seções) e fotos da fototeca marcadas.
    var selectedFiles: [ClutterFile] {
        selection.compactMap { fileByID[$0] }.sorted { $0.order < $1.order }.map(\.file)
    }

    var selectedPhotoIDs: [String] { selection.filter { photoSize[$0] != nil }.sorted() }

    var selectedCount: Int { selection.filter { fileByID[$0] != nil || photoSize[$0] != nil }.count }

    var selectedSize: Int64 {
        selection.reduce(0) { $0 + (fileByID[$1]?.file.size ?? photoSize[$1] ?? 0) }
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
        let files = selectedFiles, photoIDs = selectedPhotoIDs, photoSizes = photoSize
        // Grupos de cópias com algo saindo e não confirmados por inteiro: a cópia que fica precisa continuar lá.
        let leaving = Set(files.map(\.url.path))
        let keeping = report.duplicates.filter { g in !confirmedFull.contains(g.id) && g.files.contains { leaving.contains($0.url.path) } }
            .map(\.files)
        managerOpen = false
        phase = .removing
        task = Task {
            var removed = Set<String>(), failed: [String: String] = [:], freed: Int64 = 0
            let results = await remover.remove(files, keeping: keeping)
            for f in files {
                switch results[f.url.path] ?? .failure(.cancelled) {
                case .success: removed.insert(f.url.path); freed += f.size
                case .failure(let e): failed[f.url.path] = e.reason
                }
            }
            if !photoIDs.isEmpty {
                let photoResults = dryRun ? Dictionary(uniqueKeysWithValues: photoIDs.map { ($0, Result<Void, CleanFailure>.success(())) })
                    : await photos.remove(photoIDs)
                for id in photoIDs {
                    switch photoResults[id] ?? .failure(.cancelled) {
                    case .success: removed.insert(id); freed += photoSizes[id] ?? 0
                    case .failure(let e): failed[id] = e.reason
                    }
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
