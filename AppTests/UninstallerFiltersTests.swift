import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

private func app(_ name: String, size: Int64, opened: Date?) -> AppRecord {
    AppRecord(url: URL(fileURLWithPath: "/Applications/\(name)"), bundleID: "com.\(name)", name: name, lastOpened: opened, bundleSize: size)
}

struct UninstallerFiltersTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func nameSortIsFinderLike() {
        let apps = [app("Claude.app", size: 1, opened: nil), app("Claude Code URL Handler.app", size: 1, opened: nil),
                    app("bruno.app", size: 1, opened: nil)]
        let sorted = UninstallerSort(key: .name, ascending: true).sort(apps, sizes: [:])
        #expect(sorted.map(\.name) == ["bruno.app", "Claude Code URL Handler.app", "Claude.app"])
    }

    @Test func sortByLastOpenedPutsNeverOpenedLastBothWays() {
        let apps = [app("A.app", size: 1, opened: nil), app("B.app", size: 1, opened: now),
                    app("C.app", size: 1, opened: now.addingTimeInterval(-3600))]
        #expect(UninstallerSort(key: .lastOpened, ascending: true).sort(apps, sizes: [:]).map(\.name) == ["C.app", "B.app", "A.app"])
        #expect(UninstallerSort(key: .lastOpened, ascending: false).sort(apps, sizes: [:]).map(\.name) == ["B.app", "C.app", "A.app"])
    }

    @Test func sortBySizeUsesRowTotals() {
        let a = app("A.app", size: 1, opened: nil), b = app("B.app", size: 1, opened: nil)
        let sorted = UninstallerSort(key: .size, ascending: false).sort([a, b], sizes: [a.id: 10, b.id: 99])
        #expect(sorted.map(\.name) == ["B.app", "A.app"])
    }

    @Test func searchMatchesNameCaseInsensitive() {
        let apps = [app("Visual Studio Code.app", size: 1, opened: nil), app("Xcode.app", size: 1, opened: nil)]
        #expect(UninstallerSort.search(apps, "CODE").map(\.name) == ["Visual Studio Code.app", "Xcode.app"])
        #expect(UninstallerSort.search(apps, "studio").map(\.name) == ["Visual Studio Code.app"])
        #expect(UninstallerSort.search(apps, "  ").count == 2)
    }

    @MainActor @Test func selectedFilterFollowsSelection() {
        let a = app("A.app", size: 1, opened: nil)
        let counts = AppFilter.counts(apps: [a], selected: [a.id], now: now)
        #expect(counts[.selected] == 1)
    }
}
