import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct ClutterRemovalTests {
    func file(_ t: FixtureTree, _ rel: String, _ bytes: Int = 1000) -> ClutterFile {
        t.file(rel, bytes: bytes)
        let u = t.url(rel)
        let v = try! u.resourceValues(forKeys: [.contentModificationDateKey])
        return ClutterFile(url: u, size: Int64(bytes), modified: v.contentModificationDate)
    }

    @Test func trashesAndRevalidates() async throws {
        let t = FixtureTree()
        let go = file(t, "Users/me/Documents/a.png")
        let grown = file(t, "Users/me/Documents/b.png")
        let link = file(t, "Users/me/Documents/c.png")
        let gone = file(t, "Users/me/Documents/d.png")
        // Mudaram depois da análise: outro tamanho, virou link, sumiu.
        try Data(repeating: 1, count: 2000).write(to: grown.url)
        try FileManager.default.removeItem(at: link.url)
        _ = t.symlink("Users/me/Documents/c.png", to: go.url)
        try FileManager.default.removeItem(at: gone.url)
        let trasher = FixtureTrasher(t.url("trash"))
        let remover = ClutterRemover(trasher: trasher, home: t.url("Users/me"), dryRun: false, log: CleanupLog(directory: t.url("logs")))
        let r = await remover.remove([go, grown, link, gone])
        #expect((try? r[go.url.path]?.get()) != nil)
        for f in [grown, link, gone] {
            if case .failure(let e) = r[f.url.path] { #expect(e.reason == "item changed") } else { Issue.record("deveria recusar \(f.url.lastPathComponent)") }
        }
        #expect(trasher.trashed.map(\.lastPathComponent) == ["a.png"])
        let logs = try FileManager.default.contentsOfDirectory(atPath: t.url("logs").path)
        #expect(logs.count == 1 && logs[0].hasPrefix("clutter-"))
    }

    @Test func sameSizeEditIsRefused() async throws {
        let t = FixtureTree()
        let f = file(t, "Users/me/Documents/a.bin")
        try Data(repeating: 7, count: 1000).write(to: f.url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_900_000_000)], ofItemAtPath: f.url.path)
        let trasher = FixtureTrasher(t.url("trash"))
        let r = await ClutterRemover(trasher: trasher, home: t.url("Users/me"), dryRun: false, log: CleanupLog(directory: t.url("logs")))
            .remove([f])
        if case .failure(let e) = r[f.url.path] { #expect(e.reason == "item changed") } else { Issue.record("deveria recusar") }
    }

    /// A cópia que fica sumiu ou mudou depois da análise: as marcadas do grupo não saem (seria a última cópia).
    @Test func keeperMustStillExist() async throws {
        let t = FixtureTree()
        let go = file(t, "Users/me/Downloads/a.png"), keep = file(t, "Users/me/Documents/a.png")
        let other = file(t, "Users/me/Movies/b.mov"), otherKeep = file(t, "Users/me/Pictures/b.mov")
        try FileManager.default.removeItem(at: keep.url)
        let trasher = FixtureTrasher(t.url("trash"))
        let r = await ClutterRemover(trasher: trasher, home: t.url("Users/me"), dryRun: false, log: CleanupLog(directory: t.url("logs")))
            .remove([go, other], keeping: [[go, keep], [other, otherKeep]])
        if case .failure(let e) = r[go.url.path] { #expect(e.reason == "item changed") } else { Issue.record("deveria recusar") }
        #expect((try? r[other.url.path]?.get()) != nil)
        #expect(trasher.trashed.map(\.lastPathComponent) == ["b.mov"])
    }

    @Test func dryRunTouchesNothing() async throws {
        let t = FixtureTree()
        let f = file(t, "Users/me/Downloads/x.zip")
        let trasher = FixtureTrasher(t.url("trash"))
        let r = await ClutterRemover(trasher: trasher, home: t.url("Users/me"), dryRun: true, log: CleanupLog(directory: t.url("logs")))
            .remove([f])
        #expect((try? r[f.url.path]?.get()) != nil)
        #expect(trasher.trashed.isEmpty && FileManager.default.fileExists(atPath: f.url.path))
    }

    @Test func protectedPathsRefused() async throws {
        let t = FixtureTree()
        let lib = file(t, "Users/me/Library/Keychains/k.db")
        let trasher = FixtureTrasher(t.url("trash"))
        let r = await ClutterRemover(trasher: trasher, home: t.url("Users/me"), dryRun: false, log: CleanupLog(directory: t.url("logs")))
            .remove([lib])
        if case .failure(let e) = r[lib.url.path] { #expect(e.reason == "kept: protected") } else { Issue.record("deveria recusar") }
        #expect(trasher.trashed.isEmpty)
    }

    // MARK: - Seleção por grupo

    func dupGroup() -> DuplicateGroup {
        let old = Date(timeIntervalSince1970: 1_600_000_000), new = Date(timeIntervalSince1970: 1_700_000_000)
        return DuplicateGroup(files: [ClutterFile(url: URL(fileURLWithPath: "/u/Downloads/a.png"), size: 10, modified: old, created: old),
                                      ClutterFile(url: URL(fileURLWithPath: "/u/Documents/a.png"), size: 10, modified: new, created: new)],
                              hash: "h")
    }

    @Test func pickOptionsKeepOne() {
        let g = dupGroup()
        let ids = g.files.map(\.url.path)
        #expect(ClutterPick.none.select(g.files.map(ClutterPick.Item.init)) == [])
        #expect(ClutterPick.all.select(g.files.map(ClutterPick.Item.init)) == Set(ids))
        #expect(ClutterPick.keepNewest.select(g.files.map(ClutterPick.Item.init)) == [ids[0]])
        #expect(ClutterPick.keepOldest.select(g.files.map(ClutterPick.Item.init)) == [ids[1]])
    }

    @Test func fullySelectedGroupsAreReported() {
        let g = dupGroup()
        let report = ClutterReport(home: URL(fileURLWithPath: "/u"), largeOld: [], duplicates: [g], similar: [], downloads: [], tiles: [])
        #expect(report.fullySelectedGroups(in: [g.files[0].url.path]).isEmpty)
        #expect(report.fullySelectedGroups(in: Set(g.files.map(\.url.path))) == [g.id])
    }
}

@Suite struct ClutterReportRemovingTests {
    @Test func removedItemsLeaveGroupsAndTilesUpdate() {
        let home = URL(fileURLWithPath: "/u")
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        func f(_ rel: String, _ size: Int64) -> ClutterFile {
            ClutterFile(url: home.appendingPathComponent(rel), size: size, created: now.addingTimeInterval(-400 * 86_400),
                        accessed: now.addingTimeInterval(-400 * 86_400))
        }
        let big = f("Movies/big.mov", 60_000_000)
        let d1 = f("Documents/a.png", 200_000), d2 = f("Documents/b/a.png", 200_000), d3 = f("Pictures/a.png", 200_000)
        let e1 = f("Documents/x.zip", 300_000), e2 = f("Desktop2/x.zip", 300_000)
        let dl = DownloadsFinder.Group(app: .chrome, files: [DownloadsFinder.Item(file: f("Downloads/z.dmg", 9_000), downloaded: nil)],
                                       autoselected: [])
        let dups = [DuplicateGroup(files: [d1, d2, d3], hash: "1"), DuplicateGroup(files: [e1, e2], hash: "2")]
        let report = ClutterReport(home: home, largeOld: [big], duplicates: dups, similar: [], downloads: [dl],
                                   tiles: ClutterTiles.make(home: home, now: now, largeOld: [big], duplicates: dups, similar: [], downloads: [dl]))
        let after = report.removing([big.url.path, d1.url.path, e1.url.path, "/u/Downloads/z.dmg"], now: now)
        #expect(after.largeOld.isEmpty && after.downloads.isEmpty)
        #expect(after.duplicates.map(\.id) == ["1"])
        #expect(after.duplicates[0].files.map(\.url.lastPathComponent) == ["a.png", "a.png"])
        #expect(after.total == 2)
        #expect(after.tiles.map(\.kind) == [.duplicatesDocuments])
    }

    @Test func totalCountsEachFileOnce() {
        let home = URL(fileURLWithPath: "/u")
        let big = ClutterFile(url: home.appendingPathComponent("Downloads/big.zip"), size: 60_000_000)
        let copy = ClutterFile(url: home.appendingPathComponent("Documents/big.zip"), size: 60_000_000)
        let dl = DownloadsFinder.Group(app: .chrome, files: [DownloadsFinder.Item(file: big, downloaded: nil)], autoselected: [])
        let r = ClutterReport(home: home, largeOld: [big, copy], duplicates: [DuplicateGroup(files: [big, copy], hash: "h")], similar: [],
                              downloads: [dl], tiles: [])
        #expect(r.total == 2)
    }
}
