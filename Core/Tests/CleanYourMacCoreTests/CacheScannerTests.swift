import Testing
import Foundation
@testable import CleanYourMacCore

struct FakeApps: AppLookup {
    var apps: [String: URL] = [:]
    func application(bundleID: String) -> (name: String, url: URL)? {
        apps[bundleID].map { (($0.lastPathComponent as NSString).deletingPathExtension, $0) }
    }
}

private func scan(_ s: any GroupScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}

private func userCache(_ t: FixtureTree, apps: FakeApps = FakeApps()) -> CacheScanner {
    CacheScanner.userCache(apps: apps, inventory: FolderAppInventory())
}

private let mb = 1_000_000

@Test func userCache_childrenBecomeItems() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Caches/Google/a", bytes: 1 * mb)
    t.file("Users/tester/Library/Caches/Homebrew/b", bytes: 2 * mb)
    let items = try await scan(userCache(t), ctx).sorted { $0.name < $1.name }
    #expect(items.map(\.name) == ["Google", "Homebrew"])
    #expect(items.allSatisfy { $0.leaves.allSatisfy { $0.isRecommended } })
    #expect(items[1].totalSize > items[0].totalSize)
}

@Test func userCache_dsStoreSkipped() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Caches/.DS_Store", bytes: 6000)
    #expect(try await scan(userCache(t), ctx).isEmpty)
}

@Test func userCache_emptyFolderIncluded() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.dir("Users/tester/Library/Caches/Vazio")
    let items = try await scan(userCache(t), ctx)
    #expect(items.map(\.name) == ["Vazio"])
    #expect(items[0].totalSize == 0)
}

@Test func userCache_symlinkSkipped() async throws {
    let t = FixtureTree(); let other = FixtureTree(); let ctx = t.context()
    other.file("big/x", bytes: mb)
    t.symlink("Users/tester/Library/Caches/link", to: other.url("big"))
    #expect(try await scan(userCache(t), ctx).isEmpty)
}

@Test func userCache_excludesPlaywright() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Caches/ms-playwright/x", bytes: 5 * mb)
    #expect(try await scan(userCache(t), ctx).isEmpty)
}

@Test func userCache_excludesAITools() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Caches/claude-cli-nodejs/a", bytes: 10)
    t.file("Users/tester/Library/Caches/com.openai.codex.helper/a", bytes: 10)
    t.file("var/folders/zz/C/com.anthropic.claudefordesktop/a", bytes: 10)
    #expect(try await scan(userCache(t), ctx).isEmpty)
}

@Test func userCache_darwinRoot() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("var/folders/zz/C/com.foo.bar/x", bytes: 10)
    #expect(try await scan(userCache(t), ctx).map(\.name) == ["com.foo.bar"])
}

@Test func userCache_clangIncludedAgentsExcluded() async throws {
    // Baseline de 16:13: o CleanMyMac mostra `clang`, mas ignora agentes como o ThumbnailsAgent.
    let t = FixtureTree(); let ctx = t.context()
    t.file("var/folders/zz/C/clang/ModuleCache/x", bytes: 10)
    t.file("var/folders/zz/C/com.apple.quicklook.ThumbnailsAgent/x", bytes: 10)
    #expect(try await scan(userCache(t), ctx).map(\.name) == ["clang"])
}

@Test func userCache_containerGroupedByContainer() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Containers/com.foo.app/Data/Library/Caches/A/x", bytes: 10_000)
    t.file("Users/tester/Library/Containers/com.foo.app/Data/Library/Caches/B/x", bytes: 20_000)
    let items = try await scan(userCache(t), ctx)
    #expect(items.map(\.name) == ["com.foo.app"])
    #expect(items[0].children.count == 2)
}

@Test func userCache_mergesSameIdentifier() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("var/folders/zz/C/com.foo.app/x", bytes: mb)
    t.file("Users/tester/Library/Containers/com.foo.app/Data/Library/Caches/A/x", bytes: 2 * mb)
    let items = try await scan(userCache(t), ctx)
    #expect(items.count == 1)
    #expect(items[0].children.count == 2)
}

@Test func userCache_displayNameFromBundleId() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = URL(fileURLWithPath: "/Applications/Foo.app")
    t.file("Users/tester/Library/Caches/com.foo.bar/x", bytes: 10)
    t.file("Users/tester/Library/Caches/com.apple.helpd/x", bytes: 10)
    let items = try await scan(userCache(t, apps: FakeApps(apps: ["com.foo.bar": app])), ctx).sorted { $0.name < $1.name }
    #expect(items.map(\.name) == ["Foo.app", "com.apple.helpd"])
    #expect(items[0].icon == .app(app))
}

@Test func userCache_sameDisplayNameNotMerged() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = URL(fileURLWithPath: "/Applications/Setapp.app")
    t.file("Users/tester/Library/Caches/com.setapp.DesktopClient/x", bytes: 10)
    t.file("Users/tester/Library/Caches/com.setapp.DesktopClient.SetappAgent/x", bytes: 10)
    let apps = FakeApps(apps: ["com.setapp.DesktopClient": app, "com.setapp.DesktopClient.SetappAgent": app])
    let names = try await scan(userCache(t, apps: apps), ctx).map(\.name)
    #expect(names == ["Setapp.app", "Setapp.app"])
}

@Test func userCache_gradleNotRecommended() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/.gradle/caches/modules-2/x", bytes: mb)
    let items = try await scan(userCache(t), ctx)
    #expect(items.map(\.name) == ["Gradle"])
    #expect(items[0].leaves.allSatisfy { !$0.isRecommended })
}

@Test func userCache_gradleZeroSkipped() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.dir("Users/tester/.gradle/caches/vazio")
    #expect(try await scan(userCache(t), ctx).isEmpty)
}

@Test func userCache_electronCache() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.app("Applications/Foo.app", bundleID: "com.foo.electron", electron: true)
    t.file("Users/tester/Library/Application Support/Foo/Cache/x", bytes: mb)
    let items = try await scan(userCache(t), ctx)
    #expect(items.map(\.name) == ["com.foo.electron"])
    #expect(items[0].leaves.allSatisfy { $0.isRecommended })
}

@Test func userCache_photosKeepsMostRecent() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let base = "Users/tester/Library/Containers/com.apple.Photos/Data/Library/Application Support/Photos Desktop/0"
    for (i, n) in ["a", "b", "c"].enumerated() {
        let f = t.file("\(base)/\(n)", bytes: 10)
        var tv = [timeval(tv_sec: 1_000_000 + i * 1000, tv_usec: 0), timeval(tv_sec: 1_000_000, tv_usec: 0)]
        utimes(f.path, &tv)
    }
    let items = try await scan(userCache(t), ctx).filter { $0.name == "com.apple.Photos" }
    #expect(Set(items.first?.leaves.map(\.name) ?? []) == ["a", "b"])
}

@Test func userCache_telegramNotRecommended() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable/account-1/postbox/media/x", bytes: 10)
    let items = try await scan(userCache(t), ctx)
    #expect(items.map(\.name) == ["ru.keepcoder.Telegram"])
    #expect(items[0].leaves.allSatisfy { !$0.isRecommended })
}

@Test func userCache_spotifyDefaultStorage() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Application Support/Spotify/PersistentCache/Storage/x", bytes: 10)
    let items = try await scan(userCache(t), ctx)
    #expect(items.map(\.name) == ["com.spotify.client"])
    #expect(items[0].leaves.allSatisfy { !$0.isRecommended })
}

@Test func userCache_appStorePurgeables() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let p = t.file("Users/tester/Downloads/old.pkg", bytes: 10)
    let manifest = t.url("var/folders/zz/C/com.apple.appstore/manifest.plist")
    t.dir("var/folders/zz/C/com.apple.appstore")
    try PropertyListSerialization.data(fromPropertyList: ["purgeables": [p.path]], format: .xml, options: 0).write(to: manifest)
    let items = try await scan(userCache(t), ctx).filter { $0.name == "com.apple.appstore" }
    let paths = items.first?.leaves.compactMap { $0.url?.path } ?? []
    #expect(paths.contains(p.path))
}

@Test func userCache_removalDeletesChildNotRoot() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Caches/Google/a", bytes: 10)
    let s = userCache(t)
    let item = try #require(try await scan(s, ctx).first)
    let policy = Registry.policies(for: [s], context: ctx)[.userCache]!
    for leaf in item.leaves {
        guard case .delete(let u) = leaf.removal else { Issue.record("removal"); continue }
        #expect(u.path == ctx.home.appendingPathComponent("Library/Caches/Google").path)
        #expect((try? policy.validate(u)) != nil)
    }
    #expect((try? policy.validate(ctx.home.appendingPathComponent("Library/Caches"))) == nil)
}

// MARK: systemCache

@Test func systemCache_childrenAndCoreSymbolication() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Library/Caches/com.apple.iconservices.store/x", bytes: 10)
    t.file("Library/Caches/ColorSync/x", bytes: 10)
    t.file("System/Library/Caches/com.apple.coresymbolicationd/data", bytes: 10)
    t.file("System/Library/Caches/other/x", bytes: 10)
    let items = try await scan(CacheScanner.systemCache(apps: FakeApps()), ctx).map(\.name).sorted()
    #expect(items == ["com.apple.coresymbolicationd", "com.apple.iconservices.store"])
}

@Test func systemCache_zeroDropped() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.dir("Library/Caches/empty")
    #expect(try await scan(CacheScanner.systemCache(apps: FakeApps()), ctx).isEmpty)
}

@Test func systemCache_itemIsLeafAndRecommended() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Library/Caches/com.apple.iconservices.store/x", bytes: 10)
    let item = try #require(try await scan(CacheScanner.systemCache(apps: FakeApps()), ctx).first)
    #expect(item.leaves.allSatisfy { $0.isRecommended })
    #expect(!item.displaysChildren)
}

@Test func systemCache_requiresAdmin() {
    #expect(GroupID.systemCache.requiresAdmin)
    #expect(GroupID.systemCache.requiresAdminToScan)
    #expect(!GroupID.userCache.requiresAdmin)
}

@Test func userCache_darwinExclusionThroughSymlinkedPath() async throws {
    // /var -> /private/var: a pasta do Darwin vem do confstr sem /private, a listagem vem com.
    let t = FixtureTree()
    t.file("var/folders/zz/C/com.apple.quicklook.ThumbnailsAgent/x", bytes: 10)
    t.file("var/folders/zz/C/com.keep/x", bytes: 10)
    let link = t.symlink("dlink", to: t.url("var/folders/zz/C"))
    var ctx = t.context()
    ctx.darwinUserCacheDir = link
    let names = try await scan(userCache(t), ctx).map(\.name)
    #expect(names == ["com.keep"])
}
