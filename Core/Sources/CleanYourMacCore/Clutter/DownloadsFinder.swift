import Foundation
import SQLite3

/// Downloads por app (docs/re/specs/clutter/downloads.md), como o CleanMyMac: o histórico de downloads de cada app, só os
/// concluídos cujo arquivo ainda existe. Chrome: banco `History` de cada perfil (lido de uma cópia); Safari:
/// `~/Library/Safari/Downloads.plist` (exige Acesso Total ao Disco). Slack: ainda sem leitor (formato não confirmado).
public struct DownloadsFinder: Sendable {
    public enum App: String, CaseIterable, Sendable {
        case chrome, safari, slack

        public var title: String {
            switch self {
            case .chrome: "Google Chrome"
            case .safari: "Safari"
            case .slack: "Slack"
            }
        }
    }

    public struct Item: Hashable, Sendable {
        public let file: ClutterFile
        /// Quando foi baixado.
        public let downloaded: Date?
        public var url: URL { file.url }

        public init(file: ClutterFile, downloaded: Date?) {
            self.file = file
            self.downloaded = downloaded
        }
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

        public init(app: App, files: [Item], autoselected: [Item]) {
            self.app = app
            self.files = files
            self.autoselected = autoselected
        }
    }

    private let home: URL

    public init(home: URL) { self.home = home }

    public func groups(now: Date = Date()) -> [Group] {
        // Slack: o formato do histórico dele não foi confirmado; sem leitor, o grupo não aparece.
        let sources: [(App, [(String, Date?)])] = [(.chrome, chrome()), (.safari, safari())]
        let monthAgo = now.addingTimeInterval(-30 * 86_400)
        return sources.compactMap { app, entries -> Group? in
            var seen = Set<String>()
            let items = entries.compactMap { path, date -> Item? in
                guard seen.insert(path).inserted, let file = Self.file(path) else { return nil }
                return Item(file: file, downloaded: date)
            }
            guard !items.isEmpty else { return nil }
            let sorted = items.sorted { $0.size != $1.size ? $0.size > $1.size : $0.url.path < $1.url.path }
            return Group(app: app, files: sorted, autoselected: sorted.filter { ($0.downloaded ?? now) < monthAgo })
        }
        .sorted { $0.totalSize != $1.totalSize ? $0.totalSize > $1.totalSize : $0.app.rawValue < $1.app.rawValue }
    }

    /// Arquivo comum que ainda existe (pastas e links ficam de fora).
    static func file(_ path: String) -> ClutterFile? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
                                         .contentAccessDateKey, .contentTypeKey]
        guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { return nil }
        return ClutterFile(url: url, size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate, created: v.creationDate,
                           accessed: v.contentAccessDate, contentType: v.contentType?.identifier)
    }

    // MARK: - Chrome

    /// Microssegundos desde 1601-01-01.
    static func chromeDate(_ value: Int64) -> Date? {
        value > 0 ? Date(timeIntervalSince1970: Double(value) / 1_000_000 - 11_644_473_600) : nil
    }

    func chrome() -> [(String, Date?)] {
        let base = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        var profiles = ["Default"]
        if let data = try? Data(contentsOf: base.appendingPathComponent("Local State")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
            profiles = Array(Set(profiles + cache.keys)).sorted()
        }
        return profiles.flatMap { Self.chromeHistory(base.appendingPathComponent($0).appendingPathComponent("History")) }
    }

    /// Lê uma cópia do banco (o Chrome aberto trava o original), só os downloads concluídos.
    static func chromeHistory(_ db: URL) -> [(String, Date?)] {
        guard FileManager.default.fileExists(atPath: db.path) else { return [] }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("cym-chrome-\(UUID().uuidString).db")
        guard (try? FileManager.default.copyItem(at: db, to: copy)) != nil else { return [] }
        defer { try? FileManager.default.removeItem(at: copy) }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        let sql = "SELECT current_path, start_time, received_bytes, total_bytes FROM downloads"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [(String, Date?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let text = sqlite3_column_text(stmt, 0) else { continue }
            let received = sqlite3_column_int64(stmt, 2), total = sqlite3_column_int64(stmt, 3)
            guard total > 0, received == total else { continue }
            out.append((String(cString: text), chromeDate(sqlite3_column_int64(stmt, 1))))
        }
        return out
    }

    // MARK: - Safari

    func safari() -> [(String, Date?)] {
        let url = home.appendingPathComponent("Library/Safari/Downloads.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let history = plist["DownloadHistory"] as? [[String: Any]] else { return [] }
        return history.compactMap { e in
            guard let path = e["DownloadEntryPath"] as? String else { return nil }
            let done = (e["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value
            let total = (e["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
            if let done, let total, total > 0, done < total { return nil }
            return (path, e["DownloadEntryDateAddedKey"] as? Date)
        }
    }

    // MARK: - Quarentena (só para ler a data em outros usos)

    /// `flags;hex(segundos desde 1970);agente;uuid`.
    static func parseQuarantine(_ value: String) -> (agent: String, date: Date?)? {
        let parts = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, !parts[2].isEmpty else { return nil }
        return (parts[2], UInt64(parts[1], radix: 16).map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    static func quarantine(_ path: String) -> (agent: String, date: Date?)? {
        let n = getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        guard n > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: n)
        guard getxattr(path, "com.apple.quarantine", &buffer, n, 0, XATTR_NOFOLLOW) == n else { return nil }
        return parseQuarantine(String(decoding: buffer, as: UTF8.self))
    }
}
