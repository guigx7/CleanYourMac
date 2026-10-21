import Foundation
import Testing
@testable import CleanYourMacCore

/// Lixo dentro do fixture (o FileManager mandaria para o Lixo real).
final class FixtureTrasher: Trasher, @unchecked Sendable {
    let bin: URL
    var deny: Set<String> = []
    private(set) var trashed: [URL] = []

    init(_ bin: URL) {
        self.bin = bin
        try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    }

    func trash(_ url: URL) throws {
        if deny.contains(url.path) { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(url.lastPathComponent))
        trashed.append(url)
    }
}

struct FakeRunningApps: RunningApps {
    var open: Set<String> = []
    func running(bundleIDs: Set<String>) -> [RunningApp] {
        bundleIDs.intersection(open).map { RunningApp(bundleID: $0, name: $0, pid: 1) }
    }
    func quit(_ app: RunningApp, force: Bool) async -> Bool { true }
}

/// Registra os lotes privilegiados e responde ok (ou o que for pedido).
final class RecordingPrivileged: PrivilegedRunner, @unchecked Sendable {
    private(set) var batches: [[PrivilegedCommand]] = []
    var fail = false
    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] {
        batches.append(commands)
        return commands.map { _ in fail ? .failure(CleanFailure(reason: "denied")) : .success(()) }
    }
}

private let appID = "com.example.foo|/Applications/Foo.app"

private struct Setup {
    let t = FixtureTree()
    let trasher: FixtureTrasher
    let privileged = RecordingPrivileged()
    let commands = HelperFakeCommands()
    var running = FakeRunningApps()

    init() { trasher = FixtureTrasher(t.url("Users/tester/.Trash")) }

    func engine(dryRun: Bool = false) -> CleanEngine {
        let policy = PathPolicy(allowedRoots: [t.url("Applications"), t.url("Users/tester/Library"), t.url("Library")])
        return CleanEngine(policies: [.appUninstall: policy, .appLeftovers: policy], privileged: privileged, dryRun: dryRun,
                           log: CleanupLog(directory: t.url("logs")), commands: commands,
                           runningApps: running, trasher: trasher)
    }

    func leaf(_ rel: String, _ removal: (URL) -> RemovalAction = { .moveToTrash($0) }, bundle: Bool = false,
              mode: AppItemID.Mode = .uninstall) -> JunkItem {
        let u = rel.hasSuffix(".app") ? t.app(rel, bundleID: "com.example.foo") : t.file(rel, bytes: 4096)
        let id = bundle ? AppItemID.bundle(mode: mode, appID: appID) : AppItemID.leaf(mode: mode, appID: appID, path: u.path)
        return JunkItem(id: id, group: .appUninstall, name: u.lastPathComponent, url: u, size: 4096, removal: removal(u))
    }
}

private func run(_ engine: CleanEngine, _ items: [JunkItem]) async -> CleanReport? {
    var report: CleanReport?
    for await e in engine.clean(items) { if case .completed(let r) = e { report = r } }
    return report
}

@Suite struct AppsRemovalTests {
    @Test func appItemIDsRoundTrip() {
        let leaf = AppItemID.leaf(mode: .uninstall, appID: appID, path: "/x/y")
        #expect(AppItemID.owner(of: leaf) == "com.example.foo")
        #expect(AppItemID.appID(of: leaf) == appID)
        #expect(!AppItemID.isBundle(leaf))
        #expect(AppItemID.isBundle(AppItemID.bundle(mode: .uninstall, appID: appID)))
        #expect(AppItemID.mode(of: AppItemID.leaf(mode: .reset, appID: appID, path: "/x")) == .reset)
        #expect(AppItemID.owner(of: AppItemID.leftover(bundleID: "com.gone.app", path: "/p")) == "com.gone.app")
        #expect(AppItemID.owner(of: "userCache:/x") == nil)
    }

    @Test func uninstallMovesAppAndFilesToTrash() async {
        let s = Setup()
        let prefs = s.leaf("Users/tester/Library/Preferences/com.example.foo.plist")
        let app = s.leaf("Applications/Foo.app", bundle: true)
        let report = await run(s.engine(), [app, prefs])
        #expect(report?.failed.isEmpty == true)
        #expect(s.trasher.trashed.map(\.lastPathComponent) == ["com.example.foo.plist", "Foo.app"]) // bundle por último
        #expect(!FileManager.default.fileExists(atPath: s.t.url("Applications/Foo.app").path))
        #expect(FileManager.default.fileExists(atPath: s.t.url("Users/tester/.Trash/Foo.app").path))
    }

    @Test func runningAppBlocksRemoval() async {
        var s = Setup()
        s.running = FakeRunningApps(open: ["com.example.foo"])
        let prefs = s.leaf("Users/tester/Library/Preferences/com.example.foo.plist")
        let app = s.leaf("Applications/Foo.app", bundle: true)
        let report = await run(s.engine(), [prefs, app])
        #expect(report?.failed[prefs.id] == "in use")
        #expect(report?.failed[app.id] == "in use")
        #expect(s.trasher.trashed.isEmpty)
    }

    @Test func resetProceedsWhileRunning() async {
        var s = Setup()
        s.running = FakeRunningApps(open: ["com.example.foo"])
        let prefs = s.leaf("Users/tester/Library/Preferences/com.example.foo.plist", mode: .reset)
        let report = await run(s.engine(), [prefs])
        #expect(report?.failed.isEmpty == true)
        #expect(s.trasher.trashed.count == 1)
    }

    @Test func bundleKeptWhenEarlierStepFailed() async {
        let s = Setup()
        let prefs = s.leaf("Users/tester/Library/Preferences/com.example.foo.plist")
        let app = s.leaf("Applications/Foo.app", bundle: true)
        s.trasher.deny = [prefs.url!.path]
        s.privileged.fail = true
        let report = await run(s.engine(), [app, prefs])
        #expect(report?.failed[prefs.id] == "denied")
        #expect(report?.failed[app.id] == "kept: an earlier step failed")
        #expect(FileManager.default.fileExists(atPath: s.t.url("Applications/Foo.app").path))
    }

    @Test func rootOwnedAppGoesToHelperTrash() async {
        let s = Setup()
        let support = s.leaf("Library/Application Support/Foo/data")
        let app = s.leaf("Applications/Foo.app", bundle: true)
        s.trasher.deny = [support.url!.path, app.url!.path]
        let report = await run(s.engine(), [support, app])
        #expect(report?.failed.isEmpty == true)
        let all = s.privileged.batches.flatMap { $0 }
        #expect(all == [.trash(support.url!, owner: "com.example.foo"), .trash(app.url!, owner: "com.example.foo")])
    }

    @Test func launchdUserAgentUnloadedThenTrashed() async {
        let s = Setup()
        let agent = s.leaf("Users/tester/Library/LaunchAgents/com.example.foo.agent.plist") { .unloadAndTrash(plist: $0, domain: .user) }
        let report = await run(s.engine(), [agent])
        #expect(report?.failed.isEmpty == true)
        #expect(s.commands.calls == [["/bin/launchctl", "bootout", "gui/\(getuid())", agent.url!.path]])
        #expect(s.trasher.trashed == [agent.url!])
    }

    @Test func launchdSystemDaemonGoesToHelper() async {
        let s = Setup()
        let daemon = s.leaf("Library/LaunchDaemons/com.example.foo.helper.plist") { .unloadAndTrash(plist: $0, domain: .system) }
        let report = await run(s.engine(), [daemon])
        #expect(report?.failed.isEmpty == true)
        #expect(s.privileged.batches == [[.launchdBootout(plist: daemon.url!, owner: "com.example.foo"),
                                          .trash(daemon.url!, owner: "com.example.foo")]])
        #expect(s.commands.calls.isEmpty)
    }

    @Test func receiptForgottenViaBatch() async {
        let s = Setup()
        let receipt = JunkItem(id: AppItemID.leaf(mode: .uninstall, appID: appID, path: "receipt:com.example.foo.pkg"),
                               group: .appUninstall, name: "com.example.foo.pkg", url: nil, size: 0,
                               removal: .forgetReceipt("com.example.foo.pkg"))
        let report = await run(s.engine(), [receipt])
        #expect(report?.failed.isEmpty == true)
        #expect(s.privileged.batches == [[.forgetPackage("com.example.foo.pkg", owner: "com.example.foo")]])
    }

    @Test func dryRunTouchesNothing() async {
        let s = Setup()
        let prefs = s.leaf("Users/tester/Library/Preferences/com.example.foo.plist")
        let app = s.leaf("Applications/Foo.app", bundle: true)
        let report = await run(s.engine(dryRun: true), [prefs, app])
        #expect(report?.dryRun == true)
        #expect(report?.removed.count == 2)
        #expect(s.trasher.trashed.isEmpty)
        #expect(s.privileged.batches.isEmpty)
    }

    @Test func trashOnExternalVolumeUsesVolumeTrash() async throws {
        let s = Setup()
        let image = s.t.url("vol.dmg")
        let name = "cymvol\(UInt32.random(in: 0...999_999))"
        // Com tempo-limite: o hdiutil às vezes fica preso; nesse caso o teste é pulado em vez de travar a suíte.
        func hdiutil(_ args: [String]) -> Int32 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return -1 }
            let deadline = Date().addingTimeInterval(30)
            while p.isRunning && Date() < deadline { usleep(100_000) }
            if p.isRunning { p.terminate(); return -2 }
            return p.terminationStatus
        }
        guard hdiutil(["create", "-size", "20m", "-fs", "APFS", "-volname", name, image.path]) == 0,
              hdiutil(["attach", "-nobrowse", "-mountpoint", "/Volumes/\(name)", image.path]) == 0 else {
            _ = hdiutil(["detach", "/Volumes/\(name)", "-force"])
            Issue.record("hdiutil indisponível ou preso")
            return
        }
        defer { _ = hdiutil(["detach", "/Volumes/\(name)", "-force"]) }
        let volume = URL(fileURLWithPath: "/Volumes/\(name)")
        let app = volume.appendingPathComponent("Foo.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let item = JunkItem(id: AppItemID.bundle(mode: .uninstall, appID: "com.example.foo|\(app.path)"), group: .appUninstall,
                            name: "Foo.app", url: app, size: 0, removal: .moveToTrash(app))
        let engine = CleanEngine(policies: [.appUninstall: PathPolicy(allowedRoots: [volume])], privileged: s.privileged, dryRun: false,
                                 log: CleanupLog(directory: s.t.url("logs")), runningApps: FakeRunningApps())
        let report = await run(engine, [item])
        #expect(report?.failed.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: app.path))
        let trashes = volume.appendingPathComponent(".Trashes/\(getuid())")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: trashes.path))?.contains { $0.hasPrefix("Foo") } == true)
    }
}
