import Foundation

public struct ScanProgress: Sendable {
    public let group: GroupID
    public let currentPath: String
    public let bytesFound: Int64

    public init(group: GroupID, currentPath: String, bytesFound: Int64) {
        self.group = group
        self.currentPath = currentPath
        self.bytesFound = bytesFound
    }
}

/// Encontra os itens de um grupo. Implementações não devem alterar o disco.
public protocol GroupScanner: Sendable {
    var group: GroupID { get }
    func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem]
}

/// Onde a limpeza deste grupo pode tocar. Padrão: nada (o scanner precisa declarar).
public struct RemovalScope: Sendable {
    public var roots: [URL]
    public var items: [URL]
    public init(roots: [URL] = [], items: [URL] = []) {
        self.roots = roots
        self.items = items
    }
}

public protocol ScopedScanner: GroupScanner {
    func removalScope(_ context: ScanContext) -> RemovalScope
}
