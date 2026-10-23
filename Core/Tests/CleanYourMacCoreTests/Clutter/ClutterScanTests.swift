import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct ClutterScanTests {
    func run(_ scan: ClutterScan, _ target: ClutterTarget) async throws -> ClutterReport? {
        var report: ClutterReport?
        for try await e in scan.run(target) { if case .finished(let r) = e { report = r } }
        return report
    }

    func fill(_ t: FixtureTree) {
        let big = t.url("Users/me/Downloads/movie.mov")
        try? FileManager.default.createDirectory(at: big.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let h = try! FileHandle(forWritingTo: big); try! h.truncate(atOffset: 60_000_000); try! h.close()
        for rel in ["Documents/a.bin", "Desktop/a.bin"] {
            let u = t.url("Users/me/" + rel)
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data(repeating: 9, count: 300_000).write(to: u)
        }
    }

    @Test func reportHasAllSections() async throws {
        let t = FixtureTree()
        fill(t)
        let r = try #require(try await run(ClutterScan(home: t.url("Users/me")), .home))
        #expect(r.largeOld.map(\.url.lastPathComponent) == ["movie.mov"])
        #expect(r.duplicates.count == 1)
        #expect(r.total == 1 + 2)
    }

    @Test func folderTargetSkipsDownloadsSection() async throws {
        let t = FixtureTree()
        fill(t)
        let r = try #require(try await run(ClutterScan(home: t.url("Users/me")), .folder(t.url("Users/me/Documents"))))
        #expect(r.largeOld.isEmpty && r.duplicates.isEmpty && r.downloads.isEmpty)
    }

    @Test func duplicateTilesByPlace() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let home = URL(fileURLWithPath: "/Users/me")
        func f(_ rel: String, _ size: Int64, created: Date? = nil) -> ClutterFile {
            ClutterFile(url: home.appendingPathComponent(rel), size: size, created: created ?? now.addingTimeInterval(-200 * 86_400))
        }
        let g = DuplicateGroup(files: [f("Downloads/a.png", 100), f("Documents/a.png", 100)], hash: "h")
        let tiles = ClutterTiles.make(home: home, now: now, largeOld: [], duplicates: [g], similar: [], downloads: [])
        #expect(tiles.first?.kind == .duplicatesDocuments)
        #expect(tiles.first?.size == 200) // total dos grupos, como o CleanMyMac (35,6 MB para 45 arquivos)
    }

    @Test func parityJSONMatchesBaselineKeys() throws {
        let report = ClutterReport(home: URL(fileURLWithPath: "/Users/me"), largeOld: [], duplicates: [], similar: [], downloads: [], tiles: [])
        let json = report.parityJSON()
        let baseline = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/re/parity/clutter-baseline-2026-10-23.json"))) as! [String: Any]
        #expect(Set(json.keys) == Set(baseline.keys))
    }
}
