import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

private func rep(_ sizes: [GroupID: [Int64]]) -> ScanReport {
    var groups: [GroupID: GroupResult] = [:]
    for (g, s) in sizes {
        groups[g] = GroupResult(group: g, items: s.enumerated().map { stubItem(g, "\(g.rawValue)\($0.offset)", $0.element) })
    }
    return ScanReport(groups: groups)
}

@Test func groupsSortedBySizeWithFixedTies() {
    let r = rep([.brokenLoginItems: [], .userLogs: [16], .userCache: [2800], .deletedUsers: [], .systemCache: [765],
                 .iosBackups: [], .documentVersions: [], .brokenPreferences: []])
    #expect(ReviewLogic.groups(in: .systemJunk, report: r) ==
            [.userCache, .systemCache, .userLogs, .brokenLoginItems, .documentVersions, .deletedUsers, .brokenPreferences, .iosBackups])
}

@Test func xcodeHiddenWhenEmptyOthersShown() {
    let r = rep([.xcodeJunk: [], .deletedUsers: []])
    #expect(ReviewLogic.groups(in: .systemJunk, report: r) == [.deletedUsers])
    #expect(ReviewLogic.groups(in: .systemJunk, report: rep([.xcodeJunk: [5]])) == [.xcodeJunk])
}

@Test func emptyCategoryDetection() {
    let r = rep([.mailAttachments: [], .userCache: [1]])
    #expect(ReviewLogic.isEmpty(.mailAttachments, report: r))
    #expect(!ReviewLogic.isEmpty(.systemJunk, report: r))
}

@Test func sortByNameTogglesDirection() {
    let items = ["beta", "Alpha", "gama"].map { stubItem(.userCache, $0, 1) }
    #expect(ReviewLogic.sorted(items, by: .name, ascending: true).map(\.name) == ["Alpha", "beta", "gama"])
    #expect(ReviewLogic.sorted(items, by: .name, ascending: false).map(\.name) == ["gama", "beta", "Alpha"])
    let sized = [stubItem(.userCache, "a", 1), stubItem(.userCache, "b", 3), stubItem(.userCache, "c", 2)]
    #expect(ReviewLogic.sorted(sized, by: .size, ascending: false).map(\.name) == ["b", "c", "a"])
}

@Test func toggleSortDirection() {
    var state = ReviewLogic.SortState()
    #expect(state.key == .size && state.ascending == false)
    state.choose(.name)
    #expect(state.key == .name && state.ascending)
    state.choose(.name)
    #expect(!state.ascending)
    state.choose(.size)
    #expect(state.key == .size && !state.ascending)
}

@Test func searchIgnoresCaseAndAccents() {
    let items = [stubItem(.userCache, "Google", 1), stubItem(.userCache, "Homebrew", 1), stubItem(.userCache, "Ação", 1)]
    #expect(ReviewLogic.filter(items, query: "goo").map(\.name) == ["Google"])
    #expect(ReviewLogic.filter(items, query: "acao").map(\.name) == ["Ação"])
    #expect(ReviewLogic.filter(items, query: "").count == 3)
}

@Test func searchMatchesChildren() {
    let child = stubItem(.aiAgentsJunk, "Caches", 1)
    let parent = JunkItem(group: .aiAgentsJunk, name: "Claude", url: nil, size: 0, children: [child])
    #expect(ReviewLogic.filter([parent], query: "cach").map(\.name) == ["Claude"])
}
