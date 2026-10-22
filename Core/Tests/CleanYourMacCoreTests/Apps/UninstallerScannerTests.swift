import Foundation
import Testing
@testable import CleanYourMacCore

private struct Env {
    let t = FixtureTree()
    let ctx: ScanContext

    init() { ctx = t.context() }

    func scanner(usage: FakeUsage = FakeUsage(), query: [URL] = [], privileged: Bool = false) -> UninstallerScanner {
        UninstallerScanner(catalog: AppCatalog(query: FakeAppQuery(results: query), usage: usage, displayName: { $0.lastPathComponent }),
                           finder: RelatedFilesFinder(loginItems: FakeLoginItems(entries: []), receipts: FakeReceipts(),
                                                      privilegedAvailable: privileged))
    }

    func scan(_ s: UninstallerScanner? = nil) async throws -> [JunkItem] {
        try await (s ?? scanner()).scan(ctx) { _ in }
    }
}

private func kinds(_ item: JunkItem) -> [String] { item.children.compactMap(\.detail) }
private func leaf(_ item: JunkItem, _ name: String) -> JunkItem? { item.leaves.first { $0.url?.lastPathComponent == name } }

@Suite struct UninstallerScannerTests {
    @Test func oneItemPerAppWithKindsAndTotal() async throws {
        let e = Env()
        let app = AppFixture.makeApp(e.t, "Applications/Foo.app", bundleID: "com.foo.App")
        e.t.file("Users/tester/Library/Preferences/com.foo.App.plist", bytes: 4096)
        e.t.file("Users/tester/Library/Caches/com.foo.App/c", bytes: 8192)
        let items = try await e.scan()
        let foo = try #require(items.first { $0.name == "Foo.app" })
        #expect(foo.id == "appUninstall:com.foo.App|\(PathPolicy.realPath(app.path))")
        #expect(foo.group == .appUninstall)
        #expect(kinds(foo).first == "binaries")
        #expect(Set(kinds(foo)) == ["binaries", "preferences", "supportingFiles"])
        let bundle = try #require(foo.children.first?.children.first)
        #expect(AppItemID.isBundle(bundle.id))
        #expect(bundle.removal == .trashAppBundle(URL(fileURLWithPath: PathPolicy.realPath(app.path))))
        #expect(bundle.isRecommended)
        #expect(foo.totalSize == foo.leaves.reduce(0) { $0 + $1.size })
        #expect(foo.leaves.allSatisfy { AppItemID.owner(of: $0.id) == "com.foo.App" })
    }

    @Test func copiesUnselected() async throws {
        let e = Env()
        AppFixture.makeApp(e.t, "Applications/G.app", bundleID: "com.g")
        let build = AppFixture.makeApp(e.t, "Users/tester/Projetos/build/G.app", bundleID: "com.g")
        let item = try #require(try await e.scan(e.scanner(query: [build])).first)
        let binaries = try #require(item.children.first)
        #expect(binaries.children.count == 2)
        #expect(binaries.children.map(\.isRecommended) == [true, false])
        #expect(!AppItemID.isBundle(binaries.children[1].id))
    }

    @Test func protectedAppHasLockedBundle() async throws {
        let e = Env()
        AppFixture.makeApp(e.t, "Applications/Safari.app", bundleID: "com.apple.Safari")
        let item = try #require(try await e.scan().first)
        let bundle = try #require(item.children.first?.children.first)
        #expect(bundle.removal == nil)
        #expect(bundle.badge == .locked)
    }

    @Test func selfCannotBeUninstalledNorReset() async throws {
        let e = Env()
        AppFixture.makeApp(e.t, "Applications/CleanYourMac.app", bundleID: "io.github.guigx7.CleanYourMac")
        e.t.file("Users/tester/Library/Preferences/io.github.guigx7.CleanYourMac.plist", bytes: 10)
        let item = try #require(try await e.scan().first)
        #expect(item.children.first?.children.first?.badge == .locked)
        #expect(UninstallerScanner.resetItem(from: item, context: e.ctx) == nil)
    }

    @Test func resetMarksStateNotUserData() async throws {
        let e = Env()
        AppFixture.makeApp(e.t, "Applications/Foo.app", bundleID: "com.foo.App")
        e.t.file("Users/tester/Library/Preferences/com.foo.App.plist", bytes: 10)
        e.t.file("Users/tester/Library/Caches/com.foo.App/c", bytes: 10)
        e.t.file("Users/tester/Library/Logs/Foo/l", bytes: 10)
        e.t.file("Users/tester/Library/Containers/com.foo.App/Data/x", bytes: 10)
        e.t.dir("Library/Application Support/Foo")
        e.t.file("Users/tester/Downloads/Foo.dmg", bytes: 10)
        let item = try #require(try await e.scan(e.scanner(privileged: true)).first)
        let reset = try #require(UninstallerScanner.resetItem(from: item, context: e.ctx))
        #expect(reset.id.hasPrefix("appReset:"))
        #expect(!reset.leaves.contains { AppItemID.isBundle($0.id) && $0.removal != nil })
        #expect(!kinds(reset).contains("installers"))
        #expect(leaf(reset, "com.foo.App.plist")?.isRecommended == true)
        #expect(leaf(reset, "com.foo.App")?.isRecommended == true || reset.leaves.contains { $0.url?.path.contains("Caches/com.foo.App") == true && $0.isRecommended })
        #expect(leaf(reset, "Foo")?.isRecommended == true || reset.leaves.first { $0.url?.path.hasSuffix("Logs/Foo") == true }?.isRecommended == true)
        #expect(reset.leaves.first { $0.detail == "container" }?.isRecommended == false)
        #expect(reset.leaves.first { $0.url?.path.hasSuffix("/Library/Application Support/Foo") == true }?.isRecommended == false)
        #expect(reset.leaves.allSatisfy { AppItemID.mode(of: $0.id) == .reset })
    }

    @Test func resetAppleAppLocksItemsOutsideHome() async throws {
        let e = Env()
        AppFixture.makeApp(e.t, "Applications/GarageBand.app", bundleID: "com.apple.garageband10")
        e.t.dir("Library/Application Support/GarageBand")
        let item = try #require(try await e.scan(e.scanner(privileged: true)).first)
        let reset = try #require(UninstallerScanner.resetItem(from: item, context: e.ctx))
        let lib = try #require(reset.leaves.first { $0.url?.path.hasSuffix("Application Support/GarageBand") == true })
        #expect(lib.removal == nil)
        #expect(lib.badge == .locked)
    }

    @Test func resetNeedsExtraConfirmation() {
        let c = JunkItem(group: .appUninstall, name: "c", detail: "container", url: URL(fileURLWithPath: "/c"), size: 1)
        let p = JunkItem(group: .appUninstall, name: "p", detail: "preferences", url: URL(fileURLWithPath: "/p"), size: 1)
        let u = JunkItem(group: .appUninstall, name: "u", detail: "userData", url: URL(fileURLWithPath: "/u"), size: 1)
        #expect(UninstallerScanner.needsResetConfirmation([p, c]))
        #expect(UninstallerScanner.needsResetConfirmation([u]))
        #expect(!UninstallerScanner.needsResetConfirmation([p]))
    }

    @Test func policyAcceptsOnlyScopedPaths() {
        let e = Env()
        let policy = PathPolicy(allowedRoots: e.scanner().removalScope(e.ctx).roots)
        #expect(throws: PathPolicyError.self) { try policy.validate(e.t.url("Users/tester/Documents/x")) }
        #expect((try? policy.validate(e.t.url("Users/tester/Library/Preferences/x.plist"))) != nil)
        #expect((try? policy.validate(e.t.url("Applications/Foo.app"))) != nil)
    }

    @Test func trashAppBundleOnlyAcceptsRealBundles() async {
        let e = Env()
        let app = AppFixture.makeApp(e.t, "Users/tester/Projetos/build/G.app", bundleID: "com.g")
        let fake = e.t.dir("Users/tester/Documents/Notes.app")
        let trasher = FixtureTrasher(e.t.url("Users/tester/.Trash"))
        let engine = CleanEngine(policies: [.appUninstall: PathPolicy(allowedRoots: [])], privileged: RecordingPrivileged(), dryRun: false,
                                 log: CleanupLog(directory: e.t.url("logs")), runningApps: FakeRunningApps(), trasher: trasher)
        let items = [app, fake].map { u in
            JunkItem(id: AppItemID.leaf(mode: .uninstall, appID: "com.g|\(u.path)", path: u.path), group: .appUninstall,
                     name: u.lastPathComponent, url: u, size: 0, removal: .trashAppBundle(u))
        }
        var report: CleanReport?
        for await ev in engine.clean(items) { if case .completed(let r) = ev { report = r } }
        #expect(report?.removed == [items[0].id])
        #expect(FileManager.default.fileExists(atPath: fake.path))
    }
}
