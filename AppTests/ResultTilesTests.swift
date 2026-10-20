import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

private func report(_ sizes: [GroupID: [(Int64, Bool)]]) -> ScanReport {
    var groups: [GroupID: GroupResult] = [:]
    for (g, entries) in sizes {
        groups[g] = GroupResult(group: g, items: entries.enumerated().map { i, e in stubItem(g, "\(g.rawValue)-\(i)", e.0, recommended: e.1) })
    }
    return ScanReport(groups: groups)
}

@Test func systemTileExcludesOwnTileGroups() {
    let r = report([.userCache: [(2_800, true)], .universalBinaries: [(32, true)]])
    let tiles = ResultTile.make(from: r)
    #expect(tiles.map(\.kind) == [.systemJunk, .universalBinaries])
    #expect(tiles[0].size == 2_800)
    #expect(tiles[1].size == 32)
    #expect(r.totalSize == 2_832)
}

@Test func onlyAITile() {
    let tiles = ResultTile.make(from: report([.aiAgentsJunk: [(10, false)]]))
    #expect(tiles.map(\.kind) == [.aiClutter])
    #expect(tiles[0].canClean == false)
}

@Test func emptyReportHasNoTiles() {
    #expect(ResultTile.make(from: report([.userCache: [], .trash: []])).isEmpty)
}

@Test func trashTileNeedsBytes() {
    #expect(ResultTile.make(from: report([.trash: [], .mailTrash: []])).isEmpty)
    #expect(ResultTile.make(from: report([.mailTrash: [(5, true)]])).map(\.kind) == [.trashBins])
}

@Test func tileOrderFollowsSpec() {
    let r = report([.documentVersions: [(1, true)], .deletedUsers: [(1, true)], .iosBackups: [(1, true)],
                    .xcodeJunk: [(1, true)], .universalBinaries: [(1, true)], .trash: [(1, true)],
                    .mailAttachments: [(1, true)], .aiAgentsJunk: [(1, true)], .systemLogs: [(1, true)]])
    #expect(ResultTile.make(from: r).map(\.kind) == [.systemJunk, .aiClutter, .mailAttachments, .trashBins,
                                                      .universalBinaries, .xcodeJunk, .iosBackups, .deletedUsers,
                                                      .documentVersions])
}

@Test func systemTileIconsAreTopThreeGroups() {
    let r = report([.userCache: [(100, true)], .systemCache: [(50, true)], .userLogs: [(10, true)], .systemLogs: [(1, true)]])
    #expect(ResultTile.make(from: r)[0].iconGroups == [.userCache, .systemCache, .userLogs])
}

@Test func onlySystemTileCanClean() {
    let r = report([.userCache: [(1, true)], .universalBinaries: [(1, true)], .trash: [(1, true)]])
    #expect(ResultTile.make(from: r).filter(\.canClean).map(\.kind) == [.systemJunk])
}

@MainActor @Test func cleanSystemTileUsesRecommendedOnly() async {
    let a = stubItem(.userCache, "a", 10), b = stubItem(.userCache, "b", 20), c = stubItem(.userCache, "c", 5, recommended: false)
    let l = stubItem(.systemLogs, "l", 7, recommended: false)
    let u = stubItem(.universalBinaries, "u", 30)
    let m = makeModel([StubScanner(group: .userCache, items: [a, b, c]), StubScanner(group: .systemLogs, items: [l]),
                       StubScanner(group: .universalBinaries, items: [u])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.clean(tile: .systemJunk)
    await waitFor { if case .done = m.phase { true } else { false } }
    guard case .done(let rep) = m.phase else { Issue.record("não terminou"); return }
    #expect(Set(rep.removed) == [a.id, b.id])
}
