import Foundation
import Testing
@testable import CleanYourMacCore

struct FakeReceipts: ReceiptSource {
    var receipts: [String: (volume: String, location: String, files: [String])] = [:]
    func packages() -> [String] { Array(receipts.keys) }
    func info(_ id: String) -> (volume: String, location: String)? { receipts[id].map { ($0.volume, $0.location) } }
    func files(_ id: String) -> [String] { receipts[id]?.files ?? [] }
}

private func plist(_ t: FixtureTree, _ rel: String, _ dict: [String: Any]) {
    let url = t.url(rel)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: url)
}

private struct Env {
    let t = FixtureTree()
    let ctx: ScanContext
    let app: AppRecord

    init(bundleID: String = "com.foo.App", matchName: String = "Foo", extra: [String: Any] = [:]) {
        ctx = t.context()
        let url = AppFixture.makeApp(t, "Applications/\(matchName).app", bundleID: bundleID, extra: extra)
        app = AppRecord(url: url, bundleID: bundleID, name: "\(matchName).app", matchName: matchName)
    }

    func paths(_ files: [RelatedFile]) -> [String] {
        files.map { $0.url.path.replacingOccurrences(of: PathPolicy.realPath(t.url("").path), with: "") }.sorted()
    }

    func find(installed: [AppRecord]? = nil, login: [LoginItemEntry] = [], receipts: FakeReceipts = FakeReceipts(),
              privileged: Bool = false) -> [RelatedFile] {
        RelatedFilesFinder(loginItems: FakeLoginItems(entries: login), receipts: receipts, privilegedAvailable: privileged)
            .files(for: app, installed: installed ?? [app], context: ctx)
    }
}

@Suite struct RelatedFilesTests {
    @Test func idMatchRequiresExactOrDottedSuffixWithoutDigits() {
        let e = Env()
        for n in ["com.foo.App", "com.foo.App.helper", "com.foo.AppHelper", "x.com.foo.App"] { e.t.dir("Users/tester/Library/Caches/\(n)") }
        e.t.dir("var/folders/zz/T/com.foo.App.7kmmTi")
        e.t.dir("var/folders/zz/T/com.foo.App.EwEVXI")
        #expect(e.paths(e.find()) == ["/Users/tester/Library/Caches/com.foo.App", "/Users/tester/Library/Caches/com.foo.App.helper",
                                      "/var/folders/zz/T/com.foo.App.EwEVXI"])
        #expect(e.find().allSatisfy { $0.kind == .supportingFiles && $0.removal == .moveToTrash($0.url) && $0.isSelected })
    }

    @Test func sharedPrefixNameNotRelated() {
        let e = Env(bundleID: "com.example.code", matchName: "Code")
        let vscodeURL = AppFixture.makeApp(e.t, "Applications/Visual Studio Code.app", bundleID: "com.microsoft.VSCode")
        let vscode = AppRecord(url: vscodeURL, bundleID: "com.microsoft.VSCode", name: "Visual Studio Code.app", matchName: "Code")
        for n in ["Code", "Code Helper", "code-oss"] { e.t.dir("Users/tester/Library/Application Support/\(n)") }
        e.t.dir("Users/tester/Library/Caches/com.example.codeHelper")
        // "Code" casa pelo nome com os dois apps: empate, fica fora dos dois.
        #expect(e.find(installed: [e.app, vscode]).isEmpty)
        // Sozinho, o app "Code" fica com a pasta Code (e não com "Code Helper"/"code-oss").
        #expect(e.paths(e.find()) == ["/Users/tester/Library/Application Support/Code"])
    }

    @Test func exactIDBeatsPrefixBetweenInstalledApps() {
        let e = Env()
        let helperURL = AppFixture.makeApp(e.t, "Applications/Helper.app", bundleID: "com.foo.App.helper")
        let helper = AppRecord(url: helperURL, bundleID: "com.foo.App.helper", name: "Helper.app", matchName: "Helper")
        e.t.dir("Users/tester/Library/Caches/com.foo.App.helper")
        #expect(e.find(installed: [e.app, helper]).isEmpty)
    }

    @Test func preferencesPlistByIDAndFolderByName() {
        let e = Env()
        e.t.file("Users/tester/Library/Preferences/com.foo.App.plist", bytes: 10)
        e.t.file("Users/tester/Library/Preferences/ByHost/com.foo.App.ABC.plist", bytes: 10)
        e.t.file("Users/tester/Library/Preferences/app.foo.com.plist", bytes: 10)
        e.t.dir("Users/tester/Library/Preferences/Foo")
        let files = e.find()
        #expect(e.paths(files) == ["/Users/tester/Library/Preferences/Foo", "/Users/tester/Library/Preferences/com.foo.App.plist"])
        #expect(files.allSatisfy { $0.kind == .preferences })
    }

    @Test func containerOnlyExactBundleID() {
        let e = Env()
        e.t.file("Users/tester/Library/Containers/com.foo.App/Data/x", bytes: 4096)
        e.t.dir("Users/tester/Library/Containers/com.foo.App.Widget")
        e.t.dir("Users/tester/Library/Group Containers/TEAM.com.foo.App")
        let files = e.find()
        #expect(e.paths(files) == ["/Users/tester/Library/Containers/com.foo.App"])
        #expect(files.first?.kind == .container)
    }

    @Test func symlinkedRelatedFileNotFollowed() {
        let e = Env()
        e.t.file("outside/big", bytes: 1_000_000)
        e.t.dir("Users/tester/Library/Containers")
        e.t.symlink("Users/tester/Library/Containers/com.foo.App", to: e.t.url("outside"))
        e.t.symlink("Users/tester/Library/Caches/com.foo.App", to: e.t.url("outside"))
        #expect(e.find().isEmpty)
    }

    @Test func launchdPlistsByNameLabelAssociationAndPrivilegedHelper() {
        let e = Env(extra: ["SMPrivilegedExecutables": ["com.foo.App.Helper": "anchor apple"]])
        plist(e.t, "Users/tester/Library/LaunchAgents/com.foo.App.plist", ["Label": "com.foo.App"])
        plist(e.t, "Users/tester/Library/LaunchAgents/com.foo.App.Wrong.plist", ["Label": "com.bar"])
        plist(e.t, "Library/LaunchAgents/org.other.agent.plist", ["Label": "org.other.agent", "AssociatedBundleIdentifiers": ["com.foo.App"]])
        plist(e.t, "Library/LaunchDaemons/com.foo.App.Updater.plist", ["Label": "com.foo.App.Updater"])
        plist(e.t, "Library/LaunchDaemons/com.foo.App.Helper.plist", ["Label": "com.foo.App.Helper"])
        e.t.file("Library/PrivilegedHelperTools/com.foo.App.Helper", bytes: 10)
        let files = e.find(privileged: true)
        #expect(e.paths(files) == ["/Library/LaunchAgents/org.other.agent.plist", "/Library/LaunchDaemons/com.foo.App.Helper.plist",
                                   "/Library/PrivilegedHelperTools/com.foo.App.Helper",
                                   "/Users/tester/Library/LaunchAgents/com.foo.App.plist"])
        #expect(files.allSatisfy { $0.kind == .loginItems })
        let user = files.first { $0.url.lastPathComponent == "com.foo.App.plist" }
        #expect(user?.removal == .unloadAndTrash(plist: user!.url, domain: .user))
        let daemon = files.first { $0.url.lastPathComponent == "com.foo.App.Helper.plist" }
        #expect(daemon?.removal == .unloadAndTrash(plist: daemon!.url, domain: .system))
    }

    @Test func pdfServicesAndPrivilegedToolNeverSymlinks() {
        let e = Env(extra: ["SMPrivilegedExecutables": ["com.foo.App.Helper": "anchor apple"]])
        let target = e.t.dir("Library/LaunchDaemons-real")
        e.t.dir("Users/tester/Library/PDF Services")
        e.t.symlink("Users/tester/Library/PDF Services/Foo", to: target)
        plist(e.t, "Library/LaunchDaemons/com.foo.App.Helper.plist", ["Label": "com.foo.App.Helper"])
        e.t.dir("Library/PrivilegedHelperTools")
        e.t.symlink("Library/PrivilegedHelperTools/com.foo.App.Helper", to: target)
        let paths = e.paths(e.find(privileged: true))
        #expect(!paths.contains { $0.contains("PDF Services") })
        #expect(!paths.contains { $0.contains("PrivilegedHelperTools") })
    }

    @Test func sessionLoginItemOfTheApp() {
        let e = Env()
        let files = e.find(login: [LoginItemEntry(name: "Foo", url: e.app.url), LoginItemEntry(name: "Other", url: URL(fileURLWithPath: "/x.app"))])
        #expect(files.count == 1)
        #expect(files.first?.kind == .loginItems)
        #expect(files.first?.size == 0)
        #expect(files.first?.removal == .removeSessionLoginItem(name: "Foo", url: e.app.url))
    }

    @Test func crashReportsByNamePrefix() {
        let e = Env()
        e.t.file("Users/tester/Library/Logs/DiagnosticReports/Foo_2026-10-21-101010_mac.diag", bytes: 10)
        e.t.file("Users/tester/Library/Logs/DiagnosticReports/Foo-2026-10-21-101010.ips", bytes: 10)
        e.t.file("Users/tester/Library/Logs/DiagnosticReports/Foobar_2026.diag", bytes: 10)
        // Prefixo com o nome exato (maiúsculas contam): o relatório de outro processo não entra.
        e.t.file("Users/tester/Library/Application Support/CrashReporter/foo_crashpad_handler_ABC.plist", bytes: 10)
        e.t.file("Users/tester/Library/Logs/foo.log", bytes: 10)
        e.t.file("Users/tester/Library/Logs/foo.log.old.0", bytes: 10)
        #expect(e.paths(e.find()) == ["/Users/tester/Library/Logs/DiagnosticReports/Foo_2026-10-21-101010_mac.diag",
                                      "/Users/tester/Library/Logs/foo.log"])
    }

    @Test func neverAppleOrStandardFolders() {
        let e = Env(bundleID: "com.thirdparty.Mail", matchName: "Mail")
        e.t.dir("Users/tester/Library/Mail")
        e.t.dir("Users/tester/Library/Caches/com.apple.Mail")
        e.t.dir("Users/tester/Library/Mail Downloads")
        #expect(e.find().isEmpty)
    }

    @Test func userDataDirectChildrenOfLibrary() {
        let e = Env()
        e.t.dir("Users/tester/Library/Foo")
        e.t.dir("Users/tester/Library/Google/Foo")
        let files = e.find()
        #expect(e.paths(files) == ["/Users/tester/Library/Foo"])
        #expect(files.first?.kind == .userData)
    }

    @Test func nestedItemCountedOnce() {
        let e = Env()
        e.t.file("Users/tester/Library/Application Support/Foo/com.foo.App/x", bytes: 4096)
        #expect(e.paths(e.find()) == ["/Users/tester/Library/Application Support/Foo"])
    }

    @Test func systemItemsUnselectedWithoutHelper() {
        let e = Env()
        e.t.dir("Library/Application Support/Foo")
        #expect(e.find(privileged: false).first?.isSelected == false)
        #expect(e.find(privileged: true).first?.isSelected == true)
    }

    @Test func receiptsByIDVolumeAndFiles() {
        let e = Env()
        let receipts = FakeReceipts(receipts: [
            "com.foo.App.pkg": ("/", "/", ["Applications/Foo.app", "Applications/Foo.app/Contents"]),
            "com.foo.installer.pkg": ("/", "/", ["Applications/Foo.app"]),
            "com.apple.pkg.X": ("/", "/", ["Applications/Foo.app"]),
            "com.foo.App.other": ("/", "/", ["Applications/Bar.app"]),
        ])
        let files = RelatedFilesFinder(loginItems: FakeLoginItems(entries: []), receipts: receipts, privilegedAvailable: true, rootForReceipts: e.t.url(""))
            .files(for: e.app, installed: [e.app], context: e.ctx)
        #expect(files.map(\.removal) == [.forgetReceipt("com.foo.App.pkg")])
        #expect(files.first?.kind == .other)
        #expect(files.first?.size == 0)
    }

    @Test func installerInDownloadsUnselected() {
        let e = Env()
        let dmg = e.t.file("Users/tester/Downloads/Foo.dmg", bytes: 10)
        e.t.file("Users/tester/Downloads/Foo-1.2.dmg", bytes: 10)
        let files = e.find()
        #expect(files.map(\.removal) == [.deleteDiskImage(URL(fileURLWithPath: PathPolicy.realPath(dmg.path)))])
        #expect(files.first?.isSelected == false)
    }
}
