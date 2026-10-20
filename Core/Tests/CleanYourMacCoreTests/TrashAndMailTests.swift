import Testing
import Foundation
import SQLite3
@testable import CleanYourMacCore

// MARK: - Lixos

struct FakeVolumes: VolumeProvider {
    var volumes: [MountedVolume]
    func mountedVolumes() -> [MountedVolume] { volumes }
}

private func trashScanner(_ volumes: [MountedVolume] = []) -> TrashScanner {
    TrashScanner(volumes: FakeVolumes(volumes: volumes))
}

private func scan(_ s: any GroupScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}

private func child(_ items: [JunkItem], key: String) -> JunkItem? { items.first { $0.titleKey == key } }

@Test func trash_userTrashChildren() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/.Trash/a.txt", bytes: 10)
    t.file("Users/tester/.Trash/pasta/b.bin", bytes: 5000)
    t.file("Users/tester/.Trash/.DS_Store", bytes: 10)
    let system = child(try await scan(trashScanner(), ctx), key: "trash.system")
    #expect(Set(system?.children.map(\.name) ?? []) == [".DS_Store", "a.txt", "pasta"])
    #expect(system?.leaves.allSatisfy { $0.isRecommended } == true)
}

@Test func trash_missingIsEmpty() async throws {
    let t = FixtureTree()
    #expect(try await scan(trashScanner(), t.context()).isEmpty)
}

@Test func trash_iCloudTrashes() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Mobile Documents/com~apple~CloudDocs/.Trash/x.pages", bytes: 10)
    t.file("Users/tester/Library/Mobile Documents/com~apple~Keynote/Documents/.Trash/k.key", bytes: 10)
    t.dir("Users/tester/Library/Mobile Documents/com~apple~Pages/Documents")
    let system = child(try await scan(trashScanner(), ctx), key: "trash.system")
    #expect(Set(system?.children.map(\.name) ?? []) == ["x.pages", "k.key"])
}

@Test func trash_mountedVolumes() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let usb = t.dir("Volumes/USB")
    t.file("Volumes/USB/.Trashes/\(getuid())/f.mov", bytes: 10)
    t.file("Volumes/USB/.Trashes/99999/g.mov", bytes: 10)
    let net = t.dir("Volumes/NAS")
    t.file("Volumes/NAS/.Trashes/\(getuid())/n.mov", bytes: 10)
    let vols = [MountedVolume(url: usb, name: "USB", isBrowsable: true, isLocal: true, isReadOnly: false),
                MountedVolume(url: net, name: "NAS", isBrowsable: true, isLocal: false, isReadOnly: false),
                MountedVolume(url: t.root, name: "Macintosh HD", isBrowsable: true, isLocal: true, isReadOnly: false)]
    let mounted = child(try await scan(trashScanner(vols), ctx), key: "trash.mounted")
    #expect(mounted?.children.map(\.name) == ["USB"])
    #expect(mounted?.children.first?.children.map(\.name) == ["f.mov"])
}

@Test func trash_removalKeepsTrashFolder() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/.Trash/pasta/b.bin", bytes: 10)
    let s = trashScanner()
    let items = try await scan(s, ctx)
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")))
    for await _ in engine.clean(items) {}
    #expect(!FileManager.default.fileExists(atPath: t.url("Users/tester/.Trash/pasta").path))
    #expect(FileManager.default.fileExists(atPath: t.url("Users/tester/.Trash").path))
    let policy = Registry.policies(for: [s], context: ctx)[.trash]!
    #expect((try? policy.validate(t.url("Users/tester/.Trash"))) == nil)
    #expect((try? policy.validate(t.url("Users/tester/Documents/x"))) == nil)
}

@Test func trash_lockedFileUnlockedAndDeleted() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let f = t.file("Users/tester/.Trash/locked.txt", bytes: 10)
    chflags(f.path, UInt32(UF_IMMUTABLE))
    let s = trashScanner()
    let items = try await scan(s, ctx)
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")))
    for await _ in engine.clean(items) {}
    #expect(!FileManager.default.fileExists(atPath: f.path))
}

// MARK: - Contas do Mail

struct FakeAccounts: MailAccountSource {
    var accounts: [MailAccount]
    func accounts(_ context: ScanContext) -> [MailAccount] { accounts }
}

private func imap(_ id: String, _ name: String, active: Bool = true, trash: String? = nil) -> MailAccount {
    MailAccount(identifier: id, name: name, type: "com.apple.account.IMAP", isActive: active, trashMailboxName: trash)
}

private func mailVersion(_ t: FixtureTree) {
    t.dir("Users/tester/Library/Mail")
    try! PropertyListSerialization.data(fromPropertyList: ["LastUsedVersionDirectoryName": "V10"], format: .xml, options: 0)
        .write(to: t.url("Users/tester/Library/Mail/PersistenceInfo.plist"))
}

@Test func mail_attachmentsGroupedByNameAndSize() async throws {
    let t = FixtureTree(); let ctx = t.context(); mailVersion(t)
    let base = "Users/tester/Library/Mail/V10/ACC1/INBOX.mbox/UUID/Data/1/Attachments"
    t.file("\(base)/10/2/report.pdf", bytes: 5000)
    t.file("\(base)/11/2/report.pdf", bytes: 5000)
    t.file("\(base)/12/2/photo.jpg", bytes: 300)
    let s = MailAttachmentsScanner(accounts: FakeAccounts(accounts: [imap("ACC1", "Trabalho")]))
    let items = try await scan(s, ctx)
    let account = items.first { $0.name == "Trabalho" }
    #expect(Set(account?.children.map(\.name) ?? []) == ["report.pdf", "photo.jpg"])
    #expect(account?.children.first { $0.name == "report.pdf" }?.children.count == 2)
    #expect(account?.leaves.allSatisfy { $0.isRecommended } == true)
}

@Test func mail_inactiveOrOfflineOrPOPSkipped() async throws {
    let t = FixtureTree(); let ctx = t.context(); mailVersion(t)
    for id in ["OFF", "INA", "POP"] { t.file("Users/tester/Library/Mail/V10/\(id)/x.mbox/Attachments/1/a.txt", bytes: 10) }
    try PropertyListSerialization.data(fromPropertyList: ["takenOffline": "YES"], format: .xml, options: 0)
        .write(to: t.url("Users/tester/Library/Mail/V10/OFF/.mboxCache.plist"))
    let pop = MailAccount(identifier: "POP", name: "pop", type: "com.apple.account.POP", isActive: true, trashMailboxName: nil)
    let s = MailAttachmentsScanner(accounts: FakeAccounts(accounts: [imap("OFF", "off"), imap("INA", "ina", active: false), pop]))
    #expect(try await scan(s, ctx).isEmpty)
}

@Test func mail_downloadsRecommendedOnlyIfUnmodified() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let fresh = t.file("Users/tester/Library/Mail Downloads/8A4B1C2D-1111-2222-3333-444455556666/fresh.pdf", bytes: 10)
    let edited = t.file("Users/tester/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/edited.docx", bytes: 10)
    t.file("Users/tester/Library/Mail Downloads/.DS_Store", bytes: 10)
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    for u in [fresh, edited] { try FileManager.default.setAttributes([.creationDate: created, .modificationDate: created], ofItemAtPath: u.path) }
    try FileManager.default.setAttributes([.modificationDate: created.addingTimeInterval(60)], ofItemAtPath: edited.path)
    let s = MailAttachmentsScanner(accounts: FakeAccounts(accounts: []))
    let downloads = child(try await scan(s, ctx), key: "mail.downloads")
    let byName = Dictionary(uniqueKeysWithValues: (downloads?.children ?? []).map { ($0.name, $0) })
    #expect(Set(byName.keys) == ["fresh.pdf", "edited.docx"])
    #expect(byName["fresh.pdf"]?.isRecommended == true)
    #expect(byName["edited.docx"]?.isRecommended == false)
    #expect(byName["fresh.pdf"]?.removal == .delete(fresh.deletingLastPathComponent()))
}

// MARK: - Lixo do Mail

@Test func mailTrash_messagesWithAttachments() async throws {
    let t = FixtureTree(); let ctx = t.context(); mailVersion(t)
    let box = "Users/tester/Library/Mail/V10/ACC1/[Gmail].mbox/Lixeira.mbox/UUID/Data/1/2"
    t.file("\(box)/Messages/123.emlx", bytes: 2000)
    t.file("\(box)/Messages/124.2.emlxpart", bytes: 500)
    t.file("\(box)/Messages/info.plist", bytes: 10)
    t.file("\(box)/Attachments/123/2/file.pdf", bytes: 9000)
    let s = MailTrashScanner(accounts: FakeAccounts(accounts: [imap("ACC1", "Gmail", trash: "[Gmail]/Lixeira")]))
    let account = try await scan(s, ctx).first
    #expect(account?.name == "Gmail")
    #expect(Set(account?.children.map(\.name) ?? []) == ["123.emlx", "124.2.emlxpart"])
    let msg = account?.children.first { $0.name == "123.emlx" }
    #expect(msg?.children.map(\.name) == ["123.emlx", "file.pdf"])
    #expect(msg?.leaves.count == 2)
    #expect(account?.leaves.allSatisfy { $0.isRecommended } == true)
}

@Test func mailTrash_accountWithoutTrashSkipped() async throws {
    let t = FixtureTree(); let ctx = t.context(); mailVersion(t)
    t.file("Users/tester/Library/Mail/V10/ACC1/Trash.mbox/Data/Messages/1.emlx", bytes: 10)
    let s = MailTrashScanner(accounts: FakeAccounts(accounts: [imap("ACC1", "x")]))
    #expect(try await scan(s, ctx).isEmpty)
}

@Test func mailTrash_nameFromEnvelopeIndex() async throws {
    let t = FixtureTree(); let ctx = t.context(); mailVersion(t)
    t.file("Users/tester/Library/Mail/V10/ACC1/Trash.mbox/Data/Messages/7.emlx", bytes: 10)
    let db = t.dir("Users/tester/Library/Mail/V10/MailData").appendingPathComponent("Envelope Index")
    try execSQL(db, """
        CREATE TABLE subjects (ROWID INTEGER PRIMARY KEY, subject TEXT);
        CREATE TABLE addresses (ROWID INTEGER PRIMARY KEY, address TEXT, comment TEXT);
        CREATE TABLE messages (ROWID INTEGER PRIMARY KEY, subject INTEGER, sender INTEGER);
        INSERT INTO subjects VALUES (1, 'Fatura de outubro');
        INSERT INTO addresses VALUES (1, 'ana@example.com', 'Ana');
        INSERT INTO messages VALUES (7, 1, 1);
        """)
    let s = MailTrashScanner(accounts: FakeAccounts(accounts: [imap("ACC1", "x", trash: "Trash")]))
    #expect(try await scan(s, ctx).first?.children.map(\.name) == ["Ana: Fatura de outubro"])
}

func execSQL(_ url: URL, _ sql: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
}

@Test func accounts_readFromAccountsDB() throws {
    let t = FixtureTree(); let ctx = t.context()
    let db = t.dir("Users/tester/Library/Accounts").appendingPathComponent("Accounts4.sqlite")
    let props = try PropertyListSerialization.data(fromPropertyList: ["com.apple.Dataclass.Mail": ["TrashMailboxName": "Trash"]],
                                                   format: .binary, options: 0)
    try execSQL(db, """
        CREATE TABLE ZACCOUNTTYPE (Z_PK INTEGER PRIMARY KEY, ZIDENTIFIER TEXT);
        CREATE TABLE ZACCOUNT (Z_PK INTEGER PRIMARY KEY, ZACCOUNTTYPE INTEGER, ZIDENTIFIER TEXT, ZACCOUNTDESCRIPTION TEXT,
                               ZPARENTACCOUNT INTEGER, ZDATACLASSPROPERTIES BLOB);
        CREATE TABLE ZDATACLASS (Z_PK INTEGER PRIMARY KEY, ZIDENTIFIER TEXT);
        CREATE TABLE Z_2ENABLEDDATACLASSES (Z_2ENABLEDACCOUNTS INTEGER, Z_4ENABLEDDATACLASSES INTEGER);
        INSERT INTO ZACCOUNTTYPE VALUES (1, 'com.apple.account.IMAP'), (2, 'com.apple.account.Google');
        INSERT INTO ZDATACLASS VALUES (1, 'com.apple.Dataclass.Mail'), (2, 'com.apple.Dataclass.Notes');
        INSERT INTO ZACCOUNT VALUES (1, 2, 'PARENT', 'Gmail pessoal', NULL, NULL);
        INSERT INTO ZACCOUNT VALUES (2, 1, 'ACC-A', NULL, 1, X'\(props.map { String(format: "%02X", $0) }.joined())');
        INSERT INTO ZACCOUNT VALUES (3, 1, 'ACC-B', 'Sem mail', NULL, NULL);
        INSERT INTO Z_2ENABLEDDATACLASSES VALUES (2, 1), (3, 2);
        """)
    let accounts = SQLiteMailAccounts().accounts(ctx)
    let a = accounts.first { $0.identifier == "ACC-A" }
    #expect(a?.name == "Gmail pessoal")
    #expect(a?.isActive == true)
    #expect(a?.trashMailboxName == "Trash")
    #expect(accounts.first { $0.identifier == "ACC-B" }?.isActive == false)
}
