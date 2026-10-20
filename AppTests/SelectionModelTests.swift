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
    s.select(.smart, in: .userCache)
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

@MainActor @Test func initialSelectionIsEmpty() {
    let a = leafItem("a", 10, recommended: true), b = leafItem("b", 20)
    let report = ScanReport(groups: [.userCache: GroupResult(group: .userCache, items: [a, b])])
    let s = SelectionModel()
    s.load(report)
    #expect(s.selectedItems.isEmpty)
    #expect(s.presetState(in: .userCache) == .none)
    #expect(!s.hasChanges)
}

@MainActor @Test func presetStateFollowsSelection() {
    let items = (0..<5).map { leafItem("i\($0)", 10, recommended: $0 < 2) }
    let report = ScanReport(groups: [.userCache: GroupResult(group: .userCache, items: items)])
    let s = SelectionModel()
    s.load(report)
    s.select(.smart, in: .userCache)
    #expect(s.selectedCount == 2)
    #expect(s.presetState(in: .userCache) == .smart)
    s.toggle(items[0])
    #expect(s.presetState(in: .userCache) == .manual)
    s.select(.all, in: .userCache)
    #expect(s.presetState(in: .userCache) == .all)
    s.select(.none, in: .userCache)
    #expect(s.presetState(in: .userCache) == .none)
    #expect(s.hasChanges == false)
}

@MainActor @Test func smartSelectDisabledWithoutRecommended() {
    let report = ScanReport(groups: [.userCache: GroupResult(group: .userCache, items: [leafItem("a", 1)])])
    let s = SelectionModel()
    s.load(report)
    #expect(!s.canSmartSelect(.userCache))
}

@MainActor @Test func latestBackupNeedsConfirmation() {
    let url = URL(fileURLWithPath: "/tmp/sel/backup")
    let latest = JunkItem(group: .iosBackups, name: "b", url: url, size: 5, badge: .latest, removal: .delete(url))
    let report = ScanReport(groups: [.iosBackups: GroupResult(group: .iosBackups, items: [latest])])
    let s = SelectionModel()
    s.load(report)
    s.toggle(latest)
    #expect(s.pendingAlert == .iosLatestBackup)
    #expect(s.selectedItems.isEmpty)
    s.cancelPending()
    #expect(s.pendingAlert == nil && s.selectedItems.isEmpty)
    s.toggle(latest)
    s.confirmPending()
    #expect(s.selectedItems.map(\.id) == [latest.id])
}

@MainActor @Test func selectAllLocalModelsOneAlert() {
    let a = leafItem("m1", 10, group: .localModels), b = leafItem("m2", 20, group: .localModels)
    let report = ScanReport(groups: [.localModels: GroupResult(group: .localModels, items: [a, b])])
    let s = SelectionModel()
    s.load(report)
    s.select(.all, in: .localModels)
    #expect(s.pendingAlert == .localModels)
    s.confirmPending()
    #expect(s.selectedCount == 2)
    #expect(s.pendingAlert == nil)
}

@MainActor @Test func deselectNeverNeedsConfirmation() {
    let a = leafItem("m1", 10, group: .localModels)
    let report = ScanReport(groups: [.localModels: GroupResult(group: .localModels, items: [a])])
    let s = SelectionModel()
    s.load(report)
    s.toggle(a); s.confirmPending()
    s.toggle(a)
    #expect(s.pendingAlert == nil && s.selectedItems.isEmpty)
}

@MainActor @Test func duplicateURLCountedOnceInBytes() {
    let url = URL(fileURLWithPath: "/tmp/sel/same")
    let a = JunkItem(id: "x:1", group: .userCache, name: "a", url: url, size: 10, removal: .delete(url))
    let b = JunkItem(id: "x:2", group: .userLogs, name: "b", url: url, size: 10, removal: .delete(url))
    let s = SelectionModel()
    s.toggle(a); s.toggle(b)
    #expect(s.selectedBytes == 10)
}
