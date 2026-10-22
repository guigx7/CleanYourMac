import Testing
import Foundation
@testable import CleanYourMacCore

/// Registra as chamadas e responde com um status/saída por subcomando.
final class HelperFakeCommands: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    var responses: [String: (Int32, String)] = [:]
    /// Primeiro argumento → simula tempo esgotado (só na chamada com tempo-limite).
    var timeouts: Set<String> = []

    func run(_ executable: String, _ arguments: [String], timeout: Duration) -> (status: Int32, output: String)? {
        if timeouts.contains(arguments.first ?? "") {
            lock.withLock { calls.append([executable] + arguments) }
            return nil
        }
        return run(executable, arguments)
    }

    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        lock.lock(); defer { lock.unlock() }
        calls.append([executable] + arguments)
        let key = arguments.first ?? ""
        let r = responses[key] ?? (0, "")
        return (r.0, r.1)
    }
}

private func plist(_ t: FixtureTree, _ rel: String, _ dict: [String: Any]) -> URL {
    let url = t.url(rel)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    try! data.write(to: url)
    return url
}

private func appsExecutor(_ t: FixtureTree, commands: HelperFakeCommands = HelperFakeCommands(),
                          allowed: [String]? = nil) -> HelperExecutor {
    let home = t.url("Users/me").path
    return HelperExecutor(isAdmin: { _ in true }, allowedPrefixes: allowed ?? [t.url("Library").path, t.url("Users").path],
                   trashPrefixes: [t.url("Library/Application Support").path, t.url("Library/LaunchDaemons").path, t.url("Users").path],
                   launchdFolders: [t.url("Library/LaunchDaemons").path, t.url("Library/LaunchAgents").path],
                   commands: commands,
                   homeOf: { _ in home }, appRoots: [t.url("Applications").path])
}

// MARK: - trash

@Test func helperApps_trashMovesIntoUserTrashWithUniqueName() throws {
    let t = FixtureTree()
    let a = t.file("Library/Application Support/com.example.a/x", bytes: 10)
    let b = t.file("Library/Application Support/com.example.b/x", bytes: 10)
    t.dir("Users/me")
    let e = appsExecutor(t)
    #expect(e.run([.trash(a, owner: "com.example.a"), .trash(b, owner: "com.example.b")], requester: getuid()) == [.ok, .ok])
    #expect(!FileManager.default.fileExists(atPath: a.path))
    #expect(FileManager.default.fileExists(atPath: t.url("Users/me/.Trash/x").path))
    #expect(FileManager.default.fileExists(atPath: t.url("Users/me/.Trash/x 2").path))
    let owner = try FileManager.default.attributesOfItem(atPath: t.url("Users/me/.Trash/x 2").path)[.ownerAccountID] as? NSNumber
    #expect(owner?.uint32Value == getuid())
}

@Test func helperApps_trashRefusesOutsidePrefixesVitalAndOtherUsers() {
    let t = FixtureTree()
    let etc = t.file("etc/hosts", bytes: 10)
    let other = t.file("Users/other/Library/f", bytes: 10)
    let mine = t.file("Users/me/Library/Caches/com.example.a", bytes: 10)
    t.dir("Library/Application Support")
    let e = appsExecutor(t)
    #expect(e.run([.trash(etc, owner: "com.example.a")], requester: getuid()) == [.refused])
    #expect(e.run([.trash(t.url("Library/Application Support"), owner: "com.example.a")], requester: getuid()) == [.refused])
    #expect(e.run([.trash(other, owner: "com.example.a")], requester: getuid()) == [.refused])
    #expect(e.run([.trash(mine, owner: "com.example.a")], requester: getuid()) == [.ok])
    #expect(FileManager.default.fileExists(atPath: etc.path))
    #expect(FileManager.default.fileExists(atPath: other.path))
}

@Test func helperApps_trashNeverThroughSymlinkedParent() {
    let t = FixtureTree()
    let victim = t.file("outside/victim", bytes: 10)
    t.dir("Library/Application Support")
    t.symlink("Library/Application Support/link", to: t.url("outside"))
    let e = appsExecutor(t)
    #expect(e.run([.trash(t.url("Library/Application Support/link/victim"), owner: "com.example.a")], requester: getuid()) == [.refused])
    #expect(FileManager.default.fileExists(atPath: victim.path))
}

@Test func helperApps_refusesAppleOrMalformedOwner() {
    let t = FixtureTree()
    let f = t.file("Library/Application Support/com.example.a/x", bytes: 10)
    let e = appsExecutor(t)
    #expect(e.run([.trash(f, owner: "com.apple.Safari")], requester: getuid()) == [.refused])
    #expect(e.run([.trash(f, owner: "")], requester: getuid()) == [.refused])
    #expect(e.run([.trash(f, owner: "com.x;rm")], requester: getuid()) == [.refused])
}

@Test func helperApps_trashRefusesSymlinkLastComponent() {
    let t = FixtureTree()
    t.dir("Users/me")
    let victim = t.file("Library/PrivilegedHelperTools/victim", bytes: 10)
    t.dir("Library/Application Support")
    t.symlink("Library/Application Support/com.example.a", to: victim.deletingLastPathComponent())
    #expect(appsExecutor(t).run([.trash(t.url("Library/Application Support/com.example.a"), owner: "com.example.a")], requester: getuid()) == [.refused])
    #expect(FileManager.default.fileExists(atPath: victim.path))
}

@Test func helperApps_trashRefusesSymlinkedTrashFolder() {
    let t = FixtureTree()
    let f = t.file("Library/Application Support/com.example.a/x", bytes: 10)
    t.dir("Users/me")
    t.dir("elsewhere")
    t.symlink("Users/me/.Trash", to: t.url("elsewhere"))
    #expect(appsExecutor(t).run([.trash(f.deletingLastPathComponent(), owner: "com.example.a")], requester: getuid()) == [.refused])
    #expect(FileManager.default.fileExists(atPath: f.path))
}

@Test func helperApps_trashUsesTrashPrefixesNotRemovePrefixes() {
    let t = FixtureTree()
    t.dir("Users/me")
    let f = t.file("Library/Application Support/com.example.a/x", bytes: 10)
    // Prefixos de "remove" estreitos (como em produção): `trash` usa os próprios.
    let e = appsExecutor(t, allowed: [t.url("Library/Caches").path])
    #expect(e.run([.trash(f.deletingLastPathComponent(), owner: "com.example.a")], requester: getuid()) == [.ok])
}

@Test func helperApps_trashRequiresLinkToOwnerAndNeverApple() {
    let t = FixtureTree()
    t.dir("Users/me")
    AppFixtureLite.app(t, "Applications/Foo.app", bundleID: "com.example.a", name: "Foo")
    let other = t.file("Library/Application Support/com.other.x/d", bytes: 10)
    let apple = t.file("Library/LaunchDaemons/com.apple.thing.plist", bytes: 10)
    let byName = t.file("Library/Application Support/Foo/d", bytes: 10)
    let byPrefix = t.file("Library/Application Support/com.example.a.helper/d", bytes: 10)
    let lookalike = t.file("Library/Application Support/com.example.ab/d", bytes: 10)
    let e = appsExecutor(t)
    #expect(e.run([.trash(other.deletingLastPathComponent(), owner: "com.example.a")], requester: getuid()) == [.refused])
    #expect(e.run([.trash(apple, owner: "com.example.a")], requester: getuid()) == [.refused])
    #expect(e.run([.trash(lookalike.deletingLastPathComponent(), owner: "com.example.a")], requester: getuid()) == [.refused])
    #expect(e.run([.trash(byName.deletingLastPathComponent(), owner: "com.example.a")], requester: getuid()) == [.ok])
    #expect(e.run([.trash(byPrefix.deletingLastPathComponent(), owner: "com.example.a")], requester: getuid()) == [.ok])
}

@Test func helperApps_trashProtectsRequesterHomeFolders() {
    let t = FixtureTree()
    t.dir("Users/me/Library/Caches")
    t.dir("Users/me/Documents")
    let e = appsExecutor(t)
    for rel in ["Users/me/Library", "Users/me/Documents", "Users/me/Library/Caches", "Users/me"] {
        #expect(e.run([.trash(t.url(rel), owner: "com.example.a")], requester: getuid()) == [.refused], "\(rel)")
    }
}

@Test func helperApps_bootoutAcceptsAssociationAndPrivilegedHelperWithBoundary() {
    let t = FixtureTree()
    AppFixtureLite.app(t, "Applications/Docker.app", bundleID: "com.docker.docker", name: "Docker",
                       extra: ["SMPrivilegedExecutables": ["com.docker.vmnetd": "anchor apple"]])
    let assoc = plist(t, "Library/LaunchAgents/org.other.agent.plist", ["Label": "org.other.agent", "AssociatedBundleIdentifiers": ["com.docker.docker"]])
    let helper = plist(t, "Library/LaunchDaemons/com.docker.vmnetd.plist", ["Label": "com.docker.vmnetd"])
    let lookalike = plist(t, "Library/LaunchDaemons/com.docker.dockerx.plist", ["Label": "com.docker.dockerx"])
    let e = appsExecutor(t)
    #expect(e.run([.launchdBootout(plist: assoc, owner: "com.docker.docker")], requester: 501) == [.ok])
    #expect(e.run([.launchdBootout(plist: helper, owner: "com.docker.docker")], requester: 501) == [.ok])
    #expect(e.run([.launchdBootout(plist: lookalike, owner: "com.docker.docker")], requester: 501) == [.refused])
}

/// App mínimo para os testes do helper (o helper lê o Info.plist como root).
enum AppFixtureLite {
    static func app(_ t: FixtureTree, _ rel: String, bundleID: String, name: String, extra: [String: Any] = [:]) {
        let u = t.dir("\(rel)/Contents")
        var info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name]
        info.merge(extra) { $1 }
        try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: u.appendingPathComponent("Info.plist"))
    }
}

// MARK: - launchdBootout

@Test func helperApps_bootoutDaemonAndAgentWithDomainFromFolder() {
    let t = FixtureTree()
    let daemon = plist(t, "Library/LaunchDaemons/com.example.foo.helper.plist", ["Label": "com.example.foo.helper", "Program": "/x"])
    let agent = plist(t, "Library/LaunchAgents/com.example.foo.agent.plist", ["Label": "com.example.foo.agent", "Program": "/x"])
    let cmds = HelperFakeCommands()
    let e = appsExecutor(t, commands: cmds)
    #expect(e.run([.launchdBootout(plist: daemon, owner: "com.example.foo"), .launchdBootout(plist: agent, owner: "com.example.foo")],
                  requester: 501) == [.ok, .ok])
    #expect(cmds.calls == [["/bin/launchctl", "bootout", "system/com.example.foo.helper"],
                           ["/bin/launchctl", "bootout", "gui/501/com.example.foo.agent"]])
}

@Test func helperApps_bootoutLinkByProgramInsideOwnerApp() {
    let t = FixtureTree()
    let app = t.app("Applications/Foo.app", bundleID: "com.vendor.foo")
    let p = plist(t, "Library/LaunchDaemons/org.other.svc.plist",
                  ["Label": "org.other.svc", "ProgramArguments": [app.appendingPathComponent("Contents/MacOS/Foo").path, "--daemon"]])
    let cmds = HelperFakeCommands()
    let e = appsExecutor(t, commands: cmds)
    #expect(e.run([.launchdBootout(plist: p, owner: "com.vendor.foo")], requester: 501) == [.ok])
    #expect(e.run([.launchdBootout(plist: p, owner: "com.vendor.bar")], requester: 501) == [.refused])
}

@Test func helperApps_bootoutRefusals() {
    let t = FixtureTree()
    let apple = plist(t, "Library/LaunchDaemons/com.example.x.plist", ["Label": "com.apple.evil"])
    let appleName = plist(t, "Library/LaunchDaemons/com.apple.y.plist", ["Label": "com.example.y"])
    let outside = plist(t, "Library/Preferences/com.example.z.plist", ["Label": "com.example.z"])
    let real = plist(t, "Library/elsewhere/com.example.w.plist", ["Label": "com.example.w"])
    let link = t.symlink("Library/LaunchDaemons/com.example.w.plist", to: real)
    let noLabel = plist(t, "Library/LaunchDaemons/com.example.n.plist", ["Program": "/x"])
    let cmds = HelperFakeCommands()
    let e = appsExecutor(t, commands: cmds)
    for (p, owner) in [(apple, "com.example.x"), (appleName, "com.example.y"), (outside, "com.example.z"),
                       (link, "com.example.w"), (noLabel, "com.example.n")] {
        #expect(e.run([.launchdBootout(plist: p, owner: owner)], requester: 501) == [.refused])
    }
    #expect(cmds.calls.isEmpty)
}

@Test func helperApps_bootoutNotLoadedCountsAsSuccess() {
    let t = FixtureTree()
    let p = plist(t, "Library/LaunchDaemons/com.example.foo.plist", ["Label": "com.example.foo"])
    let cmds = HelperFakeCommands()
    let e = appsExecutor(t, commands: cmds)
    cmds.responses["bootout"] = (3, "No such process")
    #expect(e.run([.launchdBootout(plist: p, owner: "com.example.foo")], requester: 501) == [.ok])
    cmds.responses["bootout"] = (5, "Input/output error")
    #expect(e.run([.launchdBootout(plist: p, owner: "com.example.foo")], requester: 501) == [.failed("launchctl bootout: 5")])
}

// MARK: - forgetPackage

@Test func helperApps_forgetPackageRules() {
    let t = FixtureTree()
    let cmds = HelperFakeCommands()
    cmds.responses["--pkg-info"] = (0, "package-id: com.example.pkg\nversion: 1\nvolume: /\nlocation: /\n")
    let e = appsExecutor(t, commands: cmds)
    #expect(e.run([.forgetPackage("com.apple.pkg.Safari", owner: "com.example.app")], requester: 501) == [.refused])
    #expect(e.run([.forgetPackage("com.ex/ample", owner: "com.example.app")], requester: 501) == [.refused])
    #expect(e.run([.forgetPackage("com.example.pkg; rm", owner: "com.example.app")], requester: 501) == [.refused])
    #expect(e.run([.forgetPackage("com..example", owner: "com.example.app")], requester: 501) == [.refused])
    #expect(e.run([.forgetPackage("org.other.pkg", owner: "com.example.app")], requester: 501) == [.refused])
    #expect(cmds.calls.isEmpty)
    #expect(e.run([.forgetPackage("com.example.pkg", owner: "com.example.app")], requester: 501) == [.ok])
    #expect(cmds.calls == [["/usr/sbin/pkgutil", "--pkg-info", "com.example.pkg"], ["/usr/sbin/pkgutil", "--forget", "com.example.pkg"]])
}

@Test func helperApps_forgetPackageNeedsReceiptOnBootVolume() {
    let t = FixtureTree()
    let cmds = HelperFakeCommands()
    let e = appsExecutor(t, commands: cmds)
    cmds.responses["--pkg-info"] = (1, "No receipt")
    #expect(e.run([.forgetPackage("com.example.pkg", owner: "com.example.app")], requester: 501) == [.failed("receipt not found")])
    cmds.responses["--pkg-info"] = (0, "volume: /Volumes/Ext\n")
    #expect(e.run([.forgetPackage("com.example.pkg", owner: "com.example.app")], requester: 501) == [.refused])
}

@Test func helperApps_requestRoundTripsAsJSON() throws {
    let req = HelperRequest.run([.trash(URL(fileURLWithPath: "/Applications/A.app"), owner: "com.a"),
                                 .launchdBootout(plist: URL(fileURLWithPath: "/Library/LaunchDaemons/com.a.plist"), owner: "com.a"),
                                 .forgetPackage("com.a.pkg", owner: "com.a")])
    #expect(try JSONDecoder().decode(HelperRequest.self, from: JSONEncoder().encode(req)) == req)
    #expect(HelperConstants.version == 3)
}
