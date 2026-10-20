import Foundation

/// Lista de exclusões por caminho (`rules/exclusions.json`).
public struct Exclusions: Sendable {
    private let patterns: [String: [String]]

    public static let bundled: Exclusions = {
        guard let url = Bundle.module.url(forResource: "exclusions", withExtension: "json", subdirectory: "rules"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Exclusions(patterns: [:]) }
        var map: [String: [String]] = [:]
        for (k, v) in raw { if let list = v as? [String] { map[k] = list } }
        return Exclusions(patterns: map)
    }()

    public init(patterns: [String: [String]]) {
        self.patterns = patterns
    }

    /// O caminho casa com a lista global ou com a do grupo.
    /// Compara caminhos reais (o pai é resolvido; ex.: /var → /private/var). Globs só no último componente.
    public func excludes(_ url: URL, group: GroupID, context: ScanContext) -> Bool {
        let path = Self.real(url)
        let lists = (patterns["global"] ?? []) + (patterns[group.rawValue] ?? [])
        return lists.contains { fnmatch(Self.real(context.resolve($0)), path, 0) == 0 }
    }

    private static func real(_ url: URL) -> String {
        (PathPolicy.realPath(url.deletingLastPathComponent().path) as NSString).appendingPathComponent(url.lastPathComponent)
    }
}
