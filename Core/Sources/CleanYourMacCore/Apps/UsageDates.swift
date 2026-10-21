import Foundation
@preconcurrency import CoreServices

/// Datas de uso de um app (docs/re/specs/apps/inventory.md §Última abertura).
public protocol UsageDates: Sendable {
    func dates(_ app: URL) -> (lastUsed: Date?, contentModified: Date?)
}

/// `kMDItemLastUsedDate` e `kMDItemContentModificationDate` do Spotlight.
public struct SpotlightUsageDates: UsageDates {
    public init() {}

    public func dates(_ app: URL) -> (lastUsed: Date?, contentModified: Date?) {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, app as CFURL) else { return (nil, nil) }
        return (MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date,
                MDItemCopyAttribute(item, kMDItemContentModificationDate) as? Date)
    }
}

/// Apps que o Spotlight conhece nos escopos.
public protocol AppQuery: Sendable {
    func applications(in scopes: [URL]) -> [URL]
}

/// `kMDItemContentType == "com.apple.application-bundle"`, síncrono.
public struct SpotlightAppQuery: AppQuery {
    public init() {}

    public func applications(in scopes: [URL]) -> [URL] {
        let predicate = "kMDItemContentType == \"com.apple.application-bundle\"" as CFString
        guard let query = MDQueryCreate(kCFAllocatorDefault, predicate, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, scopes.map(\.path) as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var out: [URL] = []
        for i in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String { out.append(URL(fileURLWithPath: path)) }
        }
        return out
    }
}
