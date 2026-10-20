import Foundation

/// Onde a análise acontece. Em produção `root` é "/"; nos testes, um diretório temporário.
public struct ScanContext: Sendable {
    public var root: URL
    public var home: URL
    public var userName: String
    public var preferredLanguages: [String]
    public var now: Date

    public init(root: URL, home: URL, userName: String, preferredLanguages: [String], now: Date) {
        self.root = root
        self.home = home
        self.userName = userName
        self.preferredLanguages = preferredLanguages
        self.now = now
    }

    /// Contexto do usuário atual no disco real.
    public static func current() -> ScanContext {
        ScanContext(root: URL(fileURLWithPath: "/"),
                    home: FileManager.default.homeDirectoryForCurrentUser,
                    userName: NSUserName(),
                    preferredLanguages: Locale.preferredLanguages,
                    now: Date())
    }

    /// Expande "~" (home) e "$ROOT"; caminhos absolutos ficam relativos a `root`.
    public func resolve(_ template: String) -> URL {
        if template == "~" { return home }
        if template.hasPrefix("~/") { return home.appendingPathComponent(String(template.dropFirst(2))) }
        var rest = template
        if rest.hasPrefix("$ROOT") { rest.removeFirst(5) }
        while rest.hasPrefix("/") { rest.removeFirst() }
        return rest.isEmpty ? root : root.appendingPathComponent(rest)
    }
}
