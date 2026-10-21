import Foundation
import Testing
@testable import CleanYourMacCore

/// O Spotlight não indexa pastas temporárias: a consulta é trocada por uma lista fixa.
struct FakeDiskImageQuery: DiskImageQuery {
    var results: [URL]
    func diskImages(in scopes: [URL]) -> [URL] {
        results.filter { r in scopes.contains { r.path.hasPrefix($0.path + "/") } }
    }
}

private func scanner(_ t: FixtureTree, _ found: [URL], mounted: Set<String> = []) -> InstallersScanner {
    InstallersScanner(query: FakeDiskImageQuery(results: found), mountedImages: { mounted })
}

@Suite struct InstallersTests {
    @Test func installerFoundUnselectedWithFileName() async throws {
        let t = FixtureTree()
        let ctx = t.context()
        let a = t.file("Users/tester/Downloads/a.dmg", bytes: 50_000)
        let b = t.file("Users/tester/Library/Application Support/X/b.dmg", bytes: 10)
        let c = t.file("Applications/c.dmg", bytes: 10)
        let items = try await scanner(t, [a, b, c]).scan(ctx) { _ in }
        #expect(items.map(\.name).sorted() == ["a.dmg", "b.dmg", "c.dmg"])
        #expect(items.allSatisfy { !$0.isRecommended && $0.group == .appInstallers })
        let first = try #require(items.first { $0.name == "a.dmg" })
        #expect(first.size == FixtureTree.allocated(a))
        #expect(first.removal == .deleteDiskImage(a))
    }

    @Test func installerExclusionsOutsideScopesAndDropbox() async throws {
        let t = FixtureTree()
        let ctx = t.context()
        let shared = t.file("Users/Shared/d.dmg", bytes: 10)
        let lib = t.file("Library/e.dmg", bytes: 10)
        let box = t.file("Users/tester/Dropbox/f.dmg", bytes: 10)
        let info = t.file("Users/tester/.dropbox/info.json", bytes: 0)
        try Data(#"{"personal":{"path":"\#(t.url("Users/tester/Dropbox").path)"}}"#.utf8).write(to: info)
        let items = try await scanner(t, [shared, lib, box]).scan(ctx) { _ in }
        #expect(items.isEmpty)
    }

    @Test func mountedImageListedButBadged() async throws {
        let t = FixtureTree()
        let a = t.file("Users/tester/Downloads/a.dmg", bytes: 10)
        let items = try await scanner(t, [a], mounted: [PathPolicy.realPath(a.path)]).scan(t.context()) { _ in }
        #expect(items.first?.badge == .mounted)
    }

    @Test func noSpotlightIndexMeansEmpty() async throws {
        let t = FixtureTree()
        #expect(try await scanner(t, []).scan(t.context()) { _ in }.isEmpty)
    }

    @Test func installersDeleteImmediatelyOnlyRegularDmg() async throws {
        let t = FixtureTree()
        let ctx = t.context()
        let a = t.file("Users/tester/Downloads/a.dmg", bytes: 10)
        let target = t.file("elsewhere/target.dmg", bytes: 10)
        let link = t.symlink("Users/tester/Downloads/j.dmg", to: target)
        let notDmg = t.file("Users/tester/Downloads/k.pkg", bytes: 10)
        let s = scanner(t, [a])
        let policies = [GroupID.appInstallers: PathPolicy(allowedRoots: s.removalScope(ctx).roots)]
        let engine = CleanEngine(policies: policies, privileged: AppleScriptPrivilegedRunner(), dryRun: false,
                                 log: CleanupLog(directory: t.url("logs")))
        let items = [a, link, notDmg].map {
            JunkItem(group: .appInstallers, name: $0.lastPathComponent, url: $0, size: 10, removal: .deleteDiskImage($0))
        }
        var report: CleanReport?
        for await e in engine.clean(items) { if case .completed(let r) = e { report = r } }
        #expect(report?.removed == [items[0].id])
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(FileManager.default.fileExists(atPath: notDmg.path))
        #expect(!FileManager.default.fileExists(atPath: t.url("Users/tester/.Trash/a.dmg").path))
    }
}
