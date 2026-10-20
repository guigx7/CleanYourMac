import Testing
import Foundation
@testable import CleanYourMacCore

private func scan(_ s: any GroupScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}

private func plist(_ t: FixtureTree, _ rel: String, _ dict: [String: Any]) {
    t.dir((rel as NSString).deletingLastPathComponent)
    try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: t.url(rel))
}

private func launchd(_ entries: [LoginItemEntry] = []) -> BrokenLoginItemsScanner {
    BrokenLoginItemsScanner(loginItems: FakeLoginItems(entries: entries), inventory: FolderAppInventory())
}

// C1: agentes que funcionam não podem virar "quebrados".
@Test func fix_launchdBareCommandIsNotBroken() async throws {
    let t = FixtureTree(); let ctx = t.context()
    plist(t, "Users/tester/Library/LaunchAgents/com.me.backup.plist", ["ProgramArguments": ["sh", "-c", "echo"]])
    plist(t, "Users/tester/Library/LaunchAgents/com.me.unknown.plist", ["ProgramArguments": ["some-tool-not-on-path"]])
    #expect(try await scan(launchd(), ctx).isEmpty)
}

@Test func fix_launchdOnUnmountedVolumeIsNotBroken() async throws {
    let t = FixtureTree(); let ctx = t.context()
    plist(t, "Users/tester/Library/LaunchAgents/com.me.ext.plist", ["Program": "/Volumes/NoSuchDisk-\(UUID())/tool"])
    #expect(try await scan(launchd(), ctx).isEmpty)
}

@Test func fix_unresolvedLoginItemNotRecommended() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let items = try await scan(launchd([LoginItemEntry(name: "Maybe", url: nil)]), ctx)
    #expect(items.map(\.name) == ["Maybe"])
    #expect(items[0].isRecommended == false)
}

// I1: o script root não pode ficar num arquivo gravável pelo usuário.
@Test func fix_privilegedScriptIsInlineAppleScript() {
    let source = AppleScriptPrivilegedRunner.appleScriptSource(for: "echo 'a \"b\"' \\\\ x\n")
    #expect(source.hasPrefix("do shell script \""))
    #expect(source.contains(#"echo 'a \"b\"' \\\\ x"#))
    #expect(source.hasSuffix("with administrator privileges"))
    #expect(!source.contains("quoted form of"))
}

// I2: binários/idiomas sem permissão de escrita falham, não vão para o lote root sem salvaguarda.
@Test func fix_unwritableThinNotEscalated() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = t.app("Applications/App.app", bundleID: "com.ro")
    let exe = app.appendingPathComponent("Contents/MacOS/app")
    try FileManager.default.copyItem(at: MachOFixtures.binary(["arm64", "x86_64"]), to: exe)
    let s = UniversalBinariesScanner(inventory: FolderAppInventory(folders: ["/Applications"]), hostArch: "arm64")
    let items = try await scan(s, ctx)
    chmod(exe.deletingLastPathComponent().path, 0o555)
    defer { chmod(exe.deletingLastPathComponent().path, 0o755) }
    let runner = FakePrivilegedRunner()
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: runner, dryRun: false,
                             log: CleanupLog(directory: t.dir("logs")))
    var report: CleanReport?
    for await e in engine.clean(items) { if case .completed(let r) = e { report = r } }
    #expect(runner.calls.isEmpty)
    #expect(report?.failed.count == 1)
}

// I3: esvaziar uma pasta que é symlink não pode apagar o destino.
@Test func fix_deleteContentsRefusesSymlink() async throws {
    let t = FixtureTree()
    let docs = t.file("Documents/precious.txt", bytes: 10)
    t.dir("R")
    let link = t.symlink("R/x", to: t.url("Documents"))
    let item = JunkItem(group: .trash, name: "x", url: link, size: 1, removal: .deleteContents(of: link))
    var policies: [GroupID: PathPolicy] = [:]
    policies[.trash] = PathPolicy(allowedRoots: [t.url("R")])
    let engine = CleanEngine(policies: policies, privileged: FakePrivilegedRunner(), dryRun: false,
                             log: CleanupLog(directory: t.dir("logs")))
    for await _ in engine.clean([item]) {}
    #expect(FileManager.default.fileExists(atPath: docs.path))
}

// I4: sem a lista de exclusões, os grupos de cache ficam vazios (falha fechada).
@Test func fix_exclusionsFailClosed() {
    let t = FixtureTree(); let ctx = t.context()
    #expect(Exclusions.failClosed.excludes(t.url("Users/tester/Library/Caches/Google"), group: .userCache, context: ctx))
    #expect(Exclusions.bundled.isLoaded)
    #expect(Exclusions.bundled.excludes(ctx.resolve("~/Library/Caches/ms-playwright"), group: .userCache, context: ctx))
}

// I5: caminhos vindos de arquivos graváveis ficam contidos; locais vitais nunca são removíveis.
@Test func fix_appStorePurgeablesContained() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let outside = t.file("Users/tester/Documents/important.pages", bytes: 10)
    let inside = t.file("var/folders/zz/C/com.apple.appstore/123/pkg", bytes: 10)
    t.dir("var/folders/zz/C/com.apple.appstore")
    try PropertyListSerialization.data(fromPropertyList: ["purgeables": [outside.path, inside.path]], format: .xml, options: 0)
        .write(to: t.url("var/folders/zz/C/com.apple.appstore/manifest.plist"))
    let s = CacheScanner.userCache(apps: FakeApps(), inventory: FolderAppInventory())
    let paths = try await scan(s, ctx).flatMap(\.leaves).compactMap { $0.url?.path }
    #expect(!paths.contains(outside.path))
    #expect(!Registry.policies(for: [s], context: ctx)[.userCache]!.allowedItems.map(\.path).contains(outside.path))
}

@Test func fix_policyRefusesVitalLocations() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let p = PathPolicy(allowedRoots: [URL(fileURLWithPath: "/")], allowedItems: [home, URL(fileURLWithPath: "/Applications")])
    #expect((try? p.validate(home)) == nil)
    #expect((try? p.validate(URL(fileURLWithPath: "/Applications"))) == nil)
    #expect((try? p.validate(home.appendingPathComponent("Documents"))) == nil)
    #expect((try? p.validate(URL(fileURLWithPath: "/Library"))) == nil)
}
