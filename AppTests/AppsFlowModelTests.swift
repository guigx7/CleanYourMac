import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

struct StubAppsScan: AppsScanning {
    var report: AppsReport
    var delay: Duration = .zero

    func run(_ context: ScanContext) -> AsyncThrowingStream<AppsScanEvent, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                cont.yield(.progress(phase: .apps, path: "/Applications"))
                if delay > .zero {
                    do { try await Task.sleep(for: delay) } catch { cont.finish(throwing: error); return }
                }
                cont.yield(.finished(report))
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

/// Registra o que foi pedido e responde sucesso (ou falha para os ids em `failing`).
final class RecordingCleaner: Cleaning, @unchecked Sendable {
    private(set) var requested: [[JunkItem]] = []
    var failing: Set<String> = []

    func clean(_ items: [JunkItem]) -> AsyncStream<CleanEvent> {
        requested.append(items)
        let failing = failing
        return AsyncStream { cont in
            var removed: [String] = [], failed: [String: String] = [:]
            for leaf in items.flatMap(\.leaves) where leaf.removal != nil {
                cont.yield(.started(leaf))
                if failing.contains(leaf.id) {
                    failed[leaf.id] = "denied"
                    cont.yield(.finished(leaf, .failure(CleanFailure(reason: "denied"))))
                } else {
                    removed.append(leaf.id)
                    cont.yield(.finished(leaf, .success(leaf.size)))
                }
            }
            cont.yield(.completed(CleanReport(freedBytes: 0, removed: removed, failed: failed, dryRun: true)))
            cont.finish()
        }
    }
}

final class StubRunning: RunningApps, @unchecked Sendable {
    var open: [RunningApp] = []
    var quits = true
    private(set) var quitCalls: [(String, Bool)] = []

    func running(bundleIDs: Set<String>) -> [RunningApp] { open.filter { bundleIDs.contains($0.bundleID) } }
    func quit(_ app: RunningApp, force: Bool) async -> Bool {
        quitCalls.append((app.bundleID, force))
        if quits { open.removeAll { $0 == app } }
        return quits
    }
}

final class StubOpener: URLOpening, @unchecked Sendable {
    private(set) var opened: [URL] = []
    private(set) var copied: [String] = []
    func open(_ url: URL) -> Bool { opened.append(url); return true }
    func copy(_ text: String) { copied.append(text) }
}

private let appID = "com.foo|/Applications/Foo.app"

private func leaf(_ kind: ResourceKind, _ name: String, mode: AppItemID.Mode = .uninstall, recommended: Bool = true) -> JunkItem {
    let url = URL(fileURLWithPath: "/tmp/cym-stub/\(name)")
    return JunkItem(id: AppItemID.leaf(mode: mode, appID: appID, path: url.path), group: .appUninstall, name: name,
                    detail: kind.rawValue, url: url, size: 100, isRecommended: recommended, removal: .moveToTrash(url))
}

private func fooItem() -> JunkItem {
    let bundle = JunkItem(id: AppItemID.bundle(mode: .uninstall, appID: appID), group: .appUninstall, name: "Foo.app",
                          detail: "binaries", url: URL(fileURLWithPath: "/Applications/Foo.app"), size: 1000, isRecommended: true,
                          removal: .trashAppBundle(URL(fileURLWithPath: "/Applications/Foo.app")))
    let kinds: [(ResourceKind, [JunkItem])] = [(.binaries, [bundle]),
                                                (.preferences, [leaf(.preferences, "com.foo.plist")]),
                                                (.container, [leaf(.container, "com.foo")])]
    return JunkItem(id: "appUninstall:\(appID)", group: .appUninstall, name: "Foo.app", url: URL(fileURLWithPath: "/Applications/Foo.app"),
                    size: 0, children: kinds.map { k, items in
                        JunkItem(id: "appUninstall:\(appID)\u{1E}kind:\(k.rawValue)", group: .appUninstall, name: k.rawValue,
                                 detail: k.rawValue, url: nil, size: 0, children: items)
                    })
}

private func report(apps: Bool = true) -> AppsReport {
    let foo = AppRecord(url: URL(fileURLWithPath: "/Applications/Foo.app"), bundleID: "com.foo", name: "Foo.app")
    return AppsReport(apps: apps ? [foo] : [], uninstaller: apps ? [fooItem()] : [], leftovers: [], installers: [],
                      updates: UpdateCheckResult(updates: [], offline: false))
}

@MainActor
private func model(_ r: AppsReport = report(), delay: Duration = .zero, running: StubRunning = StubRunning(),
                   cleaner: RecordingCleaner = RecordingCleaner(), opener: StubOpener = StubOpener()) -> AppsFlowModel {
    let ctx = ScanContext(root: URL(fileURLWithPath: "/tmp/cym-stub"), home: URL(fileURLWithPath: "/tmp/cym-stub/home"),
                          userName: "t", preferredLanguages: ["en"], now: .now)
    return AppsFlowModel(scan: StubAppsScan(report: r, delay: delay), cleaner: cleaner, runningApps: running, context: ctx, opener: opener)
}

@MainActor
private func waitFor(_ m: AppsFlowModel, _ condition: (AppsFlowModel) -> Bool) async {
    for _ in 0..<200 where !condition(m) { try? await Task.sleep(for: .milliseconds(10)) }
}

@MainActor
struct AppsFlowModelTests {
    @Test func scanThenResults() async {
        let m = model()
        m.start()
        await waitFor(m) { $0.phase != .scanning }
        #expect(m.phase == .results)
        #expect(m.report?.apps.count == 1)
    }

    @Test func emptyReportShowsNothingFound() async {
        let m = model(report(apps: false))
        m.start()
        await waitFor(m) { $0.phase != .scanning }
        #expect(m.phase == .nothingFound)
    }

    @Test func stopReturnsToIntro() async {
        let m = model(delay: .seconds(5))
        m.start()
        m.stop()
        #expect(m.phase == .intro)
    }

    @Test func togglingAppSelectsRecommendedLeaves() async {
        let m = model()
        m.start()
        await waitFor(m) { $0.phase == .results }
        let item = fooItem()
        m.selection.toggle(item)
        #expect(m.selection.state(of: item) == .on)
        #expect(m.selection.selectedLeaves.count == 3)
        m.selection.toggle(item.children[2].children[0])
        #expect(m.selection.state(of: item) == .mixed)
    }

    @Test func actWithRunningAppAsksToQuit() async {
        let running = StubRunning()
        running.open = [RunningApp(bundleID: "com.foo", name: "Foo", pid: 42)]
        let cleaner = RecordingCleaner()
        let m = model(running: running, cleaner: cleaner)
        m.start()
        await waitFor(m) { $0.phase == .results }
        m.selection.toggle(fooItem())
        m.act()
        #expect(m.quitPrompt?.apps.map(\.bundleID) == ["com.foo"])
        #expect(cleaner.requested.isEmpty)
        await m.quitAndContinue(force: false)
        await waitFor(m) { if case .done = $0.phase { true } else { false } }
        #expect(running.quitCalls.map(\.0) == ["com.foo"])
        #expect(cleaner.requested.count == 1)
    }

    @Test func quitThatFailsOffersForceAndCancelTouchesNothing() async {
        let running = StubRunning()
        running.open = [RunningApp(bundleID: "com.foo", name: "Foo", pid: 42)]
        running.quits = false
        let cleaner = RecordingCleaner()
        let m = model(running: running, cleaner: cleaner)
        m.start()
        await waitFor(m) { $0.phase == .results }
        m.selection.toggle(fooItem())
        m.act()
        await m.quitAndContinue(force: false)
        #expect(m.quitPrompt?.offerForce == true)
        m.cancelQuit()
        #expect(m.quitPrompt == nil)
        #expect(cleaner.requested.isEmpty)
    }

    @Test func resetWithUserDataNeedsConfirmation() async {
        let cleaner = RecordingCleaner()
        let m = model(cleaner: cleaner)
        m.start()
        await waitFor(m) { $0.phase == .results }
        let container = leaf(.container, "com.foo", mode: .reset, recommended: false)
        m.selection.toggle(container)
        m.act()
        #expect(m.resetConfirmation?.leaves.map(\.id) == [container.id])
        #expect(cleaner.requested.isEmpty)
        m.confirmReset()
        await waitFor(m) { if case .done = $0.phase { true } else { false } }
        #expect(cleaner.requested.count == 1)
    }

    @Test func doneKeepsFailures() async {
        let cleaner = RecordingCleaner()
        let pref = leaf(.preferences, "com.foo.plist")
        cleaner.failing = [pref.id]
        let m = model(cleaner: cleaner)
        m.start()
        await waitFor(m) { $0.phase == .results }
        m.selection.toggle(pref)
        m.act()
        await waitFor(m) { if case .done = $0.phase { true } else { false } }
        #expect(m.failures[pref.id] == "denied")
    }

    @Test func updateActionOpensRightPlace() {
        let opener = StubOpener()
        let m = model(opener: opener)
        let store = URL(string: "macappstore://apps.apple.com/app/id1")!
        m.perform(.openAppStore(store, fallback: nil))
        m.perform(.openSoftwareUpdate)
        m.perform(.openApp(URL(fileURLWithPath: "/Applications/Foo.app"), notes: nil))
        m.perform(.copyCommand("brew upgrade --cask foo", homepage: nil))
        #expect(opener.opened.map(\.absoluteString) == ["macappstore://apps.apple.com/app/id1",
                                                         "x-apple.systempreferences:com.apple.preferences.softwareupdate",
                                                         "file:///Applications/Foo.app"])
        #expect(opener.copied == ["brew upgrade --cask foo"])
    }

    @Test func openManagerKeepsSectionAndFilter() {
        let m = model()
        m.openManager(.leftovers)
        #expect(m.managerOpen && m.section == .leftovers)
        m.openManager(.uninstaller, filter: .unused)
        #expect(m.section == .uninstaller && m.filter == .unused)
        m.closeManager()
        #expect(!m.managerOpen)
    }
}
