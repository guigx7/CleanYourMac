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

    /// Resultado por caminho.
    public func remove(_ files: [ClutterFile]) async -> [String: Result<Void, CleanFailure>] {
        var out: [String: Result<Void, CleanFailure>] = [:]
        var removed: [String] = [], failed: [String: String] = [:], freed: Int64 = 0
        for file in files {
            let path = file.url.path
            let result: Result<Void, CleanFailure>
            if protection.level(path: path) != .none || path.hasPrefix(library) {
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

    /// O caminho ainda é o que a análise viu: sem link no lugar dele nem nas pastas do caminho; arquivo com o mesmo tamanho,
    /// pacote ainda pasta.
    static func unchanged(_ file: ClutterFile) -> Bool {
        let path = file.url.path
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        guard PathPolicy.realPath(parent) == parent else { return false }
        let type = st.st_mode & S_IFMT
        if file.isPackage { return type == S_IFDIR }
        return type == S_IFREG && Int64(st.st_size) == file.size
    }
}
