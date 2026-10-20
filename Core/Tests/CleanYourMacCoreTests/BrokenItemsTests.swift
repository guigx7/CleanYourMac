import Testing
import Foundation
@testable import CleanYourMacCore

final class FakeCommands: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    var status: Int32 = 0
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        lock.lock(); calls.append([executable] + arguments); lock.unlock()
        return (status, "")
    }
}

struct FakeLoginItems: LoginItemsSource {
    var entries: [LoginItemEntry]
    func entries(_ context: ScanContext) -> [LoginItemEntry] { entries }
}

private func scan(_ s: any GroupScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}

private func plist(_ t: FixtureTree, _ rel: String, _ dict: [String: Any]) -> URL {
    let u = t.url(rel)
    t.dir((rel as NSString).deletingLastPathComponent)
    try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: u)
    return u
}

private func launchd(_ entries: [LoginItemEntry] = [], inventory: any AppInventory = FolderAppInventory()) -> BrokenLoginItemsScanner {
    BrokenLoginItemsScanner(loginItems: FakeLoginItems(entries: entries), inventory: inventory)
}

private let agents = "Users/tester/Library/LaunchAgents"

@Test func launchd_missingProgramIsBroken() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let p = plist(t, "\(agents)/x.plist", ["Label": "x", "Program": "/nao/existe"])
    let items = try await scan(launchd(), ctx)
    #expect(items.map(\.name) == ["x.plist"])
    #expect(items[0].isRecommended)
    #expect(items[0].size == FixtureTree.allocated(p))
}

@Test func launchd_existingProgramOK() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let exe = t.file("bin/tool", bytes: 10)
    _ = plist(t, "\(agents)/x.plist", ["Program": exe.path])
    #expect(try await scan(launchd(), ctx).isEmpty)
}

@Test func launchd_programArguments() async throws {
    let t = FixtureTree(); let ctx = t.context()
    _ = plist(t, "\(agents)/a.plist", ["ProgramArguments": ["/nao/existe", "-a"]])
    #expect(try await scan(launchd(), ctx).map(\.name) == ["a.plist"])
}

@Test func launchd_workingDirectoryRelative() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let wd = t.dir("wd")
    t.file("wd/rel/tool", bytes: 10)
    _ = plist(t, "\(agents)/ok.plist", ["ProgramArguments": ["rel/tool"], "WorkingDirectory": wd.path])
    _ = plist(t, "\(agents)/bad.plist", ["ProgramArguments": ["rel/missing"], "WorkingDirectory": wd.path])
    #expect(try await scan(launchd(), ctx).map(\.name) == ["bad.plist"])
}

@Test func launchd_tildeExpanded() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/bin/tool", bytes: 10)
    _ = plist(t, "\(agents)/x.plist", ["ProgramArguments": ["~/bin/tool"]])
    #expect(try await scan(launchd(), ctx).isEmpty)
}

@Test func launchd_noProgramOrCorruptIsBroken() async throws {
    let t = FixtureTree(); let ctx = t.context()
    _ = plist(t, "\(agents)/empty.plist", ["Label": "e"])
    t.file("\(agents)/corrupt.plist", bytes: 30)
    #expect(Set(try await scan(launchd(), ctx).map(\.name)) == ["empty.plist", "corrupt.plist"])
}

@Test func launchd_extensionAndDepthAndPermissions() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("\(agents)/y.txt", bytes: 30)
    t.file("\(agents)/z.PLIST", bytes: 30)
    t.file("\(agents)/sub/w.plist", bytes: 30)
    t.file("\(agents)/locked.plist", bytes: 30)
    t.chmod("\(agents)/locked.plist", 0o000)
    #expect(try await scan(launchd(), ctx).isEmpty)
}

@Test func launchd_appleAgentsIgnored() async throws {
    let t = FixtureTree(); let ctx = t.context()
    _ = plist(t, "Library/LaunchAgents/com.apple.x.plist", ["Program": "/nao/existe"])
    #expect(try await scan(launchd(), ctx).isEmpty)
}

@Test func launchd_privilegedHelperOfInstalledApp() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = t.app("Applications/Foo.app", bundleID: "com.foo")
    var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
    info["SMPrivilegedExecutables"] = ["com.foo.helper": "anchor apple"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    _ = plist(t, "Library/LaunchDaemons/com.foo.helper.plist", ["Program": t.url("Library/PrivilegedHelperTools/com.foo.helper").path])
    #expect(try await scan(launchd(), ctx).isEmpty)
}

@Test func launchd_unreadableAreaNotBroken() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.dir("secret/inner")
    _ = plist(t, "\(agents)/x.plist", ["Program": t.url("secret/inner/tool").path])
    t.chmod("secret", 0o000)
    let items = try await scan(launchd(), ctx)
    t.chmod("secret", 0o755)
    #expect(items.isEmpty)
}

@Test func loginItems_brokenEntries() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let existing = t.dir("Applications/Ok.app")
    let entries = [LoginItemEntry(name: "Amphetamine", url: URL(fileURLWithPath: "/Applications/Amphetamine.app")),
                   LoginItemEntry(name: "Ok", url: existing),
                   LoginItemEntry(name: "Unresolved", url: nil)]
    let items = try await scan(launchd(entries), ctx)
    #expect(Set(items.map(\.name)) == ["Amphetamine", "Unresolved"])
    #expect(items.allSatisfy { $0.size == 0 && $0.isRecommended })
}

private func engine(_ t: FixtureTree, _ s: any ScopedScanner, _ ctx: ScanContext, commands: FakeCommands,
                    loginItems: any LoginItemsSource = FakeLoginItems(entries: [])) -> CleanEngine {
    CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(), dryRun: false,
                log: CleanupLog(directory: t.dir("logs")), commands: commands, loginItems: loginItems)
}

@Test func launchd_removalUnloadsAndDeletesHelper() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let p = plist(t, "\(agents)/com.foo.agent.plist", ["Program": "/nao/existe"])
    let helper = t.file("Library/PrivilegedHelperTools/com.foo.agent", bytes: 10)
    let s = launchd()
    let items = try await scan(s, ctx)
    let cmds = FakeCommands()
    for await _ in engine(t, s, ctx, commands: cmds).clean(items) {}
    #expect(cmds.calls.contains(["/bin/launchctl", "unload", p.path]))
    #expect(!FileManager.default.fileExists(atPath: p.path))
    #expect(!FileManager.default.fileExists(atPath: helper.path))
}

final class RecordingLoginItems: LoginItemsSource, @unchecked Sendable {
    var removed: [LoginItemEntry] = []
    func entries(_ context: ScanContext) -> [LoginItemEntry] { [] }
    func remove(_ entry: LoginItemEntry) -> Bool { removed.append(entry); return true }
}

@Test func loginItems_removalTouchesNoFiles() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let entry = LoginItemEntry(name: "Gone", url: URL(fileURLWithPath: "/Applications/Gone.app"))
    let s = launchd([entry])
    let items = try await scan(s, ctx)
    let recorder = RecordingLoginItems()
    for await _ in engine(t, s, ctx, commands: FakeCommands(), loginItems: recorder).clean(items) {}
    #expect(recorder.removed == [entry])
}

// MARK: - Preferências

private let prefs = "Users/tester/Library/Preferences"

@Test func prefs_corruptDetected() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let a = t.url("\(prefs)/a.plist"); t.dir(prefs)
    try Data("xx<<".utf8).write(to: a)
    _ = plist(t, "\(prefs)/b.plist", ["k": 1])
    let bin = try PropertyListSerialization.data(fromPropertyList: ["k": 1], format: .binary, options: 0)
    try bin.write(to: t.url("\(prefs)/c.plist"))
    t.file("\(prefs)/d.plist", bytes: 0)
    try Data("xx<<".utf8).write(to: t.url("\(prefs)/.e.plist"))
    try Data("xx<<".utf8).write(to: t.url("\(prefs)/g.lockfile.plist"))
    try Data("xx<<".utf8).write(to: t.url("\(prefs)/H.PLIST"))
    try Data("xx<<".utf8).write(to: t.url("\(prefs)/i.txt"))
    t.dir("\(prefs)/ByHost"); try Data("xx<<".utf8).write(to: t.url("\(prefs)/ByHost/j.plist"))
    let k = t.url("\(prefs)/k.plist"); try Data("xx<<".utf8).write(to: k); chflags(k.path, UInt32(UF_IMMUTABLE))
    let l = t.url("\(prefs)/l.plist"); try Data("xx<<".utf8).write(to: l); t.chmod("\(prefs)/l.plist", 0o000)
    let items = try await scan(BrokenPreferencesScanner(), ctx)
    chflags(k.path, 0)
    #expect(Set(items.map(\.name)) == ["a", "H"])
    #expect(items.allSatisfy { $0.isRecommended })
}

@Test func prefs_missingRoot() async throws {
    #expect(try await scan(BrokenPreferencesScanner(), FixtureTree().context()).isEmpty)
}

@Test func prefs_removalRunsDefaultsAndRestartsCfprefsd() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.dir(prefs)
    let a = t.url("\(prefs)/a.plist"); try Data("xx<<".utf8).write(to: a)
    let s = BrokenPreferencesScanner()
    let items = try await scan(s, ctx)
    let cmds = FakeCommands()
    for await _ in engine(t, s, ctx, commands: cmds).clean(items) {}
    #expect(!FileManager.default.fileExists(atPath: a.path))
    #expect(cmds.calls.first == ["/usr/bin/defaults", "delete", a.deletingPathExtension().path])
    #expect(cmds.calls.last?.first == "/usr/bin/killall")
}
