import Testing
import Foundation
@testable import CleanYourMacCore

@Test func groupCategories() {
    #expect(GroupID.userCache.category == .systemJunk)
    #expect(GroupID.xcodeJunk.category == .systemJunk)
    #expect(GroupID.iosBackups.category == .systemJunk)
    #expect(GroupID.aiAgentsJunk.category == .aiClutter)
    #expect(GroupID.localModels.category == .aiClutter)
    #expect(GroupID.mailAttachments.category == .mailAttachments)
    #expect(GroupID.trash.category == .trashBins)
    #expect(GroupID.mailTrash.category == .trashBins)
}

@Test func everyCategoryHasGroups() {
    for c in CategoryID.allCases {
        #expect(!GroupID.allCases.filter { $0.category == c }.isEmpty)
    }
}

@Test func contextResolvesTemplates() {
    let ctx = ScanContext(root: URL(fileURLWithPath: "/tmp/r"), home: URL(fileURLWithPath: "/tmp/r/Users/a"),
                          userName: "a", preferredLanguages: ["en"], now: .now)
    #expect(ctx.resolve("~/Library/Caches").path == "/tmp/r/Users/a/Library/Caches")
    #expect(ctx.resolve("$ROOT/Library/Logs").path == "/tmp/r/Library/Logs")
    #expect(ctx.resolve("/Library/Logs").path == "/tmp/r/Library/Logs")
}

@Test func junkItemTotalIncludesChildren() {
    let a = JunkItem(group: .userCache, name: "a", url: nil, size: 10)
    let b = JunkItem(group: .userCache, name: "b", url: nil, size: 5)
    let parent = JunkItem(group: .userCache, name: "p", url: nil, size: 0, children: [a, b])
    #expect(parent.totalSize == 15)
    #expect(a.totalSize == 10)
}
