import Foundation

/// O que pode ser marcado na Lupa de Espaço (docs/re/specs/spacelens/scan.md §7).
public struct SpaceProtection: Sendable {
    public enum Level: Sendable {
        case none
        /// Pasta-padrão do sistema ou do usuário: sem caixa no nível dela; o conteúdo pode ser marcado.
        case systemFolder
        /// Essencial: nunca removível (SIP/`SF_RESTRICTED`, vitais, raiz do volume e o que fica nela).
        case essential
    }

    private let home: String
    private let systemFolders: Set<String>

    /// Pastas-padrão relativas à pasta pessoal.
    static let homeStandard = ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "Applications",
                               "Library/Application Support", "Library/Caches", "Library/Containers", "Library/Group Containers",
                               "Library/Logs", "Library/Mail", "Library/Mobile Documents", "Library/Preferences"]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let h = PathPolicy.lexicalPath(home.path)
        self.home = h
        systemFolders = Set(Self.homeStandard.map { h + "/" + $0 } + ["/Users/Shared", "/Library/Application Support"])
    }

    public func level(path raw: String) -> Level {
        let path = PathPolicy.lexicalPath(raw)
        let parts = path.split(separator: "/")
        if path == "/" || parts.count == 1 || path == home || path.hasPrefix("/System/Volumes") || Self.isRestricted(path) {
            return .essential
        }
        // Ancestrais da pasta pessoal (ex.: /Users) também ficam.
        if home.hasPrefix(path + "/") { return .essential }
        if systemFolders.contains(path) { return .systemFolder }
        if PathPolicy.isVital(path) || Self.isCloudOnly(path) { return .essential }
        return .none
    }

    /// Item do iCloud que só existe na nuvem (não baixado): não há o que mandar para o Lixo aqui.
    public static func isCloudOnly(_ path: String) -> Bool {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys), v.isUbiquitousItem == true else { return false }
        return v.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    public func level(_ node: SpaceNode) -> Level { level(path: node.path) }

    /// `SF_RESTRICTED`: protegido pela Proteção da Integridade do Sistema.
    public static func isRestricted(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && st.st_flags & UInt32(SF_RESTRICTED) != 0
    }
}

/// Remove para o Lixo, revalidando cada item (ainda existe, mesmo tipo, não virou link, não protegido).
public struct SpaceRemover: Sendable {
    private let trasher: any Trasher
    private let protection: SpaceProtection
    private let dryRun: Bool
    private let log: CleanupLog

    public init(trasher: any Trasher = FileTrasher(), protection: SpaceProtection = SpaceProtection(), dryRun: Bool, log: CleanupLog) {
        self.trasher = trasher
        self.protection = protection
        self.dryRun = dryRun
        self.log = log
    }

    /// Resultado por caminho.
    public func remove(_ nodes: [SpaceNode]) async -> [String: Result<Void, CleanFailure>] {
        var out: [String: Result<Void, CleanFailure>] = [:]
        var removed: [String] = [], failed: [String: String] = [:], freed: Int64 = 0
        for node in nodes {
            let path = node.path
            let result: Result<Void, CleanFailure>
            if protection.level(path: path) != .none {
                result = .failure(CleanFailure(reason: "kept: protected"))
            } else if !Self.unchanged(node, path) {
                result = .failure(CleanFailure(reason: "item changed"))
            } else if dryRun {
                result = .success(())
            } else {
                do {
                    try trasher.trash(URL(fileURLWithPath: path))
                    result = .success(())
                } catch {
                    result = .failure(CleanFailure(reason: error.localizedDescription))
                }
            }
            out[path] = result
            switch result {
            case .success: removed.append(path); freed += node.size
            case .failure(let f): failed[path] = f.reason
            }
        }
        try? log.write(CleanReport(freedBytes: freed, removed: removed, failed: failed, dryRun: dryRun))
        return out
    }

    /// O caminho ainda é o que a análise viu: existe, mesmo tipo e não é um link no lugar de uma pasta ou arquivo.
    static func unchanged(_ node: SpaceNode, _ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        let type = st.st_mode & S_IFMT
        if node.isDirectory { return type == S_IFDIR }
        return type != S_IFDIR && type != S_IFLNK
    }
}
