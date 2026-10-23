import Foundation

/// Downloads por app (docs/re/specs/clutter/downloads.md): os itens do topo de `~/Downloads`, agrupados pelo app que os
/// baixou segundo a marca de quarentena do macOS (`com.apple.quarantine`). O CleanMyMac lê o histórico de cada app;
/// a marca é pública e não precisa de Acesso Total ao Disco.
public struct DownloadsFinder: Sendable {
    public enum App: String, CaseIterable, Sendable {
        case chrome, safari, slack, firefox, edge, brave, arc, opera

        public var title: String {
            switch self {
            case .chrome: "Google Chrome"
            case .safari: "Safari"
            case .slack: "Slack"
            case .firefox: "Firefox"
            case .edge: "Microsoft Edge"
            case .brave: "Brave"
            case .arc: "Arc"
            case .opera: "Opera"
            }
        }

        /// Nome do agente na quarentena → app.
        public init?(agent: String) {
            let a = agent.lowercased()
            if a.contains("chrome") { self = .chrome }
            else if a.contains("safari") { self = .safari }
            else if a.contains("slack") { self = .slack }
            else if a.contains("firefox") { self = .firefox }
            else if a.contains("edge") { self = .edge }
            else if a.contains("brave") { self = .brave }
            else if a == "arc" || a.contains("company.thebrowser") { self = .arc }
            else if a.contains("opera") { self = .opera }
            else { return nil }
        }
    }

    public struct Item: Hashable, Sendable {
        public let file: ClutterFile
        /// Quando foi baixado (quarentena).
        public let downloaded: Date?
        public var url: URL { file.url }
        public var size: Int64 { file.size }
    }

    public struct Group: Hashable, Sendable, Identifiable {
        public let app: App
        /// Do maior para o menor.
        public let files: [Item]
        public var id: String { app.rawValue }
        public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
        /// Marcação automática: baixados há mais de 30 dias.
        public let autoselected: [Item]
    }

    private let folder: URL

    public init(home: URL) { folder = home.appendingPathComponent("Downloads") }

    public func groups(now: Date = Date()) -> [Group] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }
        var byApp: [App: [Item]] = [:]
        for name in names {
            let url = folder.appendingPathComponent(name)
            guard let q = Self.quarantine(url), let app = App(agent: q.agent) else { continue }
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
                                             .creationDateKey, .contentAccessDateKey, .contentTypeKey]
            guard let v = try? url.resourceValues(forKeys: keys), v.isSymbolicLink != true else { continue }
            let isDir = v.isDirectory == true
            let size = isDir ? ClutterWalker.packageSize(url) : Int64(v.fileSize ?? 0)
            let file = ClutterFile(url: url, size: size, modified: v.contentModificationDate, created: v.creationDate,
                                   accessed: v.contentAccessDate, contentType: v.contentType?.identifier, isPackage: isDir)
            byApp[app, default: []].append(Item(file: file, downloaded: q.date))
        }
        let monthAgo = now.addingTimeInterval(-30 * 86_400)
        return byApp.map { app, items in
            let sorted = items.sorted { $0.size != $1.size ? $0.size > $1.size : $0.url.path < $1.url.path }
            return Group(app: app, files: sorted, autoselected: sorted.filter { ($0.downloaded ?? now) < monthAgo })
        }
        .sorted { $0.totalSize != $1.totalSize ? $0.totalSize > $1.totalSize : $0.app.rawValue < $1.app.rawValue }
    }

    /// `flags;hex(segundos desde 1970);agente;uuid`.
    static func parseQuarantine(_ value: String) -> (agent: String, date: Date?)? {
        let parts = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, !parts[2].isEmpty else { return nil }
        return (parts[2], UInt64(parts[1], radix: 16).map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    static func quarantine(_ url: URL) -> (agent: String, date: Date?)? {
        let n = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        guard n > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: n)
        guard getxattr(url.path, "com.apple.quarantine", &buffer, n, 0, XATTR_NOFOLLOW) == n else { return nil }
        return parseQuarantine(String(decoding: buffer, as: UTF8.self))
    }
}
