import Foundation
import UniformTypeIdentifiers

/// Um arquivo (ou pacote, como um item só) achado pela varredura do Acúmulos.
public struct ClutterFile: Hashable, Sendable {
    public let url: URL
    /// Tamanho lógico (o que a tela do CleanMyMac mostra); pacotes somam o conteúdo.
    public let size: Int64
    public let modified: Date?
    public let created: Date?
    /// Último acesso do sistema de arquivos (`contentAccessDate`), a "última abertura" do Fundo do Baú.
    public let accessed: Date?
    /// Identificador de tipo (UTI).
    public let contentType: String?
    public let isPackage: Bool

    public init(url: URL, size: Int64, modified: Date? = nil, created: Date? = nil, accessed: Date? = nil,
                contentType: String? = nil, isPackage: Bool = false) {
        self.url = url
        self.size = size
        self.modified = modified
        self.created = created
        self.accessed = accessed
        self.contentType = contentType
        self.isPackage = isPackage
    }

    public var type: UTType? { contentType.flatMap(UTType.init) }
}

/// Regras comuns a Duplicatas, Fundo do Baú e Imagens similares (docs/re/specs/clutter/duplicates.md §1).
public struct ClutterRules: Sendable {
    /// Os 13 padrões de nome (comparados no início do nome, sem diferenciar maiúsculas).
    static let namePatterns = [#"\.git"#, #"\.svn"#, #"\.Trash"#, #"\.DS_Store"#, "credits.?", "infoplist.?", "web-inf.?",
                               #"backups\.backupdb"#, "licence.?", "license.?", "node_modules", "gems", "bower_components"]
    /// As 79 extensões de código, build e sistema, mais os pacotes do Fotos e do Música.
    static let extensions: Set<String> = [
        "framework", "build", "lproj", "a", "so", "h", "pch", "c", "hpp", "h++", "cpp", "c++", "m", "swift", "java", "class",
        "idea", "py", "rb", "php", "css", "js", "json", "jar", "lib", "dylib", "dll", "ocx", "pth", "db", "rpl", "hds", "info",
        "def", "properties", "proofingtool", "bup", "ar", "tmp", "hg", "vsd", "xsd", "xslt", "xsl", "entitlements", "xcconfig",
        "sparsebundle", "dsym", "cer", "crt", "applescript", "version", "asset", "prefab", "unity", "html", "scss", "sh", "bash",
        "scala", "sc", "cs", "cake", "coffee", "cshtml", "csx", "ts", "vim", "vue", "plist", "yml", "yaml", "gradle", "md", "ruby",
        "gemfile", "gem", "sql", "photoslibrary", "musiclibrary",
    ]
    private static let nameRegex = try! NSRegularExpression(pattern: "^(?:" + namePatterns.joined(separator: "|") + ")",
                                                            options: [.caseInsensitive])

    private let prefixes: [String]

    public init(home: URL) {
        let h = PathPolicy.lexicalPath(home.path)
        prefixes = ["/System/", "/Library/", h + "/Library/", h + "/Music/Music/", h + "/Music/iTunes/"]
    }

    /// O item (arquivo ou pasta) fica fora da análise.
    public func isIgnored(path: String, name: String, isHidden: Bool) -> Bool {
        if isHidden || name.hasPrefix(".") { return true }
        if Self.extensions.contains((name as NSString).pathExtension.lowercased()) { return true }
        if prefixes.contains(where: { (path + "/").hasPrefix($0) }) { return true }
        return Self.nameRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }
}

/// Percorre uma pasta com as regras comuns: arquivos regulares e pacotes (um item só), sem links e sem itens só no iCloud.
public struct ClutterWalker: Sendable {
    private let rules: ClutterRules

    public init(home: URL) { rules = ClutterRules(home: home) }

    static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey, .isRegularFileKey,
                                          .fileSizeKey, .contentModificationDateKey, .creationDateKey, .contentAccessDateKey,
                                          .contentTypeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]

    public func files(in root: URL, isCancelled: @Sendable () -> Bool = { Task.isCancelled }) throws -> [ClutterFile] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Self.keys, options: [],
                                                     errorHandler: { _, _ in true }) else { return [] }
        var out: [ClutterFile] = []
        var n = 0
        while let url = e.nextObject() as? URL {
            n += 1
            if n & 0x3FF == 0, isCancelled() { throw CancellationError() }
            guard let v = try? url.resourceValues(forKeys: Set(Self.keys)) else { continue }
            if rules.isIgnored(path: url.path, name: url.lastPathComponent, isHidden: v.isHidden ?? false) {
                if v.isDirectory == true { e.skipDescendants() }
                continue
            }
            if v.isSymbolicLink == true { continue }
            // Só na nuvem: não ocupa espaço aqui e ler o conteúdo baixaria o arquivo.
            if v.isUbiquitousItem == true, v.ubiquitousItemDownloadingStatus != .current { continue }
            if v.isDirectory == true {
                guard v.isPackage == true else { continue }
                e.skipDescendants()
                out.append(ClutterFile(url: url, size: Self.packageSize(url), modified: v.contentModificationDate, created: v.creationDate,
                                       accessed: v.contentAccessDate, contentType: v.contentType?.identifier, isPackage: true))
                continue
            }
            guard v.isRegularFile == true else { continue }
            out.append(ClutterFile(url: url, size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate, created: v.creationDate,
                                   accessed: v.contentAccessDate, contentType: v.contentType?.identifier))
        }
        if isCancelled() { throw CancellationError() }
        return out
    }

    /// Soma lógica do conteúdo de um pacote (sem seguir links).
    static func packageSize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        while let u = e.nextObject() as? URL {
            if let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true { total += Int64(v.fileSize ?? 0) }
        }
        return total
    }
}
