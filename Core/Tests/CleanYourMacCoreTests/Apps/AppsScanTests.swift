import Foundation
import Testing
@testable import CleanYourMacCore

private func makeScan(_ t: FixtureTree, fetcher: FakeFetcher = FakeFetcher(), slowQuery: Bool = false) -> AppsScan {
    let catalog = AppCatalog(query: FakeAppQuery(), usage: FakeUsage())
    let finder = RelatedFilesFinder(loginItems: FakeLoginItems(entries: []), receipts: FakeReceipts())
    return AppsScan(catalog: catalog, uninstaller: UninstallerScanner(catalog: catalog, finder: finder),
                    leftovers: LeftoversScanner(catalog: catalog, finder: finder, appExists: { _ in false }),
                    installers: InstallersScanner(query: FakeDiskImageQuery(results: []), mountedImages: { [] }),
                    updates: UpdateChecker(sources: [SparkleSource(home: t.url("Users/tester"))], macOS: nil, fetcher: fetcher,
                                           requestTimeout: .milliseconds(200), totalTimeout: .seconds(1)))
}

private func run(_ scan: AppsScan, _ ctx: ScanContext) async throws -> AppsReport? {
    for try await e in scan.run(ctx) { if case .finished(let r) = e { return r } }
    return nil
}

@Suite struct AppsScanTests {
    @Test func reportHasAllSections() async throws {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/Foo.app", bundleID: "com.foo", build: "1", feed: "https://foo.example/appcast.xml")
        t.file("Users/tester/Library/Preferences/com.foo.plist", bytes: 10)
        let f = FakeFetcher()
        f.on("https://foo.example/appcast.xml", """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>2</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
        <enclosure url="https://foo.example/f.zip" length="1"/></item></channel></rss>
        """)
        let report = try #require(try await run(makeScan(t, fetcher: f), t.context()))
        #expect(report.apps.map(\.name) == ["Foo.app"])
        #expect(report.uninstaller.count == 1)
        #expect(report.updates.updates.map(\.availableVersion) == ["2.0"])
        #expect(report.leftovers.isEmpty)
        #expect(report.installers.isEmpty)
    }

    @Test func cancelStopsQuickly() async throws {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/Foo.app", bundleID: "com.foo", build: "1", feed: "https://foo.example/appcast.xml")
        let f = FakeFetcher()
        f.delay = .seconds(5)
        let scan = makeScan(t, fetcher: f)
        let task = Task { try await run(scan, t.context()) }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        task.cancel()
        let result = await task.result
        #expect(ContinuousClock.now - start < .milliseconds(1500))
        if case .success(let r) = result { #expect(r == nil) }
    }

    @Test func noNetworkStillReports() async throws {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/Foo.app", bundleID: "com.foo", build: "1", feed: "https://foo.example/appcast.xml")
        let report = try #require(try await run(makeScan(t), t.context()))
        #expect(report.updates.offline)
        #expect(report.apps.count == 1)
    }

    @Test func filterCountsHideEmptyStoresAndVendors() {
        let now = Date()
        let apps = [
            AppRecord(url: URL(fileURLWithPath: "/Applications/A.app"), bundleID: "com.apple.a", name: "A.app", store: .appStore, vendor: .apple),
            AppRecord(url: URL(fileURLWithPath: "/Applications/B.app"), bundleID: "b", name: "B.app",
                      lastOpened: Calendar.current.date(byAdding: .year, value: -1, to: now)),
            AppRecord(url: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/P.driver"), bundleID: "com.apple.p", name: "P.driver",
                      vendor: .apple, kind: .audioPlugin, isProtected: true),
        ]
        let counts = AppFilter.counts(apps: apps, selected: [], now: now)
        #expect(counts == [.all: 2, .unused: 1, .suspicious: 0, .selected: 0, .store(.appStore): 1, .store(.other): 1,
                           .vendor(.apple): 1, .vendor(.other): 1, .audioPlugins: 1])
        #expect(AppFilter.apply(.audioPlugins, to: apps, selected: [], now: now).map(\.name) == ["P.driver"])
        #expect(AppFilter.apply(.all, to: apps, selected: [], now: now).map(\.name) == ["A.app", "B.app"])
    }

    @Test func cliJsonMatchesBaselineShape() async throws {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/Foo.app", bundleID: "com.foo")
        let report = try #require(try await run(makeScan(t), t.context()))
        let json = report.parityJSON()
        let baselineURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/re/parity/apps-baseline-2026-10-21.json")
        let baseline = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: baselineURL)) as? [String: Any])
        #expect(Set(json.keys).isSuperset(of: Set(baseline.keys).subtracting(["cmmVersion"])))
        let app = try #require((json["apps"] as? [[String: Any]])?.first)
        let baseApp = try #require((baseline["apps"] as? [[String: Any]])?.first)
        #expect(Set(app.keys) == Set(baseApp.keys))
        #expect(Set((json["leftovers"] as? [String: Any])?.keys ?? [:].keys) == ["leftoverFiles", "installers"])
        #expect(JSONSerialization.isValidJSONObject(json))
    }
}
