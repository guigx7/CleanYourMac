import Testing
import Foundation
@testable import CleanYourMacCore

private func plist(_ t: FixtureTree, _ rel: String, _ dict: [String: Any]) -> URL {
    let url = t.url(rel)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: url)
    return url
}

private func executor(_ t: FixtureTree, _ cmds: HelperFakeCommands) -> HelperExecutor {
    let home = t.url("Users/me").path
    return HelperExecutor(allowedPrefixes: [t.url("Library").path], trashPrefixes: [t.url("Library").path],
                   launchdFolders: [t.url("Library/LaunchDaemons").path, t.url("Library/LaunchAgents").path],
                   commands: cmds, homeOf: { _ in home }, appRoots: [t.url("Applications").path])
}

@Test func launchdDisableAndEnableUseLabelDomain() {
    let t = FixtureTree()
    let daemon = plist(t, "Library/LaunchDaemons/com.example.svc.plist", ["Label": "com.example.svc", "Program": "/x"])
    let agent = plist(t, "Library/LaunchAgents/com.example.agent.plist", ["Label": "com.example.agent", "Program": "/x"])
    let cmds = HelperFakeCommands()
    let e = executor(t, cmds)
    #expect(e.run([.launchdDisable(plist: daemon, owner: "com.example.svc"), .launchdDisable(plist: agent, owner: "com.example.agent")],
                  requester: 501) == [.ok, .ok])
    #expect(cmds.calls == [["/bin/launchctl", "disable", "system/com.example.svc"],
                           ["/bin/launchctl", "bootout", "system/com.example.svc"],
                           ["/bin/launchctl", "disable", "gui/501/com.example.agent"],
                           ["/bin/launchctl", "bootout", "gui/501/com.example.agent"]])
    let cmds2 = HelperFakeCommands()
    #expect(executor(t, cmds2).run([.launchdEnable(plist: daemon, owner: "com.example.svc")], requester: 501) == [.ok])
    #expect(cmds2.calls == [["/bin/launchctl", "enable", "system/com.example.svc"],
                            ["/bin/launchctl", "bootstrap", "system", PathPolicy.realPath(daemon.path)]])
}

@Test func launchdDisableFailsWhenDisableFails() {
    let t = FixtureTree()
    let daemon = plist(t, "Library/LaunchDaemons/com.example.svc.plist", ["Label": "com.example.svc"])
    let cmds = HelperFakeCommands()
    cmds.responses["disable"] = (1, "")
    #expect(executor(t, cmds).run([.launchdDisable(plist: daemon, owner: "com.example.svc")], requester: 501) == [.failed("launchctl disable: 1")])
    #expect(cmds.calls.count == 1)
}

@Test func launchdDisableRefusesSymlinkAndApple() {
    let t = FixtureTree()
    let apple = plist(t, "Library/LaunchDaemons/com.example.x.plist", ["Label": "com.apple.evil"])
    let appleName = plist(t, "Library/LaunchDaemons/com.apple.y.plist", ["Label": "com.example.y"])
    let real = plist(t, "Library/elsewhere/com.example.w.plist", ["Label": "com.example.w"])
    let link = t.symlink("Library/LaunchDaemons/com.example.w.plist", to: real)
    let unlinked = plist(t, "Library/LaunchDaemons/com.example.v.plist", ["Label": "com.example.v"])
    let cmds = HelperFakeCommands()
    let e = executor(t, cmds)
    for (p, owner) in [(apple, "com.example.x"), (appleName, "com.example.y"), (link, "com.example.w"), (unlinked, "com.other.app")] {
        #expect(e.run([.launchdDisable(plist: p, owner: owner)], requester: 501) == [.refused])
        #expect(e.run([.launchdEnable(plist: p, owner: owner)], requester: 501) == [.refused])
    }
    #expect(cmds.calls.isEmpty)
}

@Test func maintenanceCommandsAreFixed() throws {
    let t = FixtureTree()
    let cmds = HelperFakeCommands()
    let e = executor(t, cmds)
    let all: [PrivilegedCommand] = [.maintenance(.flushDNS), .maintenance(.reindexSpotlight), .maintenance(.repairPermissions),
                                    .maintenance(.freeUpRAM), .maintenance(.periodicScripts)]
    #expect(e.run(all, requester: 501) == [.ok, .ok, .ok, .ok, .ok])
    #expect(cmds.calls == [["/usr/bin/dscacheutil", "-flushcache"], ["/usr/bin/killall", "-HUP", "mDNSResponder"],
                           ["/usr/bin/mdutil", "-E", "/"], ["/usr/sbin/diskutil", "resetUserPermissions", "/", "501"],
                           ["/usr/sbin/purge"], ["/usr/sbin/periodic", "daily", "weekly", "monthly"]])
    // Tarefas sem root não passam pelo ajudante.
    #expect(e.run([.maintenance(.speedUpMail), .maintenance(.freeUpPurgeable), .maintenance(.thinSnapshots)], requester: 501)
            == [.refused, .refused, .refused])
    // Id desconhecido não decodifica.
    let bad = Data(#"{"run":{"_0":[{"maintenance":{"_0":"rmEverything"}}]}}"#.utf8)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(HelperRequest.self, from: bad) }
}

@Test func maintenanceTimeoutFails() {
    let t = FixtureTree()
    let cmds = HelperFakeCommands()
    cmds.timeouts = ["-E"]
    #expect(executor(t, cmds).run([.maintenance(.reindexSpotlight)], requester: 501) == [.failed("timed out")])
}

@Test func systemCommandRunnerTimesOut() {
    let start = Date()
    #expect(SystemCommandRunner().run("/bin/sleep", ["5"], timeout: .milliseconds(200)) == nil)
    #expect(Date().timeIntervalSince(start) < 4)
    #expect(SystemCommandRunner().run("/bin/echo", ["oi"], timeout: .seconds(5))?.output == "oi\n")
}

@Test func helperVersionIs3() {
    #expect(HelperConstants.version == 3)
}

/// Remover um item desativado tira o "disabled" do launchd (senão uma reinstalação nunca sobe).
@Test func launchdClearDisabledOnlyWhenDisabled() {
    let t = FixtureTree()
    let daemon = plist(t, "Library/LaunchDaemons/com.example.svc.plist", ["Label": "com.example.svc"])
    let cmds = HelperFakeCommands()
    cmds.responses["print-disabled"] = (0, "\ndisabled services = {\n\t\t\"com.example.svc\" => disabled\n}\n")
    #expect(executor(t, cmds).run([.launchdClearDisabled(plist: daemon, owner: "com.example.svc")], requester: 501) == [.ok])
    #expect(cmds.calls == [["/bin/launchctl", "print-disabled", "system"], ["/bin/launchctl", "enable", "system/com.example.svc"]])
    let clean = HelperFakeCommands()
    clean.responses["print-disabled"] = (0, "disabled services = {\n}\n")
    #expect(executor(t, clean).run([.launchdClearDisabled(plist: daemon, owner: "com.example.svc")], requester: 501) == [.ok])
    #expect(clean.calls == [["/bin/launchctl", "print-disabled", "system"]])
}
