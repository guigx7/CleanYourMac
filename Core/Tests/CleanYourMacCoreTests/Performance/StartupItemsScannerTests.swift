import Foundation
import Testing
@testable import CleanYourMacCore

private func plist(_ t: FixtureTree, _ rel: String, _ dict: [String: Any]) -> URL {
    let u = t.url(rel)
    t.dir((rel as NSString).deletingLastPathComponent)
    try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: u)
    return u
}

@Suite struct StartupItemsScannerTests {
    func scanner(_ t: FixtureTree, login: [LoginItemEntry] = [], commands: HelperFakeCommands = HelperFakeCommands()) -> StartupItemsScanner {
        StartupItemsScanner(loginItems: FakeLoginItems(entries: login), commands: commands,
                            disabledRecord: DisabledLoginItemsStore(url: t.url("Users/tester/Library/Application Support/CleanYourMac/disabled-login-items.json")),
                            displayName: { $0.lastPathComponent })
    }

    @Test func sessionItemsFromLoginItemsSource() {
        let t = FixtureTree()
        let warp = t.app("Applications/Warp.app", bundleID: "dev.warp.Warp-Stable")
        let mine = t.app("Applications/CleanYourMac.app", bundleID: "io.github.guigx7.CleanYourMac")
        let apple = t.app("Applications/Safari.app", bundleID: "com.apple.Safari")
        let doc = t.file("Users/tester/notes.txt", bytes: 1)
        let entries = [LoginItemEntry(name: "Warp", url: warp), LoginItemEntry(name: "Gone", url: nil),
                       LoginItemEntry(name: "Missing", url: t.url("Applications/Missing.app")),
                       LoginItemEntry(name: "Mine", url: mine), LoginItemEntry(name: "Safari", url: apple),
                       LoginItemEntry(name: "notes", url: doc)]
        let items = scanner(t, login: entries).items(t.context())
        #expect(items.map(\.name) == ["Warp.app"])
        let w = items[0]
        #expect(w.kind == .sessionLoginItem && !w.isBackground && w.state == .enabled)
        #expect(w.ownerBundleID == "dev.warp.Warp-Stable")
        #expect(w.program?.path == warp.path)
    }

    @Test func launchdPlistsFromSpecFolders() {
        let t = FixtureTree()
        let ctx = t.context()
        plist(t, "Users/tester/Library/LaunchAgents/com.example.user.plist", ["Label": "com.example.user", "Program": "/usr/local/bin/u"])
        plist(t, "Library/LaunchAgents/com.example.agent.plist", ["Label": "com.example.agent"])
        plist(t, "Library/LaunchDaemons/com.example.daemon.plist", ["Label": "com.example.daemon"])
        plist(t, "Library/LaunchDaemons/.hidden.plist", ["Label": "com.example.hidden"])
        plist(t, "Library/LaunchDaemons/com.apple.thing.plist", ["Label": "com.apple.thing"])
        plist(t, "Library/LaunchDaemons/com.other.x.plist", ["Label": "com.apple.disguised"])
        plist(t, "Library/LaunchDaemons/com.macpaw.CleanMyMac.Agent.plist", ["Label": "com.macpaw.CleanMyMac.Agent"])
        plist(t, "Library/LaunchDaemons/io.github.guigx7.CleanYourMac.helper.plist", ["Label": "io.github.guigx7.CleanYourMac.helper"])
        plist(t, "Library/LaunchDaemons/sub/com.example.deep.plist", ["Label": "com.example.deep"])
        t.file("Library/LaunchDaemons/com.example.txt", bytes: 1)
        t.file("Library/LaunchDaemons/com.example.upper.PLIST", bytes: 1)
        let real = plist(t, "Library/elsewhere/com.example.link.plist", ["Label": "com.example.link"])
        _ = t.symlink("Library/LaunchDaemons/com.example.link.plist", to: real)
        let items = scanner(t).items(ctx)
        #expect(Set(items.map(\.name)) == [".hidden.plist", "com.example.agent.plist", "com.example.daemon.plist", "com.example.user.plist"])
        #expect(items.allSatisfy { $0.isBackground })
        let kinds = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.kind) })
        #expect(kinds["com.example.user.plist"] == .userAgent)
        #expect(kinds["com.example.agent.plist"] == .systemAgent)
        #expect(kinds["com.example.daemon.plist"] == .systemDaemon)
        #expect(items.first { $0.name == "com.example.daemon.plist" }?.label == "com.example.daemon")
    }

    @Test func ownerAppResolved() {
        let t = FixtureTree()
        let ctx = t.context()
        let logi = t.app("Applications/Logi Options+.app", bundleID: "com.logi.optionsplus")
        plist(t, "Library/LaunchAgents/com.logi.optionsplus.plist",
              ["Label": "com.logi.cp-dev-mgr", "ProgramArguments": [logi.path + "/Contents/Frameworks/x.app/Contents/MacOS/x", "-a"]])
        plist(t, "Library/LaunchDaemons/com.logi.optionsplus.updater.plist",
              ["Label": "com.logi.optionsplus.updater", "Program": logi.path + "/Contents/MacOS/app"])
        plist(t, "Library/LaunchDaemons/com.bjango.istatmenus.installer.plist",
              ["Label": "com.bjango.istatmenus.installer", "Program": "/Library/PrivilegedHelperTools/com.bjango.istatmenus.installer"])
        plist(t, "Library/LaunchDaemons/org.assoc.plist", ["Label": "org.assoc", "AssociatedBundleIdentifiers": ["com.logi.optionsplus"]])
        let items = scanner(t).items(ctx)
        // Ordem por nome; o dono é o primeiro ".app" do caminho (não o app aninhado).
        #expect(items.map(\.name) == ["com.bjango.istatmenus.installer.plist", "Logi Options+.app", "Logi Options+.app", "org.assoc.plist"])
        let owned = items.filter { $0.name == "Logi Options+.app" }
        #expect(owned.allSatisfy { $0.ownerApp?.path == logi.path && $0.ownerBundleID == "com.logi.optionsplus" })
        #expect(items.first { $0.name == "org.assoc.plist" }?.ownerApp == nil)
        #expect(items.first { $0.name.hasPrefix("com.bjango") }?.program?.path == "/Library/PrivilegedHelperTools/com.bjango.istatmenus.installer")
    }

    @Test func disabledStateFromLaunchctl() {
        let t = FixtureTree()
        let ctx = t.context()
        plist(t, "Users/tester/Library/LaunchAgents/com.example.user.plist", ["Label": "com.example.user"])
        plist(t, "Library/LaunchAgents/com.example.agent.plist", ["Label": "com.example.agent", "Disabled": true])
        plist(t, "Library/LaunchDaemons/com.example.daemon.plist", ["Label": "com.example.daemon"])
        plist(t, "Library/LaunchDaemons/com.example.on.plist", ["Label": "com.example.on", "Disabled": true])
        let cmds = HelperFakeCommands()
        cmds.responses["print-disabled"] = (0, "")
        let gui = "disabled services = {\n\t\t\"com.example.user\" => disabled\n\t\t\"com.gone\" => enabled\n}\n"
        let system = "\ndisabled services = {\n\t\t\"com.example.daemon\" => true\n\t\t\"com.example.on\" => enabled\n}\n"
        let s = StartupItemsScanner(loginItems: FakeLoginItems(entries: []), commands: ByDomainCommands(gui: gui, system: system),
                                    disabledRecord: DisabledLoginItemsStore(url: t.url("rec.json")), displayName: { $0.lastPathComponent })
        let state = Dictionary(uniqueKeysWithValues: s.items(ctx).map { ($0.label ?? "", $0.state) })
        #expect(state == ["com.example.user": .disabled, "com.example.agent": .disabled, "com.example.daemon": .disabled, "com.example.on": .enabled])
        #expect(StartupItemsScanner.parseDisabled(gui) == ["com.example.user": true, "com.gone": false])
    }

    @Test func disabledSessionItemsFromRecord() throws {
        let t = FixtureTree()
        let ctx = t.context()
        let hb = t.app("Applications/Hidden Bar.app", bundleID: "com.dwarvesv.minimalbar")
        let store = DisabledLoginItemsStore(url: t.url("rec.json"))
        try store.save([DisabledLoginItem(name: "Hidden Bar", path: hb.path, bundleIdentifier: "com.dwarvesv.minimalbar", disabledAt: Date())])
        let s = StartupItemsScanner(loginItems: FakeLoginItems(entries: []), commands: HelperFakeCommands(), disabledRecord: store,
                                    displayName: { $0.lastPathComponent })
        let items = s.items(ctx)
        #expect(items.map(\.name) == ["Hidden Bar.app"])
        #expect(items[0].state == .disabled && items[0].kind == .sessionLoginItem)
        // Se o app voltou para a lista sozinho, aparece uma vez só, ativo.
        let again = StartupItemsScanner(loginItems: FakeLoginItems(entries: [LoginItemEntry(name: "Hidden Bar", url: hb)]),
                                        commands: HelperFakeCommands(), disabledRecord: store, displayName: { $0.lastPathComponent })
        #expect(again.items(ctx).map(\.state) == [.enabled])
    }
}

/// `launchctl print-disabled` com uma saída por domínio.
struct ByDomainCommands: CommandRunner {
    let gui: String, system: String
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        guard arguments.first == "print-disabled" else { return (0, "") }
        return (0, arguments.last == "system" ? system : gui)
    }
}
