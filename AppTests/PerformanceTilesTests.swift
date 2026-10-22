import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

@MainActor
@Suite struct PerformanceTilesTests {
    @Test func tilesFollowSpec() {
        let report = perfReport()
        let tiles = PerformanceTile.tiles(for: report)
        // Ordem dos dados: RAM, manutenção, capturas, início, segundo plano (results-screen.md §2.1).
        #expect(tiles.map(\.kind) == [.maintenance, .loginItems, .backgroundItems])
        #expect(tiles.map(\.count) == [5, 1, 2])
        #expect(tiles[0].actions == [.review(.maintenance), .run([.speedUpMail, .flushDNS, .freeUpPurgeable, .reindexSpotlight, .repairPermissions])])
        #expect(tiles[1].actions == [.review(.loginItems)])
        #expect(tiles[2].actions == [.review(.backgroundItems)])
        // Ícones: até 3, das primeiras tarefas por título.
        #expect(tiles[0].icons.count == 3)
    }

    @Test func ramAndSnapshotTilesHaveOwnActions() {
        let report = perfReport(tasks: [perfTask(.freeUpRAM), perfTask(.flushDNS), perfTask(.thinSnapshots)], login: [], background: [])
        let tiles = PerformanceTile.tiles(for: report)
        #expect(tiles.map(\.kind) == [.freeUpRAM, .maintenance, .thinSnapshots])
        #expect(tiles[0].actions == [.run([.freeUpRAM])])
        // O cartão de manutenção não conta a RAM (cartão próprio), mas conta as capturas.
        #expect(tiles[1].count == 2)
        #expect(tiles[2].actions == [.review(.snapshots), .run([.thinSnapshots])])
    }

    @Test func noTilesWhenNothingApplies() {
        #expect(PerformanceTile.tiles(for: perfReport(tasks: [], login: [], background: [])).isEmpty)
    }

    @Test func loginTileCountsOnlyEnabled() {
        let off = StartupItem(kind: .sessionLoginItem, name: "Off.app", program: warpApp, state: .disabled)
        let tiles = PerformanceTile.tiles(for: perfReport(tasks: [], login: [off], background: []))
        #expect(tiles.isEmpty)
    }
}
