import Foundation

public enum ItemBadge: String, Hashable, Sendable {
    case latest
    /// Imagem de disco montada: aparece, mas não pode ser marcada (apps/installers.md §Remoção).
    case mounted
}

public enum IconSource: Hashable, Sendable {
    case file(URL)
    case app(URL)
    case symbol(String)
}

/// Um item encontrado pela análise. Pode ser uma folha removível ou um agrupador de filhos.
public struct JunkItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let group: GroupID
    public let name: String
    public let detail: String?
    public let url: URL?
    /// Bytes alocados do próprio item (sem os filhos).
    public let size: Int64
    public let isRecommended: Bool
    public let badge: ItemBadge?
    public let icon: IconSource
    /// `nil` quando o item só agrupa filhos.
    public let removal: RemovalAction?
    public let children: [JunkItem]
    /// A interface mostra os filhos ao expandir. Alguns grupos guardam filhos só para a remoção.
    public let displaysChildren: Bool
    /// Chave de localização do nome (a interface prefere ela ao `name`).
    public let titleKey: String?

    public init(id: String? = nil, group: GroupID, name: String, detail: String? = nil, url: URL?,
                size: Int64, isRecommended: Bool = false, badge: ItemBadge? = nil,
                icon: IconSource? = nil, removal: RemovalAction? = nil, children: [JunkItem] = [],
                displaysChildren: Bool = true, titleKey: String? = nil) {
        self.id = id ?? "\(group.rawValue):\(url?.path ?? name)"
        self.group = group
        self.name = name
        self.detail = detail
        self.url = url
        self.size = size
        self.isRecommended = isRecommended
        self.badge = badge
        self.icon = icon ?? url.map(IconSource.file) ?? .symbol("doc")
        self.removal = removal
        self.children = children
        self.displaysChildren = displaysChildren
        self.titleKey = titleKey
    }

    /// Tamanho do item somado ao de todos os descendentes.
    public var totalSize: Int64 {
        size + children.reduce(0) { $0 + $1.totalSize }
    }

    /// Folhas (o próprio item, se não tiver filhos).
    public var leaves: [JunkItem] {
        children.isEmpty ? [self] : children.flatMap(\.leaves)
    }
}
