import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

private func leafItem(_ name: String, _ size: Int64, recommended: Bool = false, group: GroupID = .userCache) -> JunkItem {
    let url = URL(fileURLWithPath: "/tmp/sel/\(name)")
    return JunkItem(group: group, name: name, url: url, size: size, isRecommended: recommended, removal: .delete(url))
}

private func parentItem(_ name: String, _ children: [JunkItem], group: GroupID = .aiAgentsJunk) -> JunkItem {
    JunkItem(group: group, name: name, url: nil, size: 0, children: children)
}

@MainActor @Test func parentToggleSelectsChildren() {
    let a = leafItem("a", 10, group: .aiAgentsJunk), b = leafItem("b", 20, group: .aiAgentsJunk)
    let p = parentItem("p", [a, b])
    let s = SelectionModel()
    s.toggle(p)
    #expect(s.state(of: p) == .on)
    #expect(s.state(of: a) == .on && s.state(of: b) == .on)
    s.toggle(p)
    #expect(s.state(of: p) == .off)
    #expect(s.selectedItems.isEmpty)
}

@MainActor @Test func oneChildMakesParentMixed() {
    let a = leafItem("a", 10, group: .aiAgentsJunk), b = leafItem("b", 20, group: .aiAgentsJunk)
    let p = parentItem("p", [a, b])
    let s = SelectionModel()
    s.toggle(a)
    #expect(s.state(of: p) == .mixed)
    s.toggle(b)
    #expect(s.state(of: p) == .on)
}

@MainActor @Test func mixedParentToggleSelectsAll() {
    let a = leafItem("a", 10, group: .aiAgentsJunk), b = leafItem("b", 20, group: .aiAgentsJunk)
    let p = parentItem("p", [a, b])
    let s = SelectionModel()
    s.toggle(a)
    s.toggle(p)
    #expect(s.state(of: p) == .on)
}

@MainActor @Test func presetRecommended() {
    let a = leafItem("a", 10, recommended: true), b = leafItem("b", 20)
    let report = ScanReport(groups: [.userCache: GroupResult(group: .userCache, items: [a, b])])
    let s = SelectionModel()
    s.load(report)
    s.select(.recommended, in: .userCache)
    #expect(s.selectedItems.map(\.id) == [a.id])
    s.select(.all, in: .userCache)
    #expect(Set(s.selectedItems.map(\.id)) == [a.id, b.id])
    s.select(.none, in: .userCache)
    #expect(s.selectedItems.isEmpty)
}

@MainActor @Test func presetOnlyAffectsItsGroup() {
    let a = leafItem("a", 10), t = leafItem("t", 5, group: .trash)
    let report = ScanReport(groups: [.userCache: GroupResult(group: .userCache, items: [a]),
                                     .trash: GroupResult(group: .trash, items: [t])])
    let s = SelectionModel()
    s.load(report)
    s.select(.all, in: .trash)
    s.select(.all, in: .userCache)
    s.select(.none, in: .userCache)
    #expect(s.selectedItems.map(\.id) == [t.id])
}

@MainActor @Test func selectedBytesSumsLeavesOnly() {
    let a = leafItem("a", 10, group: .aiAgentsJunk), b = leafItem("b", 20, group: .aiAgentsJunk)
    let p = parentItem("p", [a, b])
    let s = SelectionModel()
    s.toggle(p)
    #expect(s.selectedBytes == 30)
    #expect(s.selectedCount == 2)
}

@MainActor @Test func groupStateReflectsItems() {
    let a = leafItem("a", 10), b = leafItem("b", 20)
    let report = ScanReport(groups: [.userCache: GroupResult(group: .userCache, items: [a, b])])
    let s = SelectionModel()
    s.load(report)
    #expect(s.state(of: .userCache) == .off)
    s.toggle(a)
    #expect(s.state(of: .userCache) == .mixed)
    s.toggle(group: .userCache)
    #expect(s.state(of: .userCache) == .on)
}

@MainActor @Test func initialSelectionUsesRecommended() {
    let a = leafItem("a", 10, recommended: true), b = leafItem("b", 20)
    let report = ScanReport(groups: [.userCache: GroupResult(group: .userCache, items: [a, b])])
    let s = SelectionModel()
    s.load(report)
    s.applyInitialSelection()
    #expect(s.selectedItems.map(\.id) == [a.id])
}
