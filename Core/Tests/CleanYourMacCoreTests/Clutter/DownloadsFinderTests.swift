import Foundation
import SQLite3
import Testing
@testable import CleanYourMacCore

@Suite struct DownloadsFinderTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    /// Microssegundos desde 1601 (relógio do Chrome).
    func webkit(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 + 11_644_473_600) * 1_000_000) }

    func chromeHistory(_ t: FixtureTree, profile: String, rows: [(String, Int64, Int64, Date)]) {
        let dir = t.dir("Users/me/Library/Application Support/Google/Chrome/\(profile)")
        var db: OpaquePointer?
        sqlite3_open(dir.appendingPathComponent("History").path, &db)
        sqlite3_exec(db, "CREATE TABLE downloads (id INTEGER PRIMARY KEY, current_path TEXT, target_path TEXT, start_time INTEGER, end_time INTEGER, received_bytes INTEGER, total_bytes INTEGER, state INTEGER)", nil, nil, nil)
        for (path, received, total, date) in rows {
            sqlite3_exec(db, "INSERT INTO downloads (current_path, target_path, start_time, end_time, received_bytes, total_bytes, state) VALUES ('\(path)', '\(path)', \(webkit(date)), \(webkit(date)), \(received), \(total), 1)", nil, nil, nil)
        }
        sqlite3_close(db)
    }

    func localState(_ t: FixtureTree, profiles: [String]) {
        let url = t.url("Users/me/Library/Application Support/Google/Chrome/Local State")
        let cache = Dictionary(uniqueKeysWithValues: profiles.map { ($0, ["name": $0]) })
        try! JSONSerialization.data(withJSONObject: ["profile": ["info_cache": cache]]).write(to: url)
    }

    @Test func chromeFromHistoryOnlyExistingAndComplete() throws {
        let t = FixtureTree()
        let a = t.file("Users/me/Downloads/a.zip", bytes: 500_000)
        let b = t.file("Users/me/Desktop/b.dmg", bytes: 300_000)
        let c = t.file("Users/me/Downloads/c.part", bytes: 10)
        chromeHistory(t, profile: "Default", rows: [
            (a.path, 500_000, 500_000, now.addingTimeInterval(-40 * 86_400)),
            (b.path, 300_000, 300_000, now.addingTimeInterval(-2 * 86_400)),
            (c.path, 10, 999, now),                                   // incompleto
            ("/Users/me/Downloads/sumiu.zip", 1, 1, now),              // não existe mais
            (a.path, 500_000, 500_000, now.addingTimeInterval(-40 * 86_400)), // repetido
        ])
        chromeHistory(t, profile: "Profile 2", rows: [])
        localState(t, profiles: ["Default", "Profile 2"])
        let groups = DownloadsFinder(home: t.url("Users/me")).groups(now: now)
        #expect(groups.map(\.app) == [.chrome])
        #expect(groups[0].files.map(\.url.lastPathComponent) == ["a.zip", "b.dmg"])
        #expect(groups[0].autoselected.map(\.url.lastPathComponent) == ["a.zip"])
    }

    @Test func safariFromDownloadsPlist() throws {
        let t = FixtureTree()
        let f = t.file("Users/me/Downloads/s.pdf", bytes: 200_000)
        let plist: [String: Any] = ["DownloadHistory": [
            ["DownloadEntryPath": f.path, "DownloadEntryProgressBytesSoFar": 200_000, "DownloadEntryProgressTotalToLoad": 200_000,
             "DownloadEntryDateAddedKey": now.addingTimeInterval(-3 * 86_400)],
            ["DownloadEntryPath": "/Users/me/Downloads/half.pdf", "DownloadEntryProgressBytesSoFar": 1, "DownloadEntryProgressTotalToLoad": 9],
        ]]
        t.dir("Users/me/Library/Safari")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: t.url("Users/me/Library/Safari/Downloads.plist"))
        let groups = DownloadsFinder(home: t.url("Users/me")).groups(now: now)
        #expect(groups.map(\.app) == [.safari])
        #expect(groups[0].files.map(\.url.lastPathComponent) == ["s.pdf"])
    }

    /// Baixado de novo no mesmo caminho: vale a data mais recente. Caminhos em ~/Library ficam de fora; arquivo editado
    /// depois de baixado continua (como no CleanMyMac).
    @Test func latestDateSameSizeAndNoLibrary() throws {
        let t = FixtureTree()
        let r = t.file("Users/me/Downloads/relatorio.pdf", bytes: 200_000)
        let swapped = t.file("Users/me/Downloads/outro.pdf", bytes: 123)
        let lib = t.file("Users/me/Library/Caches/x.zip", bytes: 1000)
        chromeHistory(t, profile: "Default", rows: [
            (r.path, 200_000, 200_000, now.addingTimeInterval(-400 * 86_400)),
            (r.path, 200_000, 200_000, now.addingTimeInterval(-1 * 86_400)),
            (swapped.path, 999, 999, now.addingTimeInterval(-50 * 86_400)),
            (lib.path, 1000, 1000, now.addingTimeInterval(-50 * 86_400)),
        ])
        let groups = DownloadsFinder(home: t.url("Users/me")).groups(now: now)
        try #require(groups.count == 1)
        #expect(groups[0].files.map(\.url.lastPathComponent) == ["relatorio.pdf", "outro.pdf"])
        #expect(groups[0].autoselected.map(\.url.lastPathComponent) == ["outro.pdf"])
    }

    /// Sem leitor do histórico do Slack (formato não confirmado), a marca de quarentena não vira grupo do Slack.
    @Test func quarantineAloneIsNotADownloadGroup() throws {
        let t = FixtureTree()
        let f = t.file("Users/me/Downloads/sl.png", bytes: 100_000)
        _ = "0083;65f1a2b3;Slack;ABCD".withCString { setxattr(f.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        #expect(DownloadsFinder(home: t.url("Users/me")).groups(now: now).isEmpty)
    }

    @Test func parsers() {
        let q = DownloadsFinder.parseQuarantine("0081;65f1a2b3;Slack;UUID")
        #expect(q?.agent == "Slack")
        #expect(q?.date == Date(timeIntervalSince1970: TimeInterval(0x65f1a2b3)))
        #expect(DownloadsFinder.chromeDate(webkit(now)) == now)
    }
}
