import Foundation
import SQLite3

/// Uma conta do app Mail (docs/re/specs/mail-attachments.md, mail-trash.md).
public struct MailAccount: Sendable, Hashable {
    public let identifier: String
    public let name: String
    public let type: String
    public let isActive: Bool
    public let trashMailboxName: String?

    public init(identifier: String, name: String, type: String, isActive: Bool, trashMailboxName: String?) {
        self.identifier = identifier
        self.name = name
        self.type = type
        self.isActive = isActive
        self.trashMailboxName = trashMailboxName
    }

    public var isIMAP: Bool { type == "com.apple.account.IMAP" || type == "com.apple.account.IMAPMail" }
}

public protocol MailAccountSource: Sendable {
    func accounts(_ context: ScanContext) -> [MailAccount]
}

/// Pasta da biblioteca do Mail (`~/Library/Mail/<Vn>`), lida de `PersistenceInfo.plist`.
enum MailLibrary {
    static func versionDirectory(_ ctx: ScanContext) -> URL? {
        let plist = ctx.resolve("~/Library/Mail/PersistenceInfo.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = dict["LastUsedVersionDirectoryName"] as? String, !version.isEmpty else { return nil }
        return ctx.resolve("~/Library/Mail/\(version)")
    }
}

/// Lê `~/Library/Accounts/Accounts4.sqlite` (somente leitura), achando tabelas e colunas por sufixo.
public struct SQLiteMailAccounts: MailAccountSource {
    public init() {}

    public func accounts(_ context: ScanContext) -> [MailAccount] {
        let url = context.resolve("~/Library/Accounts/Accounts4.sqlite")
        guard let db = SQLiteReader(url: url) else { return [] }
        let tables = db.tables()
        let upper = tables.map { ($0, $0.uppercased()) }
        let accountTable: String? = upper.first(where: { $0.1 == "ZACCOUNT" })?.0
            ?? upper.first(where: { $0.1.hasSuffix("ACCOUNT") })?.0
        let typeTableName: String? = upper.first(where: { $0.1.hasSuffix("ACCOUNTTYPE") })?.0
        guard let account = accountTable, let typeTable = typeTableName else { return [] }
        let cols = db.columns(account)
        func col(_ suffix: String, in list: [String]) -> String? { list.first { $0.uppercased().hasSuffix(suffix) } }
        let typeColumn: String? = cols.first(where: { $0.uppercased() == "ZACCOUNTTYPE" }) ?? col("ACCOUNTTYPE", in: cols)
        guard let pk = col("Z_PK", in: cols), let typeCol = typeColumn, let idCol = col("IDENTIFIER", in: cols) else { return [] }
        let descCol = col("ACCOUNTDESCRIPTION", in: cols)
        let parentCol = col("PARENTACCOUNT", in: cols)
        let propsCol = col("DATACLASSPROPERTIES", in: cols)
        let typeCols = db.columns(typeTable)
        guard let typePK = col("Z_PK", in: typeCols), let typeID = col("IDENTIFIER", in: typeCols) else { return [] }

        // Contas habilitadas para Mail (tabela de junção *ENABLEDDATACLASSES).
        var mailEnabled: Set<Int64> = []
        var hasAnyDataclass: Set<Int64> = []
        if let join = tables.first(where: { $0.uppercased().hasSuffix("ENABLEDDATACLASSES") }),
           let dataclass = tables.first(where: { $0.uppercased() == "ZDATACLASS" }) {
            let jc = db.columns(join)
            if let accCol = col("ENABLEDACCOUNTS", in: jc), let dcCol = col("ENABLEDDATACLASSES", in: jc) {
                let rows = db.query("SELECT j.\"\(accCol)\", d.ZIDENTIFIER FROM \"\(join)\" j LEFT JOIN \"\(dataclass)\" d ON d.Z_PK = j.\"\(dcCol)\"")
                for row in rows {
                    guard let acc = row[0] as? Int64 else { continue }
                    hasAnyDataclass.insert(acc)
                    if (row[1] as? String) == "com.apple.Dataclass.Mail" { mailEnabled.insert(acc) }
                }
            }
        }

        func column(_ name: String?) -> String { name.map { "a.\"\($0)\"" } ?? "NULL" }
        let parts: [String] = ["a.\"\(pk)\"", "a.\"\(idCol)\"", "t.\"\(typeID)\"", column(descCol), column(parentCol), column(propsCol)]
        let select = parts.joined(separator: ", ")
        let rows = db.query("SELECT \(select) FROM \"\(account)\" a LEFT JOIN \"\(typeTable)\" t ON t.\"\(typePK)\" = a.\"\(typeCol)\"")
        var descriptions: [Int64: String] = [:]
        for row in rows { if let k = row[0] as? Int64, let d = row[3] as? String { descriptions[k] = d } }

        return rows.compactMap { row in
            guard let key = row[0] as? Int64, let identifier = row[1] as? String, let type = row[2] as? String else { return nil }
            let own = row[3] as? String
            let parent = (row[4] as? Int64).flatMap { descriptions[$0] }
            var trash: String?
            if let blob = row[5] as? Data,
               let dict = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any],
               let mail = dict["com.apple.Dataclass.Mail"] as? [String: Any] {
                trash = (mail["TrashMailboxName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
            let active = !hasAnyDataclass.contains(key) || mailEnabled.contains(key)
            return MailAccount(identifier: identifier, name: parent ?? own ?? identifier, type: type,
                               isActive: active, trashMailboxName: trash)
        }
    }
}

/// Acesso mínimo e somente leitura a um banco SQLite.
final class SQLiteReader {
    private var db: OpaquePointer?

    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
    }

    deinit { sqlite3_close(db) }

    func tables() -> [String] {
        query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0[0] as? String }
    }

    func columns(_ table: String) -> [String] {
        query("PRAGMA table_info(\"\(table)\")").compactMap { $0[1] as? String }
    }

    /// Cada linha como uma lista de valores (Int64, Double, String, Data ou nil).
    func query(_ sql: String, _ bind: [Int64] = []) -> [[Any?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, v) in bind.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), v) }
        var out: [[Any?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let n = sqlite3_column_count(stmt)
            out.append((0..<n).map { i -> Any? in
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT: sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: sqlite3_column_text(stmt, i).map { String(cString: $0) }
                case SQLITE_BLOB:
                    sqlite3_column_blob(stmt, i).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(stmt, i))) }
                default: nil
                }
            })
        }
        return out
    }
}

// MARK: - Volumes

public struct MountedVolume: Sendable, Hashable {
    public let url: URL
    public let name: String
    public let isBrowsable: Bool
    public let isLocal: Bool
    public let isReadOnly: Bool

    public init(url: URL, name: String, isBrowsable: Bool, isLocal: Bool, isReadOnly: Bool) {
        self.url = url
        self.name = name
        self.isBrowsable = isBrowsable
        self.isLocal = isLocal
        self.isReadOnly = isReadOnly
    }
}

public protocol VolumeProvider: Sendable {
    func mountedVolumes() -> [MountedVolume]
}

public struct SystemVolumes: VolumeProvider {
    public init() {}

    public func mountedVolumes() -> [MountedVolume] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsBrowsableKey, .volumeIsLocalKey, .volumeIsReadOnlyKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return MountedVolume(url: u, name: v.volumeLocalizedName ?? u.lastPathComponent, isBrowsable: v.volumeIsBrowsable ?? false,
                                 isLocal: v.volumeIsLocal ?? false, isReadOnly: v.volumeIsReadOnly ?? true)
        }
    }
}
