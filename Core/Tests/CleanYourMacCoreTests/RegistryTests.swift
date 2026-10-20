import Testing
import Foundation
@testable import CleanYourMacCore

@Test func ruleRootsBecomePolicies() throws {
    let t = FixtureTree()
    let ctx = t.context()
    let s = RuleBasedScanner(rules: GroupRules(group: .userCache, rules: [
        PathRule(roots: ["~/Library/Caches"], itemLevel: .children),
        PathRule(roots: ["~/Library/Logs/Foo"], itemLevel: .root),
    ]))
    let roots = s.allowedRoots(ctx).map(\.path)
    #expect(roots.contains(ctx.resolve("~/Library/Caches").path))
    // Item de nível raiz: a política permite a própria pasta (via pai), não os irmãos dela.
    #expect(roots.contains(ctx.resolve("~/Library/Logs").path) == false)
    let policy = Registry.policies(for: [s], context: ctx)[.userCache]!
    #expect((try? policy.validate(ctx.resolve("~/Library/Logs/Foo"))) != nil)
    #expect((try? policy.validate(ctx.resolve("~/Library/Logs/Bar"))) == nil)
}

@Test func productionScannersAreUniquePerGroup() {
    let groups = Registry.productionScanners().map(\.group)
    #expect(Set(groups).count == groups.count)
}
