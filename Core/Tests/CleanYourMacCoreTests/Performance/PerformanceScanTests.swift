import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct PerformanceScanTests {
    func scan(_ t: FixtureTree, facts: FakeMaintenanceFacts = FakeMaintenanceFacts(), slowFacts: Bool = false,
              login: [LoginItemEntry] = [], snapshots: String = "") -> PerformanceScan {
        let cmds = HelperFakeCommands()
        cmds.responses["listlocalsnapshots"] = (0, snapshots)
        return PerformanceScan(facts: { _ in
            if slowFacts { Thread.sleep(forTimeInterval: 0.5) }
            return facts
        }, startup: StartupItemsScanner(loginItems: FakeLoginItems(entries: login), commands: cmds,
                                        disabledRecord: DisabledLoginItemsStore(url: t.url("rec.json")), displayName: { $0.lastPathComponent }),
           snapshots: TimeMachineSnapshots(commands: cmds))
    }

    func report(_ s: PerformanceScan, _ ctx: ScanContext) async throws -> PerformanceReport? {
        var out: PerformanceReport?
        for try await e in s.run(ctx) { if case .finished(let r) = e { out = r } }
        return out
    }

    @Test func reportHasAllSections() async throws {
        let t = FixtureTree()
        let ctx = t.context()
        let warp = t.app("Applications/Warp.app", bundleID: "dev.warp.Warp-Stable")
        let p = t.url("Library/LaunchDaemons/com.example.d.plist")
        t.dir("Library/LaunchDaemons")
        try PropertyListSerialization.data(fromPropertyList: ["Label": "com.example.d"], format: .xml, options: 0).write(to: p)
        let r = try #require(try await report(scan(t, login: [LoginItemEntry(name: "Warp", url: warp)],
                                                    snapshots: "com.apple.TimeMachine.2026-10-20-101500.local\n"), ctx))
        #expect(r.tasks.map(\.id) == [.speedUpMail, .flushDNS, .freeUpPurgeable, .reindexSpotlight, .repairPermissions])
        #expect(r.loginItems.map(\.name) == ["Warp.app"])
        #expect(r.backgroundItems.map(\.name) == ["com.example.d.plist"])
        #expect(r.snapshots.map(\.id) == ["2026-10-20-101500"])
    }

    @Test func cancelStopsQuickly() async {
        let t = FixtureTree()
        let ctx = t.context()
        let s = scan(t, slowFacts: true)
        let start = Date()
        let task = Task { try await report(s, ctx) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let r = try? await task.value
        #expect(r == nil)
        #expect(Date().timeIntervalSince(start) < 1.5)
    }

    @Test func cliJsonMatchesBaselineShape() async throws {
        let t = FixtureTree()
        let r = try #require(try await report(scan(t), t.context()))
        let json = r.parityJSON()
        let baselineURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/re/parity/perf-baseline-2026-10-22.json")
        let baseline = try JSONSerialization.jsonObject(with: Data(contentsOf: baselineURL)) as! [String: Any]
        #expect(Set(json.keys) == Set(baseline.keys))
        #expect(Set((json["tiles"] as! [String: Int]).keys) == Set((baseline["tiles"] as! [String: Int]).keys))
        #expect(json["purgeable"] as? Int64 == 3_800_000_000)
        #expect(json["tasks"] as? [String] == ["speedUpMail", "flushDNS", "freeUpPurgeable", "reindexSpotlight", "repairPermissions"])
        #expect((json["tiles"] as! [String: Int])["maintenance"] == 5)
    }
}
