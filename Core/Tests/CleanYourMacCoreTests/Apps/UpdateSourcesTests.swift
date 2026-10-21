import Foundation
import Testing
@testable import CleanYourMacCore

/// Respostas por prefixo de URL; registra o que foi pedido.
final class FakeFetcher: HTTPFetcher, @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [URL] = []
    var responses: [(prefix: String, result: Result<Data, Error>)] = []
    var delay: Duration = .zero

    var requested: [URL] { lock.lock(); defer { lock.unlock() }; return _requested }

    private func record(_ url: URL) { lock.lock(); defer { lock.unlock() }; _requested.append(url) }

    func get(_ url: URL, timeout: Duration) async throws -> Data {
        record(url)
        if delay > .zero {
            if delay > timeout {
                try await Task.sleep(for: timeout)
                throw URLError(.timedOut)
            }
            try await Task.sleep(for: delay)
        }
        guard let hit = responses.first(where: { url.absoluteString.hasPrefix($0.prefix) }) else { throw URLError(.badServerResponse) }
        return try hit.result.get()
    }

    func on(_ prefix: String, _ body: String) { responses.append((prefix, .success(Data(body.utf8)))) }
}

private func makeApp(_ t: FixtureTree, _ rel: String, _ info: [String: Any], receipt: Bool = false) -> URL {
    let u = t.dir(rel)
    t.dir("\(rel)/Contents/MacOS")
    try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: u.appendingPathComponent("Contents/Info.plist"))
    if receipt { t.file("\(rel)/Contents/_MASReceipt/receipt", bytes: 10) }
    return u
}

private func record(_ url: URL, _ id: String, short: String?, build: String? = nil, store: AppStore = .other,
                    feed: URL? = nil) -> AppRecord {
    AppRecord(url: url, bundleID: id, name: url.lastPathComponent, version: short, build: build, store: store, feedURL: feed)
}

private let os26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)

private let appcastV12 = """
<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<item><title>1.2</title><pubDate>Tue, 20 Oct 2026 10:00:00 +0000</pubDate><sparkle:version>120</sparkle:version>
<sparkle:shortVersionString>1.2</sparkle:shortVersionString><sparkle:releaseNotesLink>https://foo.example/notes</sparkle:releaseNotesLink>
<enclosure url="https://foo.example/Foo-1.2.zip" length="5000000"/></item>
</channel></rss>
"""

private func lookup(_ id: String, version: String, kind: String = "mac-software", minOS: String = "14.0") -> String {
    """
    {"resultCount":1,"results":[{"bundleId":"\(id)","kind":"\(kind)","version":"\(version)",
    "currentVersionReleaseDate":"2026-04-22T07:00:00Z","releaseNotes":"Correções","fileSizeBytes":"731861599",
    "trackId":682658836,"trackViewUrl":"https://apps.apple.com/br/app/garageband/id682658836?mt=12","minimumOsVersion":"\(minOS)"}]}
    """
}

private let casks = """
[{"token":"foo","name":["Foo"],"version":"1.1,abc","artifacts":[{"app":["Foo.app"]}],"auto_updates":null,"homepage":"https://foo.example","deprecated":false,"disabled":false},
 {"token":"bar","name":["Bar"],"version":"2.0","artifacts":[{"app":["Bar.app"]}],"homepage":"https://bar.example"},
 {"token":"chrome","name":["Chrome"],"version":"200.0","artifacts":[{"app":["Chrome.app"]}],"auto_updates":true},
 {"token":"latest-app","version":"latest","artifacts":[{"app":["Latest.app"]}]},
 {"token":"dup-a","version":"9.0","artifacts":[{"app":["Dup.app"]}]},
 {"token":"dup-b","version":"9.0","artifacts":[{"app":[{"target":"Dup.app"}]}]}]
"""

@Suite struct UpdateSourcesTests {
    @Test func sparkleUpdateFound() async {
        let t = FixtureTree()
        let url = makeApp(t, "Applications/Foo.app", ["CFBundleIdentifier": "com.foo", "CFBundleVersion": "100",
                                                      "CFBundleShortVersionString": "1.0", "SUFeedURL": "https://foo.example/appcast.xml"])
        let f = FakeFetcher()
        f.on("https://foo.example/appcast.xml", appcastV12)
        let app = record(url, "com.foo", short: "1.0", build: "100", feed: URL(string: "https://foo.example/appcast.xml"))
        let v = await SparkleSource(home: t.url("Users/me"), systemVersion: os26).check([app], fetcher: f)
        guard case .update(let u) = v[app.id] else { Issue.record("sem atualização: \(String(describing: v[app.id]))"); return }
        #expect(u.source == .sparkle)
        #expect(u.installedVersion == "1.0")
        #expect(u.availableVersion == "1.2")
        #expect(u.size == 5_000_000)
        #expect(u.action == .openApp(url, notes: URL(string: "https://foo.example/notes")))
        #expect(u.downloadURL == URL(string: "https://foo.example/Foo-1.2.zip"))
    }

    @Test func sparkleFeedFromPreferencesWins() async {
        let t = FixtureTree()
        let url = makeApp(t, "Applications/Foo.app", ["CFBundleIdentifier": "com.foo", "CFBundleVersion": "100",
                                                      "SUFeedURL": "https://old.example/appcast.xml"])
        let prefs = t.url("Users/me/Library/Preferences/com.foo.plist")
        try? FileManager.default.createDirectory(at: prefs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! PropertyListSerialization.data(fromPropertyList: ["SUFeedURL": "https://foo.example/appcast.xml"], format: .xml, options: 0).write(to: prefs)
        let f = FakeFetcher()
        f.on("https://foo.example/appcast.xml", appcastV12)
        let app = record(url, "com.foo", short: "1.0", build: "100", feed: URL(string: "https://old.example/appcast.xml"))
        _ = await SparkleSource(home: t.url("Users/me"), systemVersion: os26).check([app], fetcher: f)
        #expect(f.requested == [URL(string: "https://foo.example/appcast.xml")!])
    }

    @Test func appStoreLookup() async {
        let t = FixtureTree()
        let url = makeApp(t, "Applications/GarageBand.app", ["CFBundleIdentifier": "com.apple.garageband10",
                                                             "CFBundleShortVersionString": "10.4.13"], receipt: true)
        let app = record(url, "com.apple.garageband10", short: "10.4.13", store: .appStore)
        let f = FakeFetcher()
        f.on("https://itunes.apple.com/lookup", lookup("com.apple.garageband10", version: "10.4.14"))
        let v = await AppStoreSource(country: "br", systemVersion: os26).check([app], fetcher: f)
        #expect(f.requested.map(\.absoluteString) == ["https://itunes.apple.com/lookup?bundleId=com.apple.garageband10&entity=macSoftware&country=br"])
        guard case .update(let u) = v[app.id] else { Issue.record("sem atualização"); return }
        #expect(u.availableVersion == "10.4.14")
        #expect(u.size == 731_861_599)
        #expect(u.releaseDate == ISO8601DateFormatter().date(from: "2026-04-22T07:00:00Z"))
        #expect(u.action == .openAppStore(URL(string: "macappstore://apps.apple.com/app/id682658836")!,
                                          fallback: URL(string: "https://apps.apple.com/br/app/garageband/id682658836?mt=12")))
    }

    @Test func appStoreRejectsIOSKindSameVersionAndTooNewOS() async {
        let t = FixtureTree()
        let url = makeApp(t, "Applications/W.app", ["CFBundleIdentifier": "net.w"], receipt: true)
        let app = record(url, "net.w", short: "1.0", store: .appStore)
        for (body, expected) in [(lookup("net.w", version: "2.0", kind: "software"), "unknown"),
                                 (lookup("net.w", version: "1.0"), "current"),
                                 (lookup("net.w", version: "2.0", minOS: "99.0"), "current")] {
            let f = FakeFetcher()
            f.on("https://itunes.apple.com/lookup?bundleId=net.w&entity=macSoftware&country=br", body)
            f.on("https://itunes.apple.com/lookup?bundleId=net.w&entity=macSoftware&country=us", #"{"resultCount":0,"results":[]}"#)
            let v = await AppStoreSource(country: "br", systemVersion: os26).check([app], fetcher: f)
            #expect(v[app.id]?.label == expected)
        }
    }

    @Test func homebrewOnlyForCaskroomOrSourcelessApps() async {
        let t = FixtureTree()
        let foo = record(makeApp(t, "Applications/Foo.app", ["CFBundleIdentifier": "com.foo", "CFBundleShortVersionString": "1.0"]),
                         "com.foo", short: "1.0")
        let bar = record(makeApp(t, "Applications/Bar.app", ["CFBundleIdentifier": "com.bar", "CFBundleShortVersionString": "1.0"]),
                         "com.bar", short: "1.0")
        t.dir("opt/homebrew/Caskroom/foo/1.0,abc")
        let f = FakeFetcher()
        f.on("https://formulae.brew.sh/api/cask.json", casks)
        let src = HomebrewSource(caskrooms: [t.url("opt/homebrew/Caskroom")], cacheDir: nil)
        let (v, room) = await src.checkDetailed([foo, bar], fetcher: f)
        guard case .update(let u) = v[foo.id] else { Issue.record("foo sem atualização"); return }
        #expect(u.action == .copyCommand("brew upgrade --cask foo", homepage: URL(string: "https://foo.example")))
        #expect(u.availableVersion == "1.1")
        #expect(room == [foo.id])
        guard case .update = v[bar.id] else { Issue.record("bar (sem outra fonte) deveria comparar pela versão curta"); return }
    }

    @Test func homebrewSkipsAutoUpdatesLatestAndAmbiguous() async {
        let t = FixtureTree()
        let apps = ["Chrome", "Latest", "Dup"].map {
            record(makeApp(t, "Applications/\($0).app", ["CFBundleIdentifier": "com.\($0)", "CFBundleShortVersionString": "1.0"]),
                   "com.\($0)", short: "1.0")
        }
        let f = FakeFetcher()
        f.on("https://formulae.brew.sh/api/cask.json", casks)
        let v = await HomebrewSource(caskrooms: [], cacheDir: nil).check(apps, fetcher: f)
        for a in apps { #expect(v[a.id] == nil, "\(a.name)") }
    }

    @Test func homebrewCatalogNotSentApps() async {
        let t = FixtureTree()
        let foo = record(makeApp(t, "Applications/Foo.app", ["CFBundleIdentifier": "com.foo"]), "com.foo", short: "1.0")
        let f = FakeFetcher()
        f.on("https://formulae.brew.sh/api/cask.json", casks)
        _ = await HomebrewSource(caskrooms: [], cacheDir: nil).check([foo], fetcher: f)
        #expect(f.requested.allSatisfy { !$0.absoluteString.contains("com.foo") && $0.query == nil })
    }

    @Test func macOSUpdateOpensSettings() async {
        let t = FixtureTree()
        let plist = t.url("Library/Preferences/com.apple.SoftwareUpdate.plist")
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dict: [String: Any] = ["LastSuccessfulDate": Date(), "RecommendedUpdates": [
            ["Display Name": "macOS Tahoe 26.7.1", "Display Version": "26.7.1", "Identifier": "MSU_UPDATE_25H_patch_26.7.1",
             "Product Key": "MSU_UPDATE_25H_patch_26.7.1", "MobileSoftwareUpdate": true],
            ["Display Name": "macOS 27", "Display Version": "27.0.1", "Identifier": "MSU_UPDATE_26A_major", "Product Key": "MSU_MAJOR",
             "MobileSoftwareUpdate": true]]]
        try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: plist)
        let cmds = HelperFakeCommands()
        let updates = await MacOSUpdateSource(plist: plist, systemVersion: os26, commands: cmds).updates(now: Date())
        #expect(updates.count == 2)
        #expect(updates.allSatisfy { $0.action == .openSoftwareUpdate && $0.source == .macOS })
        #expect(updates.first { $0.availableVersion == "27.0.1" }?.isMajor == true)
        #expect(cmds.calls.isEmpty) // plist recente: não roda softwareupdate
    }

    @Test func macOSStalePlistRunsSoftwareUpdateForSizes() async {
        let t = FixtureTree()
        let plist = t.url("Library/Preferences/com.apple.SoftwareUpdate.plist")
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dict: [String: Any] = ["LastSuccessfulDate": Date(timeIntervalSinceNow: -3 * 86_400), "RecommendedUpdates": [
            ["Display Name": "macOS Tahoe 26.7.1", "Display Version": "26.7.1", "Product Key": "K1", "MobileSoftwareUpdate": true]]]
        try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: plist)
        let cmds = HelperFakeCommands()
        cmds.responses["--list"] = (0, "Software Update found the following new or updated software:\n* Label: macOS Tahoe 26.7.1-25H123\n\tTitle: macOS Tahoe 26.7.1, Version: 26.7.1, Size: 2048KiB, Recommended: YES, Action: restart,\n")
        let updates = await MacOSUpdateSource(plist: plist, systemVersion: os26, commands: cmds).updates(now: Date())
        #expect(cmds.calls == [["/usr/sbin/softwareupdate", "--list"]])
        #expect(updates.first?.size == Int64(2_097_152))
    }

    // MARK: - UpdateChecker

    @Test func offlineFlag() async {
        let t = FixtureTree()
        let url = makeApp(t, "Applications/Foo.app", ["CFBundleIdentifier": "com.foo", "CFBundleVersion": "1"])
        let app = record(url, "com.foo", short: "1.0", build: "1", feed: URL(string: "https://foo.example/appcast.xml"))
        let checker = UpdateChecker(sources: [SparkleSource(home: t.url("Users/me"), systemVersion: os26),
                                              HomebrewSource(caskrooms: [], cacheDir: nil)],
                                    macOS: nil, fetcher: FakeFetcher())
        let r = await checker.check([app])
        #expect(r.offline)
        #expect(r.updates.isEmpty)
    }

    @Test func timeoutDoesNotBlock() async {
        let t = FixtureTree()
        let slow = record(makeApp(t, "Applications/Foo.app", ["CFBundleIdentifier": "com.foo", "CFBundleVersion": "100"]),
                          "com.foo", short: "1.0", build: "100", feed: URL(string: "https://foo.example/appcast.xml"))
        let f = FakeFetcher()
        f.on("https://foo.example/appcast.xml", appcastV12)
        f.delay = .seconds(5)
        let checker = UpdateChecker(sources: [SparkleSource(home: t.url("Users/me"), systemVersion: os26)], macOS: nil,
                                    fetcher: f, requestTimeout: .milliseconds(200), totalTimeout: .seconds(1))
        let start = ContinuousClock.now
        _ = await checker.check([slow])
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func priorityAppStoreOnlyAndFeedBeforeHomebrew() async {
        let t = FixtureTree()
        // App da loja com feed e cask: só a App Store conta.
        let mas = record(makeApp(t, "Applications/Foo.app", ["CFBundleIdentifier": "com.foo", "CFBundleVersion": "100",
                                                             "CFBundleShortVersionString": "1.0"], receipt: true),
                         "com.foo", short: "1.0", build: "100", store: .appStore, feed: URL(string: "https://foo.example/appcast.xml"))
        // App com feed em dia e cask mais novo: o feed decide (em dia).
        let bar = record(makeApp(t, "Applications/Bar.app", ["CFBundleIdentifier": "com.bar", "CFBundleVersion": "120",
                                                             "CFBundleShortVersionString": "1.0"]),
                         "com.bar", short: "1.0", build: "120", feed: URL(string: "https://foo.example/appcast.xml"))
        let f = FakeFetcher()
        f.on("https://foo.example/appcast.xml", appcastV12)
        f.on("https://formulae.brew.sh/api/cask.json", casks)
        f.on("https://itunes.apple.com/lookup", lookup("com.foo", version: "1.0"))
        let checker = UpdateChecker(sources: [AppStoreSource(country: "br", systemVersion: os26),
                                              SparkleSource(home: t.url("Users/me"), systemVersion: os26),
                                              HomebrewSource(caskrooms: [], cacheDir: nil)],
                                    macOS: nil, fetcher: f)
        let r = await checker.check([mas, bar])
        #expect(r.updates.isEmpty)
        #expect(!r.offline)
    }

    @Test func excludesSelfAndProtected() async {
        let t = FixtureTree()
        let me = AppRecord(url: makeApp(t, "Applications/CleanYourMac.app", ["CFBundleIdentifier": "io.github.guigx7.CleanYourMac"]),
                           bundleID: "io.github.guigx7.CleanYourMac", name: "CleanYourMac.app", version: "0.1", isSelf: true)
        let f = FakeFetcher()
        let r = await UpdateChecker(sources: [AppStoreSource(country: "br", systemVersion: os26)], macOS: nil, fetcher: f).check([me])
        #expect(r.updates.isEmpty)
        #expect(f.requested.isEmpty)
    }
}

extension UpdateVerdict {
    var label: String {
        switch self {
        case .update: "update"
        case .current: "current"
        case .unknown: "unknown"
        }
    }
}
