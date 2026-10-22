import Foundation
import Testing
@testable import CleanYourMacCore

/// Lista de sessão em memória.
final class MemoryLoginItems: LoginItemsSource, @unchecked Sendable {
    var urls: [URL]
    var failRemove = false
    init(_ urls: [URL]) { self.urls = urls }
    func entries(_ context: ScanContext) -> [LoginItemEntry] { urls.map { LoginItemEntry(name: $0.deletingPathExtension().lastPathComponent, url: $0) } }
    func remove(_ entry: LoginItemEntry) -> Bool {
        guard !failRemove, let i = urls.firstIndex(of: entry.url!) else { return false }
        urls.remove(at: i)
        return true
    }
    func add(_ app: URL) -> Bool {
        urls.append(app)
        return true
    }
}

private func plist(_ t: FixtureTree, _ rel: String, _ dict: [String: Any]) -> URL {
    let u = t.url(rel)
    t.dir((rel as NSString).deletingLastPathComponent)
    try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: u)
    return u
}

private struct Setup {
    let t = FixtureTree()
    let commands = HelperFakeCommands()
    let privileged = RecordingPrivileged()
    let trasher: FixtureTrasher
    let login: MemoryLoginItems
    let store: DisabledLoginItemsStore
    let ctx: ScanContext

    init() {
        ctx = t.context()
        trasher = FixtureTrasher(t.url("Users/tester/.Trash"))
        login = MemoryLoginItems([])
        store = DisabledLoginItemsStore(url: t.url("Users/tester/Library/Application Support/CleanYourMac/disabled-login-items.json"))
    }

    func actions(dryRun: Bool = false) -> StartupItemsActions {
        StartupItemsActions(loginItems: login, commands: commands, privileged: privileged, trasher: trasher,
                            disabledRecord: store, context: ctx, dryRun: dryRun)
    }

    func scan() -> [StartupItem] {
        StartupItemsScanner(loginItems: login, commands: commands, disabledRecord: store, displayName: { $0.lastPathComponent }).items(ctx)
    }
}

private func ok(_ r: Result<Void, CleanFailure>?) -> Bool { if case .success = r { true } else { false } }
private func reason(_ r: Result<Void, CleanFailure>?) -> String? { if case .failure(let f) = r { f.reason } else { nil } }

@Suite struct StartupItemsActionsTests {
    @Test func disableUserAgentReversible() async {
        let s = Setup()
        let p = plist(s.t, "Users/tester/Library/LaunchAgents/com.example.u.plist", ["Label": "com.example.u.job"])
        let item = s.scan()[0]
        let r = await s.actions().perform(.disable, on: [item])
        #expect(ok(r[item.id]))
        #expect(s.commands.calls.suffix(2) == [["/bin/launchctl", "disable", "gui/\(s.ctx.uid)/com.example.u.job"],
                                               ["/bin/launchctl", "bootout", "gui/\(s.ctx.uid)/com.example.u.job"]])
        let r2 = await s.actions().perform(.enable, on: [item])
        #expect(ok(r2[item.id]))
        #expect(s.commands.calls.suffix(2) == [["/bin/launchctl", "enable", "gui/\(s.ctx.uid)/com.example.u.job"],
                                               ["/bin/launchctl", "bootstrap", "gui/\(s.ctx.uid)", p.path]])
        #expect(s.privileged.batches.isEmpty)
        #expect(FileManager.default.fileExists(atPath: p.path))
    }

    @Test func systemAgentDisableWithoutRoot() async {
        let s = Setup()
        plist(s.t, "Library/LaunchAgents/com.example.a.plist", ["Label": "com.example.a"])
        let item = s.scan()[0]
        _ = await s.actions().perform(.disable, on: [item])
        #expect(s.commands.calls.contains(["/bin/launchctl", "disable", "gui/\(s.ctx.uid)/com.example.a"]))
        #expect(s.privileged.batches.isEmpty)
    }

    @Test func systemItemsGoToHelper() async {
        let s = Setup()
        let d1 = plist(s.t, "Library/LaunchDaemons/com.example.d1.plist", ["Label": "com.example.d1"])
        let d2 = plist(s.t, "Library/LaunchDaemons/com.example.d2.plist", ["Label": "com.example.d2"])
        let items = s.scan()
        let r = await s.actions().perform(.disable, on: items)
        #expect(items.allSatisfy { ok(r[$0.id]) })
        #expect(s.privileged.batches == [[.launchdDisable(plist: d1, owner: "com.example.d1"), .launchdDisable(plist: d2, owner: "com.example.d2")]])
        _ = await s.actions().perform(.enable, on: items)
        #expect(s.privileged.batches.last == [.launchdEnable(plist: d1, owner: "com.example.d1"), .launchdEnable(plist: d2, owner: "com.example.d2")])
    }

    @Test func removeTrashesPlistAndHelperTool() async {
        let s = Setup()
        let app = s.t.app("Applications/Foo.app", bundleID: "com.vendor.foo")
        let tool = s.t.file("Library/PrivilegedHelperTools/com.vendor.foo.helper", bytes: 1)
        let d = plist(s.t, "Library/LaunchDaemons/com.vendor.foo.helper.plist",
                      ["Label": "com.vendor.foo.helper", "Program": tool.path, "AssociatedBundleIdentifiers": ["com.vendor.foo"]])
        let other = s.t.file("Library/PrivilegedHelperTools/com.other.tool", bytes: 1)
        let d2 = plist(s.t, "Library/LaunchDaemons/com.vendor.bar.plist", ["Label": "com.vendor.bar", "Program": other.path])
        let owned = plist(s.t, "Library/LaunchDaemons/com.vendor.foo.svc.plist",
                          ["Label": "com.vendor.foo.svc", "Program": app.path + "/Contents/MacOS/app"])
        let u = plist(s.t, "Users/tester/Library/LaunchAgents/com.example.u.plist", ["Label": "com.example.u"])
        let items = s.scan()
        let r = await s.actions().perform(.remove, on: items)
        #expect(items.allSatisfy { ok(r[$0.id]) })
        #expect(s.privileged.batches == [[
            .launchdBootout(plist: d2, owner: "com.vendor.bar"), .trash(d2, owner: "com.vendor.bar"),
            .launchdBootout(plist: d, owner: "com.vendor.foo.helper"), .trash(d, owner: "com.vendor.foo.helper"),
            .trash(tool, owner: "com.vendor.foo.helper"),
            .launchdBootout(plist: owned, owner: "com.vendor.foo"), .trash(owned, owner: "com.vendor.foo"),
        ]])
        #expect(s.commands.calls.contains(["/bin/launchctl", "bootout", "gui/\(s.ctx.uid)/com.example.u"]))
        #expect(s.trasher.trashed == [u])
        #expect(FileManager.default.fileExists(atPath: app.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func sessionDisableKeepsRecordAndEnableRestores() async {
        let t0 = Setup()
        let warp = t0.t.app("Applications/Warp.app", bundleID: "dev.warp.Warp-Stable")
        let s2 = Setup2(app: warp)
        let item = s2.scan()[0]
        let r = await s2.actions().perform(.disable, on: [item])
        #expect(ok(r[item.id]))
        #expect(s2.login.urls.isEmpty)
        #expect(s2.store.load().map(\.path) == [warp.path])
        #expect(s2.scan().map(\.state) == [.disabled])
        let disabled = s2.scan()[0]
        let r2 = await s2.actions().perform(.enable, on: [disabled])
        #expect(ok(r2[disabled.id]))
        #expect(s2.login.urls.map(\.path) == [warp.path])
        #expect(s2.store.load().isEmpty)
    }

    @Test func sessionDisableUndoesRecordWhenRemoveFails() async {
        let t0 = Setup()
        let warp = t0.t.app("Applications/Warp.app", bundleID: "dev.warp.Warp-Stable")
        let s = Setup2(app: warp)
        s.login.failRemove = true
        let item = s.scan()[0]
        let r = await s.actions().perform(.disable, on: [item])
        #expect(!ok(r[item.id]))
        #expect(s.store.load().isEmpty)
    }

    @Test func actionRevalidatesItem() async throws {
        let s = Setup()
        let p = plist(s.t, "Library/LaunchDaemons/com.example.d.plist", ["Label": "com.example.d"])
        let item = s.scan()[0]
        plist(s.t, "Library/LaunchDaemons/com.example.d.plist", ["Label": "com.example.other"])
        var r = await s.actions().perform(.remove, on: [item])
        #expect(reason(r[item.id]) == "item changed")
        try FileManager.default.removeItem(at: p)
        let real = plist(s.t, "Library/elsewhere/x.plist", ["Label": "com.example.d"])
        _ = s.t.symlink("Library/LaunchDaemons/com.example.d.plist", to: real)
        r = await s.actions().perform(.disable, on: [item])
        #expect(reason(r[item.id]) == "item changed")
        #expect(s.privileged.batches.isEmpty && s.commands.calls.allSatisfy { $0.contains("print-disabled") })
    }

    @Test func ownerInstalledWarns() {
        let s = Setup()
        let app = s.t.app("Applications/Foo.app", bundleID: "com.vendor.foo")
        plist(s.t, "Library/LaunchDaemons/com.vendor.foo.svc.plist", ["Label": "com.vendor.foo.svc", "Program": app.path + "/Contents/MacOS/app"])
        plist(s.t, "Library/LaunchDaemons/com.lone.plist", ["Label": "com.lone"])
        let items = s.scan()
        let owned = items.first { $0.ownerApp != nil }!, lone = items.first { $0.ownerApp == nil }!
        #expect(s.actions().warnings(for: owned).map { if case .ownerMayRecreate(let u) = $0 { u.path } else { "" } } == [app.path])
        #expect(s.actions().warnings(for: lone).isEmpty)
    }

    @Test func dryRunTouchesNothing() async {
        let s = Setup()
        let d = plist(s.t, "Library/LaunchDaemons/com.example.d.plist", ["Label": "com.example.d"])
        let u = plist(s.t, "Users/tester/Library/LaunchAgents/com.example.u.plist", ["Label": "com.example.u"])
        let items = s.scan()
        let before = s.commands.calls.count
        let r = await s.actions(dryRun: true).perform(.remove, on: items)
        #expect(items.allSatisfy { ok(r[$0.id]) })
        #expect(s.commands.calls.count == before && s.privileged.batches.isEmpty && s.trasher.trashed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: d.path) && FileManager.default.fileExists(atPath: u.path))
    }
}

/// Lista de sessão com um app de outro fixture.
private struct Setup2 {
    let base = Setup()
    let login: MemoryLoginItems
    var store: DisabledLoginItemsStore { base.store }
    init(app: URL) { login = MemoryLoginItems([app]) }
    func actions() -> StartupItemsActions {
        StartupItemsActions(loginItems: login, commands: base.commands, privileged: base.privileged, trasher: base.trasher,
                            disabledRecord: base.store, context: base.ctx, dryRun: false)
    }
    func scan() -> [StartupItem] {
        StartupItemsScanner(loginItems: login, commands: base.commands, disabledRecord: base.store, displayName: { $0.lastPathComponent }).items(base.ctx)
    }
}
