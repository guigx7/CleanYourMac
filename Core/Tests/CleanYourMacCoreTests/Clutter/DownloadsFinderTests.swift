import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct DownloadsFinderTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func quarantine(_ url: URL, agent: String, daysAgo: Double) {
        let ts = String(Int(now.timeIntervalSince1970 - daysAgo * 86_400), radix: 16)
        let value = "0083;\(ts);\(agent);ABCD-1234"
        _ = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
    }

    @Test func groupedByAppFromQuarantine() throws {
        let t = FixtureTree()
        let a = t.file("Users/me/Downloads/a.zip", bytes: 500_000); quarantine(a, agent: "Google Chrome", daysAgo: 40)
        let b = t.file("Users/me/Downloads/b.dmg", bytes: 300_000); quarantine(b, agent: "Chrome", daysAgo: 2)
        let c = t.file("Users/me/Downloads/c.pdf", bytes: 100_000); quarantine(c, agent: "Safari", daysAgo: 1)
        let d = t.file("Users/me/Downloads/d.png", bytes: 100_000); quarantine(d, agent: "Preview", daysAgo: 1)
        t.file("Users/me/Downloads/semmarca.txt", bytes: 10)
        let e = t.file("Users/me/Downloads/sub/inner.zip", bytes: 10); quarantine(e, agent: "Google Chrome", daysAgo: 1)
        let groups = DownloadsFinder(home: t.url("Users/me")).groups(now: now)
        #expect(groups.map(\.app) == [.chrome, .safari])
        #expect(groups[0].files.map(\.url.lastPathComponent) == ["a.zip", "b.dmg"])
        #expect(groups[0].totalSize == 800_000)
        // Marcação automática: baixados há mais de 30 dias.
        #expect(groups[0].autoselected.map(\.url.lastPathComponent) == ["a.zip"])
    }

    @Test func folderDownloadsCountAsOneItem() throws {
        let t = FixtureTree()
        let dir = t.dir("Users/me/Downloads/Pasta")
        t.file("Users/me/Downloads/Pasta/x.bin", bytes: 200_000)
        quarantine(dir, agent: "Slack", daysAgo: 5)
        let groups = DownloadsFinder(home: t.url("Users/me")).groups(now: now)
        #expect(groups.map(\.app) == [.slack])
        #expect(groups[0].files.first?.size ?? 0 >= 200_000)
    }

    @Test func parsesAgentAndDate() {
        let q = DownloadsFinder.parseQuarantine("0081;65f1a2b3;Google Chrome;UUID")
        #expect(q?.agent == "Google Chrome")
        #expect(q?.date == Date(timeIntervalSince1970: TimeInterval(0x65f1a2b3)))
        #expect(DownloadsFinder.App(agent: "Chrome") == .chrome)
        #expect(DownloadsFinder.App(agent: "Preview") == nil)
    }
}
