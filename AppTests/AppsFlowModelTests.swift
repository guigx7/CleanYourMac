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
    var reason = "denied"

    func clean(_ items: [JunkItem]) -> AsyncStream<CleanEvent> {
        requested.append(items)
        let failing = failing, reason = reason
        return AsyncStream { cont in
            var removed: [String] = [], failed: [String: String] = [:]
            for leaf in items.flatMap(\.leaves) where leaf.removal != nil {
                cont.yield(.started(leaf))
                if failing.contains(leaf.id) {
                    failed[leaf.id] = reason
                    cont.yield(.finished(leaf, .failure(CleanFailure(reason: reason))))
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

    @Test func resetWithRunningAppOffersContinueWithoutQuitting() async {
        let running = StubRunning()
        running.open = [RunningApp(bundleID: "com.foo", name: "Foo", pid: 42)]
        let cleaner = RecordingCleaner()
        let m = model(running: running, cleaner: cleaner)
        m.start()
        await waitFor(m) { $0.phase == .results }
        m.selection.toggle(leaf(.preferences, "com.foo.plist", mode: .reset))
        m.act()
        #expect(m.quitPrompt?.apps.map(\.bundleID) == ["com.foo"])
        #expect(m.quitPrompt?.canContinue == true)
        m.continueWithoutQuitting()
        await waitFor(m) { if case .done = $0.phase { true } else { false } }
        #expect(cleaner.requested.count == 1)
        #expect(running.quitCalls.isEmpty)
    }

    @Test func uninstallWithRunningAppCannotContinueWithoutQuitting() async {
        let running = StubRunning()
        running.open = [RunningApp(bundleID: "com.foo", name: "Foo", pid: 42)]
        let m = model(running: running)
        m.start()
        await waitFor(m) { $0.phase == .results }
        m.selection.toggle(fooItem())
        m.act()
        #expect(m.quitPrompt?.canContinue == false)
    }

    @Test func actOnlyOnCurrentScope() async {
        let cleaner = RecordingCleaner()
        let m = model(cleaner: cleaner)
        m.start()
        await waitFor(m) { $0.phase == .results }
        let app = leaf(.preferences, "com.foo.plist")
        let leftoverURL = URL(fileURLWithPath: "/tmp/cym-stub/gone")
        let leftover = JunkItem(id: AppItemID.leftover(bundleID: "com.gone", path: leftoverURL.path), group: .appLeftovers,
                                name: "gone", url: leftoverURL, size: 1, isRecommended: true, removal: .moveToTrash(leftoverURL))
        m.selection.toggle(app)
        m.selection.toggle(leftover)
        m.actionScope = [.appLeftovers, .appInstallers]
        #expect(m.pendingLeaves.map(\.id) == [leftover.id])
        m.act()
        await waitFor(m) { if case .done = $0.phase { true } else { false } }
        #expect(cleaner.requested.first?.map(\.id) == [leftover.id])
    }

    @Test func cancellingCardActionRestoresSelection() async {
        let m = model()
        m.start()
        await waitFor(m) { $0.phase == .results }
        let mine = leaf(.preferences, "com.foo.plist")
        m.selection.toggle(mine)
        let url = URL(fileURLWithPath: "/tmp/cym-stub/gone")
        let card = JunkItem(id: AppItemID.leftover(bundleID: "com.gone", path: url.path), group: .appLeftovers, name: "gone",
                            url: url, size: 1, isRecommended: true, removal: .moveToTrash(url))
        m.prepare([card], scope: [.appLeftovers])
        #expect(m.selection.selectedLeaves.map(\.id) == [card.id])
        m.cancelPrepared()
        #expect(m.selection.selectedLeaves.map(\.id) == [mine.id])
    }

    @Test func parityExportWritesOnlyInsideLogsFolder() {
        let logs = CleanupLog.standard.directory
        #expect(ParityExport.isAllowedOutput(logs.appendingPathComponent("parity.json").path))
        #expect(!ParityExport.isAllowedOutput("/tmp/x.json"))
        #expect(!ParityExport.isAllowedOutput(logs.appendingPathComponent("../../x.json").path))
    }

    @Test func blockedAppBundleOffersAppManagement() async {
        let cleaner = RecordingCleaner()
        let bundle = fooItem().children[0].children[0]
        cleaner.failing = [bundle.id]
        cleaner.reason = "Operation not permitted"
        let m = model(cleaner: cleaner)
        m.start()
        await waitFor(m) { $0.phase == .results }
        m.selection.toggle(bundle)
        m.act()
        await waitFor(m) { if case .done = $0.phase { true } else { false } }
        #expect(m.needsAppManagement)
        // Outros motivos (app aberto, falha comum) não pedem a permissão.
        let other = RecordingCleaner()
        other.failing = [bundle.id]
        let m2 = model(cleaner: other)
        m2.start()
        await waitFor(m2) { $0.phase == .results }
        m2.selection.toggle(bundle)
        m2.act()
        await waitFor(m2) { if case .done = $0.phase { true } else { false } }
        #expect(!m2.needsAppManagement)
    }

    @Test func textsFollowWhatTheActionDoes() {
        let pref = leaf(.preferences, "com.foo.plist")
        let dmgURL = URL(fileURLWithPath: "/tmp/cym-stub/x.dmg")
        let dmg = JunkItem(group: .appInstallers, name: "x.dmg", url: dmgURL, size: 1, removal: .deleteDiskImage(dmgURL))
        #expect(AppsFlowModel.confirmTitleKey([pref]) == "apps.confirm.title.trash.one")
        #expect(AppsFlowModel.confirmTitleKey([pref, pref]) == "apps.confirm.title.trash.other")
        #expect(AppsFlowModel.confirmTitleKey([dmg]) == "apps.confirm.title.delete.one")
        #expect(AppsFlowModel.confirmTitleKey([pref, dmg]) == "apps.confirm.title.mixed")
        #expect(AppsFlowModel.doneKeys(trashed: 1, deleted: 0) == ["apps.done.removed.one", "apps.done.trash"])
        #expect(AppsFlowModel.doneKeys(trashed: 0, deleted: 2) == ["apps.done.removed.other", "apps.done.deleted"])
        #expect(AppsFlowModel.doneKeys(trashed: 3, deleted: 1) == ["apps.done.removed.other", "apps.done.trash", "apps.done.deleted"])
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

    @Test func tileReviewOpensTheRightPlaceInsideTheSection() {
        let m = model()
        m.openManager(.updater, focus: .systemUpdates)
        #expect(m.section == .updater && m.focus == .systemUpdates)
        m.openManager(.leftovers, focus: .installers)
        #expect(m.section == .leftovers && m.focus == .installers)
        m.openManager(.uninstaller, filter: .all)
        #expect(m.focus == nil)
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
