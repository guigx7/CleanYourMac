import Foundation

/// Onde a análise acontece. Em produção `root` é "/"; nos testes, um diretório temporário.
public struct ScanContext: Sendable {
    public var root: URL
    public var home: URL
    public var userName: String
    public var preferredLanguages: [String]
    public var now: Date
    /// `confstr(_CS_DARWIN_USER_CACHE_DIR)` (ex.: /var/folders/xx/…/C). Nos testes, dentro do fixture.
    public var darwinUserCacheDir: URL
    /// uid do usuário analisado (pastas em /private/tmp precisam ser dele).
    public var uid: uid_t = getuid()

    public init(root: URL, home: URL, userName: String, preferredLanguages: [String], now: Date,
                darwinUserCacheDir: URL? = nil) {
        self.root = root
        self.home = home
        self.userName = userName
        self.preferredLanguages = preferredLanguages
        self.now = now
        self.darwinUserCacheDir = darwinUserCacheDir ?? Self.systemDarwinUserCacheDir()
    }

    static func systemDarwinUserCacheDir() -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let n = confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count)
        guard n > 0 else { return FileManager.default.temporaryDirectory }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self), isDirectory: true)
    }

    /// Contexto do usuário atual no disco real.
    public static func current() -> ScanContext {
        ScanContext(root: URL(fileURLWithPath: "/"),
                    home: FileManager.default.homeDirectoryForCurrentUser,
                    userName: NSUserName(),
                    preferredLanguages: Locale.preferredLanguages,
                    now: Date())
    }

    /// Expande "~" (home), "$DARWIN" (cache do Darwin) e "$ROOT"; caminhos absolutos ficam relativos a `root`.
    public func resolve(_ template: String) -> URL {
        if template == "$DARWIN" { return darwinUserCacheDir }
        if template.hasPrefix("$DARWIN/") { return darwinUserCacheDir.appendingPathComponent(String(template.dropFirst(8))) }
        if template == "~" { return home }
        if template.hasPrefix("~/") { return home.appendingPathComponent(String(template.dropFirst(2))) }
        var rest = template
        if rest.hasPrefix("$ROOT") { rest.removeFirst(5) }
        while rest.hasPrefix("/") { rest.removeFirst() }
        return rest.isEmpty ? root : root.appendingPathComponent(rest)
    }
}
