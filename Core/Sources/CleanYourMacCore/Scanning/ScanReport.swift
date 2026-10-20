import Foundation

public struct GroupResult: Sendable {
    public let group: GroupID
    public let items: [JunkItem]

    public init(group: GroupID, items: [JunkItem]) {
        self.group = group
        self.items = items
    }

    /// Soma de `totalSize` dos itens, contando cada `id` uma vez.
    public var totalSize: Int64 {
        var seen = Set<String>()
        return items.reduce(0) { seen.insert($1.id).inserted ? $0 + $1.totalSize : $0 }
    }
}

public struct ScanReport: Sendable {
    public let groups: [GroupID: GroupResult]

    public init(groups: [GroupID: GroupResult]) {
        self.groups = groups
    }

    public var totalSize: Int64 {
        groups.values.reduce(0) { $0 + $1.totalSize }
    }

    public func totalSize(of category: CategoryID) -> Int64 {
        groups.values.filter { $0.group.category == category }.reduce(0) { $0 + $1.totalSize }
    }

    /// Folhas marcadas como recomendadas, em todos os grupos.
    public func recommendedItems() -> [JunkItem] {
        groups.values.flatMap { $0.items.flatMap(\.leaves) }.filter(\.isRecommended)
    }

    public var isEmpty: Bool { totalSize == 0 }
}

public enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case groupFinished(GroupResult)
    case finished(ScanReport)
}
