import Testing
import Foundation
@testable import CleanYourMacCore

private struct NamedFakeApps: AppLookup {
    var apps: [String: (String, URL)] = [:]
    func application(bundleID: String) -> (name: String, url: URL)? { apps[bundleID].map { ($0.0, $0.1) } }
}

private func rules(_ rules: [PathRule], group: GroupID = .userCache) -> GroupRules {
    GroupRules(group: group, rules: rules)
}

private func scan(_ s: RuleBasedScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}

@Test func childrenBecomeItems() async throws {
    let t = FixtureTree()
    let ctx = t.context()
    let a = t.file("Users/tester/Library/Caches/A/x", bytes: 8192)
    let b = t.file("Users/tester/Library/Caches/B/y", bytes: 4096)
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Library/Caches"], itemLevel: .children, recommended: true)]))
    let items = try await scan(s, ctx).sorted { $0.name < $1.name }
    #expect(items.map(\.name) == ["A", "B"])
    #expect(items[0].size == FixtureTree.allocated(a))
    #expect(items[1].size == FixtureTree.allocated(b))
    #expect(items.allSatisfy { $0.isRecommended && $0.group == .userCache })
    #expect(items[0].removal == .delete(t.url("Users/tester/Library/Caches/A")))
}

@Test func rootLevelItem() async throws {
    let t = FixtureTree()
    let ctx = t.context()
    t.file("Library/Logs/DiagnosticReports/a.ips", bytes: 100)
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["/Library/Logs/DiagnosticReports"], itemLevel: .root,
                                                    removal: .deleteContents)], group: .systemLogs))
    let items = try await scan(s, ctx)
    #expect(items.count == 1)
    #expect(items[0].removal == .deleteContents(of: t.url("Library/Logs/DiagnosticReports")))
}

@Test func excludeWins() async throws {
    let t = FixtureTree()
    let ctx = t.context()
    t.file("Users/tester/Library/Caches/com.apple.Safari/x", bytes: 10)
    t.file("Users/tester/Library/Caches/com.foo/x", bytes: 10)
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Library/Caches"], itemLevel: .children,
                                                    exclude: ["com.apple.Safari*"])]))
    #expect(try await scan(s, ctx).map(\.name) == ["com.foo"])
}

@Test func includeFilter() async throws {
    let t = FixtureTree()
    let ctx = t.context()
    t.file("Users/tester/Library/Logs/a.log", bytes: 10)
    t.file("Users/tester/Library/Logs/b.txt", bytes: 10)
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Library/Logs"], itemLevel: .children,
                                                    include: ["*.log"])], group: .userLogs))
    #expect(try await scan(s, ctx).map(\.name) == ["a.log"])
}

@Test func minAge() async throws {
    let t = FixtureTree()
    let ctx = t.context()
    t.file("Users/tester/Library/Logs/new.log", bytes: 10, modified: Date().addingTimeInterval(-86_400))
    t.file("Users/tester/Library/Logs/old.log", bytes: 10, modified: Date().addingTimeInterval(-30 * 86_400))
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Library/Logs"], itemLevel: .children, minAgeDays: 7)],
                                          group: .userLogs))
    #expect(try await scan(s, ctx).map(\.name) == ["old.log"])
}

@Test func missingRootIsEmpty() async throws {
    let t = FixtureTree()
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Nope"], itemLevel: .children)]))
    #expect(try await scan(s, t.context()).isEmpty)
}

@Test func symlinkChildNotFollowed() async throws {
    let t = FixtureTree()
    let outside = FixtureTree()
    outside.file("big/x", bytes: 1_000_000)
    let ctx = t.context()
    t.symlink("Users/tester/Library/Caches/link", to: outside.url("big"))
    t.file("Users/tester/Library/Caches/real/x", bytes: 10)
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Library/Caches"], itemLevel: .children)]))
    #expect(try await scan(s, ctx).map(\.name) == ["real"])
}

@Test func emptyChildSkipped() async throws {
    let t = FixtureTree()
    let ctx = t.context()
    t.dir("Users/tester/Library/Caches/empty")
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Library/Caches"], itemLevel: .children)]))
    #expect(try await scan(s, ctx).isEmpty)
}

@Test func unreadableChildTolerated() async throws {
    let t = FixtureTree()
    let ctx = t.context()
    t.file("Users/tester/Library/Caches/locked/x", bytes: 10)
    t.file("Users/tester/Library/Caches/ok/x", bytes: 10)
    t.chmod("Users/tester/Library/Caches/locked", 0o000)
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Library/Caches"], itemLevel: .children)]))
    #expect(try await scan(s, ctx).map(\.name) == ["ok"])
}

@Test func bundleIDFolderUsesAppName() async throws {
    let t = FixtureTree()
    let ctx = t.context()
    t.file("Users/tester/Library/Caches/com.foo.bar/x", bytes: 10)
    let appURL = URL(fileURLWithPath: "/Applications/Foo.app")
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Library/Caches"], itemLevel: .children)]),
                             apps: NamedFakeApps(apps: ["com.foo.bar": ("Foo", appURL)]))
    let item = try #require(try await scan(s, ctx).first)
    #expect(item.name == "Foo")
    #expect(item.icon == .app(appURL))
}

@Test func reportsProgress() async throws {
    let t = FixtureTree()
    let ctx = t.context()
    t.file("Users/tester/Library/Caches/A/x", bytes: 10)
    let s = RuleBasedScanner(rules: rules([PathRule(roots: ["~/Library/Caches"], itemLevel: .children)]))
    let seen = Paths()
    _ = try await s.scan(ctx) { seen.add($0.currentPath) }
    #expect(seen.all.contains { $0.hasSuffix("Library/Caches/A") })
}

@Test func bundledLoads() throws {
    for group in GroupID.allCases where RuleBasedScanner.hasBundledRules(group) {
        #expect(try RuleBasedScanner.bundled(group).group == group)
    }
}

final class Paths: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
