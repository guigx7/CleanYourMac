import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct TimeMachineSnapshotsTests {
    let sample = """
    Snapshots for disk /:
    com.apple.TimeMachine.2026-10-20-101500.local
    com.apple.os.update-ABCDEF
    com.apple.TimeMachine.2026-10-21-090000.local

    """

    @Test func parsesListLocalSnapshots() {
        let cmds = HelperFakeCommands()
        cmds.responses["listlocalsnapshots"] = (0, sample)
        let list = TimeMachineSnapshots(commands: cmds).list()
        #expect(list.map(\.id) == ["2026-10-20-101500", "2026-10-21-090000"])
        #expect(list.allSatisfy { $0.volume.path == "/" })
        #expect(cmds.calls == [["/usr/bin/tmutil", "listlocalsnapshots", "/"]])
    }

    @Test func deletesSelectedByDate() {
        let cmds = HelperFakeCommands()
        cmds.responses["listlocalsnapshots"] = (0, sample)
        let tm = TimeMachineSnapshots(commands: cmds)
        let gone = LocalSnapshot(id: "2026-10-01-000000", volume: URL(fileURLWithPath: "/"))
        let evil = LocalSnapshot(id: "/", volume: URL(fileURLWithPath: "/"))
        let r = tm.delete([tm.list()[0], gone, evil], dryRun: false)
        #expect(cmds.calls.filter { $0[1] == "deletelocalsnapshots" } == [["/usr/bin/tmutil", "deletelocalsnapshots", "2026-10-20-101500"]])
        #expect((try? r["2026-10-20-101500"]?.get()) != nil)
        #expect((try? r["2026-10-01-000000"]?.get()) == nil)
        #expect((try? r["/"]?.get()) == nil)
    }

    @Test func dryRunDeletesNothing() {
        let cmds = HelperFakeCommands()
        cmds.responses["listlocalsnapshots"] = (0, sample)
        let tm = TimeMachineSnapshots(commands: cmds)
        _ = tm.delete(tm.list(), dryRun: true)
        #expect(!cmds.calls.contains { $0.contains("deletelocalsnapshots") })
    }

    @Test func noSnapshotsMeansNoTile() {
        let cmds = HelperFakeCommands()
        cmds.responses["listlocalsnapshots"] = (1, "Error: something")
        #expect(TimeMachineSnapshots(commands: cmds).list().isEmpty)
        cmds.responses["listlocalsnapshots"] = (0, "Snapshots for disk /:\n")
        #expect(TimeMachineSnapshots(commands: cmds).list().isEmpty)
    }
}
