import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

private func app(_ name: String, is32: Bool = false, protected: Bool = false) -> AppRecord {
    AppRecord(url: URL(fileURLWithPath: "/Applications/\(name)"), bundleID: "com.\(name)", name: name, isProtected: protected, is32Bit: is32)
}

private func item(_ group: GroupID, _ name: String, _ size: Int64) -> JunkItem {
    let url = URL(fileURLWithPath: "/tmp/\(name)")
    return JunkItem(id: AppItemID.leftover(bundleID: "com.\(name)", path: url.path), group: group, name: name, url: url,
                    size: size, isRecommended: true, removal: .moveToTrash(url))
}

private func update(_ source: UpdateSourceKind, major: Bool = false) -> AppUpdate {
    AppUpdate(id: UUID().uuidString, appID: nil, name: "x", source: source, installedVersion: "1", availableVersion: "2",
              action: .openSoftwareUpdate, isMajor: major)
}

struct AppsTilesTests {
    @Test func tilesFollowSpecOrderAndConditions() {
        let report = AppsReport(apps: [app("A.app"), app("Old.app", is32: true)], uninstaller: [],
                                leftovers: [item(.appLeftovers, "gone", 4096)], installers: [item(.appInstallers, "x.dmg", 1000)],
                                updates: UpdateCheckResult(updates: [update(.macOS), update(.macOS, major: true), update(.appStore)], offline: false))
        let tiles = AppsTile.tiles(for: report)
        #expect(tiles.map(\.kind) == [.macOSUpdates, .appUpdates, .uninstaller, .bit32, .leftovers, .installers])
        #expect(tiles.first { $0.kind == .macOSUpdates }?.count == 1) // a versão principal fica fora do cartão
        #expect(tiles.first { $0.kind == .leftovers }?.size == 4096)
        #expect(tiles.first { $0.kind == .installers }?.actions == [.review(.leftovers)])
        #expect(tiles.first { $0.kind == .leftovers }?.actions == [.review(.leftovers), .removeRecommended])
    }

    @Test func nothingFoundHasNoTiles() {
        let report = AppsReport(apps: [], uninstaller: [], leftovers: [], installers: [], updates: UpdateCheckResult(updates: [], offline: true))
        #expect(AppsTile.tiles(for: report).isEmpty)
    }

    @Test func onlyProtectedAppsHideUninstallerTile() {
        let report = AppsReport(apps: [app("S.app", protected: true)], uninstaller: [], leftovers: [], installers: [],
                                updates: UpdateCheckResult(updates: [], offline: false))
        #expect(AppsTile.tiles(for: report).isEmpty)
    }
}
