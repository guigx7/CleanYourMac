import Foundation

public enum PathPolicyError: Error, Equatable, Sendable {
    case outsideAllowedRoots(String)
    case isAllowedRootItself(String)
    case symlinkEscape(String)
}

/// Garante que a limpeza só toque caminhos dentro das raízes permitidas de um grupo.
public struct PathPolicy: Sendable {
    public let allowedRoots: [URL]
    /// Caminhos exatos que podem ser removidos inteiros (e tudo dentro deles).
    public let allowedItems: [URL]
    private let realRoots: [[String]]
    private let lexicalRoots: [[String]]
    private let realItems: [[String]]

    public init(allowedRoots: [URL], allowedItems: [URL] = []) {
        self.allowedRoots = allowedRoots
        self.allowedItems = allowedItems
        realRoots = allowedRoots.map { Self.components(Self.realPath($0.path)) }
        lexicalRoots = (allowedRoots + allowedItems).map { Self.components(Self.lexicalPath($0.path)) }
        realItems = allowedItems.map { Self.components(Self.realPath($0.path)) }
    }

    /// Retorna o caminho com o diretório pai resolvido. O último componente não é
    /// resolvido: apagar um symlink apaga só o link, nunca o destino.
    public func validate(_ url: URL) throws(PathPolicyError) -> URL {
        let lexical = URL(fileURLWithPath: Self.lexicalPath(url.path))
        let parent = Self.realPath(lexical.deletingLastPathComponent().path)
        let resolved = URL(fileURLWithPath: parent).appendingPathComponent(lexical.lastPathComponent)
        let parts = Self.components(resolved.path)

        if realItems.contains(where: { $0 == parts || Self.isStrictPrefix($0, of: parts) }) { return resolved }
        if realRoots.contains(parts) { throw .isAllowedRootItself(resolved.path) }
        if realRoots.contains(where: { Self.isStrictPrefix($0, of: parts) }) { return resolved }

        let lexicalParts = Self.components(lexical.path)
        if lexicalRoots.contains(where: { Self.isStrictPrefix($0, of: lexicalParts) })
            || (realRoots + realItems).contains(where: { Self.isStrictPrefix($0, of: lexicalParts) }) {
            throw .symlinkEscape(lexical.path)
        }
        throw .outsideAllowedRoots(lexical.path)
    }

    /// Resolve "." e ".." só textualmente (sem tocar o disco nem remover "/private").
    static func lexicalPath(_ path: String) -> String {
        var out: [String] = []
        for part in components(path) {
            switch part {
            case ".": continue
            case "..": if !out.isEmpty { out.removeLast() }
            default: out.append(part)
            }
        }
        return "/" + out.joined(separator: "/")
    }

    private static func isStrictPrefix(_ root: [String], of path: [String]) -> Bool {
        path.count > root.count && Array(path.prefix(root.count)) == root
    }

    private static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// realpath(3) no maior prefixo existente; o resto é anexado sem resolver.
    static func realPath(_ path: String) -> String {
        var head = path
        var tail: [String] = []
        while !head.isEmpty, head != "/" {
            if let r = realpath(head, nil) {
                defer { free(r) }
                let base = String(cString: r)
                return tail.reversed().reduce(base) { ($0 as NSString).appendingPathComponent($1) }
            }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
        return tail.reversed().reduce("/") { ($0 as NSString).appendingPathComponent($1) }
    }
}
