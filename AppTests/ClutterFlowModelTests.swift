import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

struct FakeClutterScan: ClutterScanning {
    var report: ClutterReport
    func run(_ target: ClutterTarget) -> AsyncThrowingStream<ClutterScanEvent, Error> {
        let report = report
        return AsyncThrowingStream { cont in
            cont.yield(.progress("files"))
            cont.yield(.finished(report))
            cont.finish()
        }
    }
}

final class RecordingClutterRemover: ClutterRemoving, @unchecked Sendable {
    private(set) var removed: [[String]] = []
    var failing: Set<String> = []
    func remove(_ files: [ClutterFile]) async -> [String: Result<Void, CleanFailure>] {
        removed.append(files.map(\.url.path))
        return Dictionary(uniqueKeysWithValues: files.map { ($0.url.path, failing.contains($0.url.path) ? .failure(CleanFailure(reason: "denied")) : .success(())) })
    }
}

final class RecordingPhotos: PhotoRemoving, @unchecked Sendable {
    private(set) var removed: [[String]] = []
    func remove(_ ids: [String]) async -> Result<Void, CleanFailure> {
        removed.append(ids)
        return .success(())
    }
}

@MainActor
struct ClutterSetup {
    let remover = RecordingClutterRemover()
    let photos = RecordingPhotos()
    let model: ClutterFlowModel
    static let home = URL(fileURLWithPath: "/u")
    static let now = Date(timeIntervalSince1970: 1_792_000_000)

    static func file(_ rel: String, _ size: Int64, daysAgo: Double = 400) -> ClutterFile {
        let d = now.addingTimeInterval(-daysAgo * 86_400)
        return ClutterFile(url: home.appendingPathComponent(rel), size: size, modified: d, created: d, accessed: d)
    }

    static func image(_ id: String, url: URL?, best: Bool) -> SimilarImage {
        SimilarImage(id: id, url: url, date: now, size: 1000, pixels: 100, sharpness: 1, isBest: best, flaws: [])
    }

    static var report: ClutterReport {
        let big = file("Movies/big.mov", 60_000_000)
        let dups = [DuplicateGroup(files: [file("Downloads/a.png", 200_000), file("Documents/a.png", 200_000)], hash: "d1")]
        let sim = [SimilarGroup(images: [image("/u/Pictures/p1.jpg", url: URL(fileURLWithPath: "/u/Pictures/p1.jpg"), best: true),
                                         image("photo-1", url: nil, best: false)])]
        let dl = [DownloadsFinder.Group(app: .chrome, files: [DownloadsFinder.Item(file: file("Downloads/z.dmg", 9_000), downloaded: now)],
                                        autoselected: [])]
        let tiles = ClutterTiles.make(home: home, now: now, largeOld: [big], duplicates: dups, similar: sim, downloads: dl)
        return ClutterReport(home: home, largeOld: [big], duplicates: dups, similar: sim, downloads: dl, tiles: tiles)
    }

    init(report: ClutterReport = ClutterSetup.report, dryRun: Bool = false) {
        model = ClutterFlowModel(scan: FakeClutterScan(report: report), remover: remover, photos: photos, dryRun: dryRun,
                                 now: { ClutterSetup.now })
    }

    func scanned() async -> ClutterFlowModel {
        model.start()
        while model.phase == .scanning { await Task.yield() }
        return model
    }
}

@MainActor
@Suite struct ClutterFlowModelTests {
    @Test func scanEndsInResultsWithEmptySelection() async {
        let m = await ClutterSetup().scanned()
        #expect(m.phase == .results)
        #expect(m.selection.isEmpty && m.report?.total == 6)
    }

    @Test func emptyReportIsNothingFound() async {
        let empty = ClutterReport(home: ClutterSetup.home, largeOld: [], duplicates: [], similar: [], downloads: [], tiles: [])
        let m = await ClutterSetup(report: empty).scanned()
        #expect(m.phase == .nothingFound)
    }

    @Test func reviewAllStartsEmptyAndTileReviewAutoselects() async {
        let m = await ClutterSetup().scanned()
        m.openManager(.largeOld)
        #expect(m.managerOpen && m.selection.isEmpty)
        m.openManager(.duplicates, autoselect: true)
        #expect(m.selection == ["/u/Downloads/a.png"] && m.canRemove)
        m.openManager(.similar, autoselect: true)
        #expect(m.selection.contains("photo-1") && !m.selection.contains("/u/Pictures/p1.jpg"))
    }

    @Test func markingLastCopyAsksAndBlocksRemoval() async {
        let m = await ClutterSetup().scanned()
        let ids = ["/u/Downloads/a.png", "/u/Documents/a.png"]
        m.toggle(ids[0], group: ("d1", ids))
        m.toggle(ids[1], group: ("d1", ids))
        #expect(m.pendingFull?.group == "d1" && m.selection == [ids[0]])
        m.cancelSelectAll()
        #expect(m.selection == [ids[0]] && m.canRemove)
        m.toggle(ids[1], group: ("d1", ids))
        m.confirmSelectAll()
        #expect(m.selection == Set(ids) && m.canRemove)
        // Desmarcar uma cópia tira a confirmação: marcar de novo pede outra vez.
        m.toggle(ids[1], group: ("d1", ids))
        m.toggle(ids[1], group: ("d1", ids))
        #expect(m.pendingFull != nil)
    }

    @Test func pickAllNeedsConfirmation() async {
        let m = await ClutterSetup().scanned()
        let g = try! #require(m.report?.duplicates.first)
        m.pick(.all, group: g.id, items: g.files.map(ClutterPick.Item.init))
        #expect(m.selection.isEmpty && m.pendingFull != nil)
        m.confirmSelectAll()
        #expect(m.selection.count == 2)
        m.pick(.keepNewest, group: g.id, items: g.files.map(ClutterPick.Item.init))
        #expect(m.selection.count == 1)
    }

    @Test func removalSendsFilesAndPhotosAndUpdatesReport() async {
        let s = ClutterSetup()
        let m = await s.scanned()
        m.toggle("/u/Movies/big.mov")
        m.toggle("photo-1", group: ("sim", ["/u/Pictures/p1.jpg", "photo-1"]))
        m.toggle("/u/Downloads/z.dmg")
        #expect(m.selectedCount == 3 && m.selectedSize == 60_000_000 + 1000 + 9_000)
        m.requestRemoval()
        #expect(m.confirmingRemoval)
        m.confirmRemoval()
        while m.phase == .removing { await Task.yield() }
        #expect(s.remover.removed == [["/u/Movies/big.mov", "/u/Downloads/z.dmg"]])
        #expect(s.photos.removed == [["photo-1"]])
        guard case .done(let o) = m.phase else { Issue.record("deveria concluir"); return }
        #expect(o.removed == 3 && o.failed.isEmpty)
        #expect(m.report?.largeOld.isEmpty == true && m.report?.similar.isEmpty == true && m.report?.downloads.isEmpty == true)
        #expect(m.selection.isEmpty)
        m.reviewMore()
        #expect(m.managerOpen && m.phase == .results)
    }

    @Test func failuresStayInReport() async {
        let s = ClutterSetup()
        s.remover.failing = ["/u/Movies/big.mov"]
        let m = await s.scanned()
        m.toggle("/u/Movies/big.mov")
        m.requestRemoval()
        m.confirmRemoval()
        while m.phase == .removing { await Task.yield() }
        guard case .done(let o) = m.phase else { Issue.record("deveria concluir"); return }
        #expect(o.failed == ["big.mov": "denied"] && o.removed == 0)
        #expect(m.report?.largeOld.count == 1)
    }

    @Test func dryRunSkipsPhotoKit() async {
        let s = ClutterSetup(dryRun: true)
        let m = await s.scanned()
        m.toggle("photo-1", group: ("sim", ["/u/Pictures/p1.jpg", "photo-1"]))
        m.requestRemoval()
        m.confirmRemoval()
        while m.phase == .removing { await Task.yield() }
        #expect(s.photos.removed.isEmpty)
    }

    @Test func backAndChooseFolder() async {
        let m = await ClutterSetup().scanned()
        m.toggle("/u/Movies/big.mov")
        m.back()
        #expect(m.phase == .intro && m.selection.isEmpty)
        m.choose(folder: URL(fileURLWithPath: "/tmp/x"))
        #expect(m.target == .folder(URL(fileURLWithPath: "/tmp/x")))
        m.choose(folder: nil)
        #expect(m.target == .home)
    }

    @Test func largeOldFilterTotals() {
        let now = ClutterSetup.now
        let a = ClutterSetup.file("a.mov", 1_200_000_000, daysAgo: 3), b = ClutterSetup.file("b.zip", 60_000_000, daysAgo: 40)
        let totals = LargeOldFilter.totals([a, b], selected: [b.url.path], now: now)
        #expect(totals[.all] == 1_260_000_000 && totals[.selected] == 60_000_000)
        #expect(totals[.size(.huge)] == 1_200_000_000 && totals[.size(.average)] == nil)
        #expect(totals[.age(.lastWeek)] == 1_200_000_000 && totals[.age(.oneMonthAgo)] == 60_000_000)
    }
}
