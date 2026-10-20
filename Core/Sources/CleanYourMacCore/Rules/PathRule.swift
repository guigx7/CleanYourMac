import Foundation

/// Regra declarativa de um grupo: onde procurar, o que vira item e como remover.
public struct PathRule: Codable, Sendable, Equatable {
    public enum ItemLevel: String, Codable, Sendable {
        /// A própria raiz é um item.
        case root
        /// Cada filho direto da raiz é um item.
        case children
    }

    public enum RemovalKind: String, Codable, Sendable {
        case delete, moveToTrash, deleteContents
    }

    /// Templates: "~/Library/Caches", "/Library/Logs" (relativo ao root do contexto).
    public var roots: [String]
    public var itemLevel: ItemLevel
    /// Globs (fnmatch) sobre o nome do item; `nil` aceita todos.
    public var include: [String]?
    /// Globs (fnmatch) sobre o caminho relativo à raiz.
    public var exclude: [String]
    public var minAgeDays: Int?
    public var recommended: Bool
    public var removal: RemovalKind
    public var detail: String?

    public init(roots: [String], itemLevel: ItemLevel, include: [String]? = nil, exclude: [String] = [],
                minAgeDays: Int? = nil, recommended: Bool = false, removal: RemovalKind = .delete,
                detail: String? = nil) {
        self.roots = roots
        self.itemLevel = itemLevel
        self.include = include
        self.exclude = exclude
        self.minAgeDays = minAgeDays
        self.recommended = recommended
        self.removal = removal
        self.detail = detail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roots = try c.decode([String].self, forKey: .roots)
        itemLevel = try c.decode(ItemLevel.self, forKey: .itemLevel)
        include = try c.decodeIfPresent([String].self, forKey: .include)
        exclude = try c.decodeIfPresent([String].self, forKey: .exclude) ?? []
        minAgeDays = try c.decodeIfPresent(Int.self, forKey: .minAgeDays)
        recommended = try c.decodeIfPresent(Bool.self, forKey: .recommended) ?? false
        removal = try c.decodeIfPresent(RemovalKind.self, forKey: .removal) ?? .delete
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
    }
}

public struct GroupRules: Codable, Sendable, Equatable {
    public var group: GroupID
    public var rules: [PathRule]

    public init(group: GroupID, rules: [PathRule]) {
        self.group = group
        self.rules = rules
    }
}
