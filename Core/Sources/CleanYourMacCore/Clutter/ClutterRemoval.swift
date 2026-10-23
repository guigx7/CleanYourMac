import Foundation

/// Menu "Selecionar:" de um grupo (docs/re/specs/clutter/results-and-manager.md §3.4): marca todos menos o que o critério
/// mantém, nenhum ou todos (este último só com o alerta de "Selecionar Tudo").
public enum ClutterPick: String, CaseIterable, Sendable {
    case none, all, keepLargest, keepSmallest, keepNewest, keepOldest

    public struct Item: Sendable {
        public let id: String
        public let size: Int64
        public let date: Date?

        public init(id: String, size: Int64, date: Date?) {
            self.id = id
            self.size = size
            self.date = date
        }

        /// Duplicatas mostram a data de criação.
        public init(_ file: ClutterFile) { self.init(id: file.url.path, size: file.size, date: file.created ?? file.modified) }
        public init(_ image: SimilarImage) { self.init(id: image.id, size: image.size, date: image.date) }
    }

    /// Os ids que ficam marcados.
    public func select(_ items: [Item]) -> Set<String> {
        let ids = Set(items.map(\.id))
        let keep: Item?
        switch self {
        case .none: return []
        case .all: return ids
        case .keepLargest: keep = items.max { $0.size != $1.size ? $0.size < $1.size : $0.id > $1.id }
        case .keepSmallest: keep = items.min { $0.size != $1.size ? $0.size < $1.size : $0.id < $1.id }
        case .keepNewest: keep = items.max { ($0.date ?? .distantPast, $1.id) < ($1.date ?? .distantPast, $0.id) }
        case .keepOldest: keep = items.min { ($0.date ?? .distantPast, $0.id) < ($1.date ?? .distantPast, $1.id) }
        }
        return keep.map { ids.subtracting([$0.id]) } ?? []
    }
}

extension ClutterReport {
    /// Grupos de Duplicatas ou Similares com todas as cópias marcadas (pedem a confirmação de "Selecionar Tudo").
    public func fullySelectedGroups(in selected: Set<String>) -> [String] {
        let dups = duplicates.filter { $0.files.allSatisfy { selected.contains($0.url.path) } }.map(\.id)
        let sims = similar.filter { $0.images.allSatisfy { selected.contains($0.id) } }.map(\.id)
        return dups + sims
    }
}

/// Manda arquivos do Acúmulos para o Lixo, revalidando cada um (ainda existe, mesmo tamanho, não virou link, não protegido).
public struct ClutterRemover: Sendable {
    private let trasher: any Trasher
    private let protection: SpaceProtection
    private let library: String
    private let dryRun: Bool
    private let log: CleanupLog

    public init(trasher: any Trasher = FileTrasher(), home: URL = FileManager.default.homeDirectoryForCurrentUser, dryRun: Bool,
                log: CleanupLog) {
        self.trasher = trasher
        protection = SpaceProtection(home: home)
        library = PathPolicy.lexicalPath(home.appendingPathComponent("Library").path) + "/"
        self.dryRun = dryRun
        self.log = log
    }

    /// Resultado por caminho. `keeping`: grupos de cópias; se nenhuma cópia que não está em `files` continua igual à da
    /// análise, as do grupo não saem (seriam a última cópia).
    public func remove(_ files: [ClutterFile], keeping groups: [[ClutterFile]] = []) async -> [String: Result<Void, CleanFailure>] {
        var out: [String: Result<Void, CleanFailure>] = [:]
        var removed: [String] = [], failed: [String: String] = [:], freed: Int64 = 0
        let leaving = Set(files.map(\.url.path))
        var orphaned = Set<String>()
        for group in groups {
            let stays = group.filter { !leaving.contains($0.url.path) }
            if !stays.isEmpty, !stays.contains(where: Self.unchanged) { orphaned.formUnion(group.map(\.url.path)) }
        }
        for file in files {
            let path = file.url.path
            let result: Result<Void, CleanFailure>
            if orphaned.contains(path) {
                result = .failure(CleanFailure(reason: "item changed"))
            } else if protection.level(path: path) != .none || path.hasPrefix(library) {
                result = .failure(CleanFailure(reason: "kept: protected"))
            } else if !Self.unchanged(file) {
                result = .failure(CleanFailure(reason: "item changed"))
            } else if dryRun {
                result = .success(())
            } else {
                do {
                    try trasher.trash(file.url)
                    result = .success(())
                } catch {
                    result = .failure(CleanFailure(reason: error.localizedDescription))
                }
            }
            out[path] = result
            switch result {
            case .success: removed.append(path); freed += file.size
            case .failure(let f): failed[path] = f.reason
            }
        }
        try? log.write(clutter: CleanReport(freedBytes: freed, removed: removed, failed: failed, dryRun: dryRun))
        return out
    }

    /// O caminho ainda é o que a análise viu: sem link no lugar dele nem nas pastas do caminho; mesma data de modificação;
    /// arquivo com o mesmo tamanho, pacote ainda pasta com o mesmo conteúdo somado.
    static func unchanged(_ file: ClutterFile) -> Bool {
        let path = file.url.path
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        guard PathPolicy.realPath(parent) == parent else { return false }
        if let modified = file.modified {
            let now = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
            guard abs(now - modified.timeIntervalSince1970) < 0.001 else { return false }
        }
        let type = st.st_mode & S_IFMT
        if file.isPackage { return type == S_IFDIR && ClutterWalker.packageSize(file.url) == file.size }
        return type == S_IFREG && Int64(st.st_size) == file.size
    }
}

extension ClutterReport {
    /// O relatório sem os itens removidos (ids = caminhos ou ids de foto): grupos com menos de 2 itens saem, Downloads sem
    /// arquivos sai, cartões recalculados.
    public func removing(_ ids: Set<String>, now: Date = Date()) -> ClutterReport {
        let largeOld = largeOld.filter { !ids.contains($0.url.path) }
        let duplicates = duplicates.compactMap { g -> DuplicateGroup? in
            let files = g.files.filter { !ids.contains($0.url.path) }
            return files.count > 1 ? DuplicateGroup(files: files, hash: g.hash) : nil
        }
        let similar = similar.compactMap { g -> SimilarGroup? in
            let images = g.images.filter { !ids.contains($0.id) }
            return images.count > 1 ? g.keeping(images) : nil
        }
        let downloads = downloads.compactMap { g -> DownloadsFinder.Group? in
            let files = g.files.filter { !ids.contains($0.url.path) }
            return files.isEmpty ? nil : DownloadsFinder.Group(app: g.app, files: files, autoselected: g.autoselected.filter { files.contains($0) })
        }
        let tiles = ClutterTiles.make(home: home, now: now, largeOld: largeOld, duplicates: duplicates, similar: similar, downloads: downloads)
        return ClutterReport(home: home, largeOld: largeOld, duplicates: duplicates, similar: similar, downloads: downloads, tiles: tiles,
                             isPartial: isPartial)
    }
}
