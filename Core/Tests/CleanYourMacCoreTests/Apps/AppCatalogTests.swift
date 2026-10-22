import Foundation
import Testing
@testable import CleanYourMacCore

struct FakeAppQuery: AppQuery {
    var results: [URL] = []
    func applications(in scopes: [URL]) -> [URL] {
        results.filter { r in scopes.contains { r.path.hasPrefix($0.path + "/") } }
    }
}

struct FakeUsage: UsageDates {
    var used: [String: Date] = [:]
    var modified: [String: Date] = [:]
    func dates(_ app: URL) -> (lastUsed: Date?, contentModified: Date?) {
        (used[app.lastPathComponent], modified[app.lastPathComponent])
    }
}

enum AppFixture {
    /// App de teste: Info.plist com os campos pedidos e um executável (Mach-O mínimo com as arquiteturas pedidas).
    @discardableResult
    static func makeApp(_ t: FixtureTree, _ rel: String, bundleID: String, version: String? = "1.0", build: String? = nil,
                        masReceipt: Bool = false, feed: String? = nil, cpuTypes: [UInt32] = [0x0100_000C],
                        extra: [String: Any] = [:]) -> URL {
        let u = t.dir(rel)
        t.dir("\(rel)/Contents/MacOS")
        var info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "app",
                                   "CFBundleName": (u.lastPathComponent as NSString).deletingPathExtension]
        if let version { info["CFBundleShortVersionString"] = version }
        if let build { info["CFBundleVersion"] = build }
        if let feed { info["SUFeedURL"] = feed }
        info.merge(extra) { $1 }
        try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: u.appendingPathComponent("Contents/Info.plist"))
        try! machO(cpuTypes).write(to: u.appendingPathComponent("Contents/MacOS/app"))
        if masReceipt { t.file("\(rel)/Contents/_MASReceipt/receipt", bytes: 10) }
        return u
    }

    /// Cabeçalho Mach-O: fino (uma arquitetura) ou universal.
    static func machO(_ cpus: [UInt32]) -> Data {
        func le(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
        func be(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.bigEndian, Array.init) }
        if cpus.count == 1 {
            let is64 = cpus[0] & 0x0100_0000 != 0
            return Data(le(is64 ? 0xFEED_FACF : 0xFEED_FACE) + le(cpus[0]) + le(0) + [UInt8](repeating: 0, count: 64))
        }
        var bytes = be(0xCAFE_BABE) + be(UInt32(cpus.count))
        for (i, c) in cpus.enumerated() { bytes += be(c) + be(0) + be(UInt32(4096 * (i + 1))) + be(16) + be(12) }
        return Data(bytes + [UInt8](repeating: 0, count: 4096 * (cpus.count + 1)))
    }
}

private func catalog(_ t: FixtureTree, query: [URL] = [], usage: FakeUsage = FakeUsage()) -> AppCatalog {
    AppCatalog(query: FakeAppQuery(results: query), usage: usage, displayName: { $0.lastPathComponent })
}

@Suite struct AppCatalogTests {
    @Test func listsAppsFromSpecFoldersSkippingNestedAndLinks() {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/A.app", bundleID: "com.a")
        AppFixture.makeApp(t, "Applications/Sub/B.app", bundleID: "com.b")
        AppFixture.makeApp(t, "Applications/A.app/Contents/Library/LoginItems/H.app", bundleID: "com.a.helper")
        let real = AppFixture.makeApp(t, "elsewhere/X.app", bundleID: "com.x")
        t.symlink("Applications/X.app", to: real)
        t.dir("Applications/Casca.app/Contents")
        let names = catalog(t).apps(t.context()).map(\.name)
        #expect(names.sorted() == ["A.app", "B.app"])
    }

    @Test func spotlightResultsFilteredByPathRules() {
        let t = FixtureTree()
        let ctx = t.context()
        let downloads = AppFixture.makeApp(t, "Users/tester/Downloads/Foo.app", bundleID: "com.foo")
        let lib = AppFixture.makeApp(t, "Users/tester/Library/Application Support/Bar/Bar.app", bundleID: "com.bar")
        let pwa = AppFixture.makeApp(t, "Users/tester/Applications/Chrome Apps.localized/GitHub.app", bundleID: "com.google.Chrome.app.abc")
        let dotted = AppFixture.makeApp(t, "Users/tester/Projetos/X.bundle/Y.app", bundleID: "com.y")
        let versioned = AppFixture.makeApp(t, "Users/tester/Projetos/App 2.0/Z.app", bundleID: "com.z")
        let trash = AppFixture.makeApp(t, "Users/tester/.Trash/W.app", bundleID: "com.w")
        let names = catalog(t, query: [downloads, lib, pwa, dotted, versioned, trash]).apps(ctx).map(\.name)
        #expect(names.sorted() == ["Foo.app", "Z.app"])
    }

    @Test func duplicateBundleIDsBecomeOneRowWithCopies() {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/G.app", bundleID: "com.g")
        let build = AppFixture.makeApp(t, "Users/tester/Projetos/build/G.app", bundleID: "com.G")
        let apps = catalog(t, query: [build]).apps(t.context())
        #expect(apps.count == 1)
        #expect(apps.first?.url.path.hasSuffix("Applications/G.app") == true)
        #expect(apps.first?.copies.map(\.lastPathComponent) == ["G.app"])
    }

    @Test func storeFromSuffixAndReceipt() {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/S.app", bundleID: "com.foo.bar-setapp", masReceipt: true)
        AppFixture.makeApp(t, "Applications/M.app", bundleID: "com.m", masReceipt: true)
        AppFixture.makeApp(t, "Applications/O.app", bundleID: "com.setapp.DesktopClient")
        let byName = Dictionary(uniqueKeysWithValues: catalog(t).apps(t.context()).map { ($0.name, $0.store) })
        #expect(byName == ["S.app": .setapp, "M.app": .appStore, "O.app": .other])
    }

    @Test func steamGamesFromLibraryFolders() {
        let t = FixtureTree()
        let lib = t.url("Games/SteamLib")
        let vdf = t.file("Users/tester/Library/Application Support/Steam/steamapps/libraryfolders.vdf", bytes: 0)
        try! Data("\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"\(lib.path)\"\n\t}\n}\n".utf8).write(to: vdf)
        let game = AppFixture.makeApp(t, "Games/SteamLib/steamapps/common/Game/Game.app", bundleID: "com.game")
        let apps = catalog(t, query: [game]).apps(t.context())
        #expect(AppCatalog.isSteam(game, context: t.context()))
        #expect(apps.isEmpty || apps.allSatisfy { $0.store == .steam })
    }

    @Test func vendorRules() {
        let cases: [(String, AppVendor)] = [
            ("com.apple.dt.Xcode", .apple), ("com.applesauce.x", .other), ("com.macpaw-labs.x", .macPaw),
            ("com.microsoftx.y", .other), ("com.microsoft.VSCode", .microsoft), ("com.google.Chrome", .google),
            ("com.setapp.DesktopClient", .macPaw), ("org.jetbrains.intellij", .jetBrains), ("com.adobe.Photoshop", .adobe),
            ("developer.apple.wwdc", .apple), ("com.skype.skype", .microsoft), ("net.whatsapp.WhatsApp", .other),
        ]
        for (id, vendor) in cases { #expect(AppCatalog.vendor(for: id) == vendor, "\(id)") }
    }

    @Test func lastOpenedFallsBackToModificationDate() {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/A.app", bundleID: "com.a")
        AppFixture.makeApp(t, "Applications/B.app", bundleID: "com.b")
        let used = Date(timeIntervalSince1970: 1_800_000_000), mod = Date(timeIntervalSince1970: 1_700_000_000)
        let apps = catalog(t, usage: FakeUsage(used: ["A.app": used], modified: ["A.app": mod, "B.app": mod])).apps(t.context())
        #expect(apps.first { $0.name == "A.app" }?.lastOpened == used)
        #expect(apps.first { $0.name == "B.app" }?.lastOpened == mod)
    }

    @Test func unusedAfterSixCalendarMonths() {
        let now = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
        let cal = Calendar.current
        func app(_ d: Date?) -> AppRecord { AppRecord(url: URL(fileURLWithPath: "/Applications/A.app"), bundleID: "com.a", name: "A.app", lastOpened: d) }
        #expect(app(cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .month, value: -6, to: now)!)).isUnused(now: now))
        #expect(!app(cal.date(byAdding: .day, value: 1, to: cal.date(byAdding: .month, value: -6, to: now)!)).isUnused(now: now))
        #expect(!app(nil).isUnused(now: now))
        let me = AppRecord(url: URL(fileURLWithPath: "/Applications/C.app"), bundleID: "io.github.guigx7.CleanYourMac", name: "C.app",
                           lastOpened: .distantPast, isSelf: true)
        #expect(!me.isUnused(now: now))
    }

    @Test func detects32Bit() {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/Old.app", bundleID: "com.old", cpuTypes: [7])
        AppFixture.makeApp(t, "Applications/Mixed.app", bundleID: "com.mixed", cpuTypes: [7, 0x0100_0007])
        AppFixture.makeApp(t, "Applications/New.app", bundleID: "com.new")
        let byName = Dictionary(uniqueKeysWithValues: catalog(t).apps(t.context()).map { ($0.name, $0.is32Bit) })
        #expect(byName == ["Old.app": true, "Mixed.app": false, "New.app": false])
    }

    @Test func audioPluginsListedAppleProtected() {
        let t = FixtureTree()
        let ctx = t.context()
        let hal = t.dir("Library/Audio/Plug-Ins/HAL/X.driver/Contents")
        try! PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.apple.audio.X"], format: .xml, options: 0)
            .write(to: hal.appendingPathComponent("Info.plist"))
        t.dir("Users/tester/Library/Audio/Plug-Ins/VST3/Y.vst3")
        t.dir("Library/Audio/Plug-Ins/Presets")
        let plugins = catalog(t).apps(ctx).filter { $0.kind == .audioPlugin }
        #expect(plugins.map(\.name).sorted() == ["X.driver", "Y.vst3"])
        #expect(plugins.first { $0.name == "X.driver" }?.isProtected == true)
        #expect(plugins.first { $0.name == "Y.vst3" }?.isProtected == false)
    }

    @Test func marksSelfAndReadsMetadata() throws {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/CleanYourMac.app", bundleID: "io.github.guigx7.CleanYourMac", version: "0.2.0",
                           build: "3", feed: "https://example.com/a.xml")
        let app = try #require(catalog(t).apps(t.context()).first)
        #expect(app.isSelf)
        #expect(app.version == "0.2.0")
        #expect(app.build == "3")
        #expect(app.feedURL == URL(string: "https://example.com/a.xml"))
        #expect(app.matchName == "CleanYourMac")
        #expect(app.bundleSize > 0)
    }
}
