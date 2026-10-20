import Testing
import Foundation
@testable import CleanYourMacCore

private func scan(_ s: any GroupScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}

private func writePlist(_ t: FixtureTree, _ rel: String, _ dict: [String: Any]) {
    t.dir((rel as NSString).deletingLastPathComponent)
    try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: t.url(rel))
}

// MARK: - Usuários apagados

@Test func deletedUsers_dmgOnly() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/Deleted Users/maria.dmg", bytes: 10_000)
    t.file("Users/Deleted Users/joao.sparseimage", bytes: 10)
    t.dir("Users/Deleted Users/pedro")
    t.file("Users/Deleted Users/.oculto.dmg", bytes: 10)
    t.file("Users/Deleted Users/X.DMG", bytes: 10)
    t.file("Users/Deleted Users/sub/ana.dmg", bytes: 10)
    let items = try await scan(DeletedUsersScanner(), ctx)
    #expect(items.map(\.name) == ["maria"])
    #expect(!items[0].isRecommended)
    #expect(GroupID.deletedUsers.requiresAdmin)
}

@Test func deletedUsers_missingRoot() async throws {
    #expect(try await scan(DeletedUsersScanner(), FixtureTree().context()).isEmpty)
}

// MARK: - Backups iOS

private let backups = "Users/tester/Library/Application Support/MobileSync/Backup"

private func backup(_ t: FixtureTree, _ udid: String, name: String?, type: String = "iPhone14,2", date: Date?, infoDate: Date? = nil) {
    var info: [String: Any] = ["Product Type": type]
    if let name { info["Device Name"] = name }
    if let infoDate { info["Last Backup Date"] = infoDate }
    writePlist(t, "\(backups)/\(udid)/Info.plist", info)
    if let date { writePlist(t, "\(backups)/\(udid)/Status.plist", ["Date": date]) }
    t.file("\(backups)/\(udid)/Manifest.db", bytes: 5000)
}

private let oct1 = Date(timeIntervalSince1970: 1_790_812_800), sep1 = Date(timeIntervalSince1970: 1_788_220_800)

@Test func ios_latestBadgePerDevice() async throws {
    let t = FixtureTree(); let ctx = t.context()
    backup(t, "UDID1", name: "iPhone do Gui", date: oct1)
    backup(t, "UDID2", name: "iPhone do Gui", date: sep1)
    let device = try #require(try await scan(IOSBackupsScanner(), ctx).first)
    #expect(device.name == "iPhone do Gui")
    let latest = device.children.first { $0.badge == .latest }
    #expect(latest?.url?.lastPathComponent == "UDID1")
    #expect(latest?.isRecommended == false)
    #expect(device.children.first { $0.url?.lastPathComponent == "UDID2" }?.isRecommended == true)
}

@Test func ios_productTypeSplitsDevices() async throws {
    let t = FixtureTree(); let ctx = t.context()
    backup(t, "A", name: "iPad", type: "iPad13,1", date: oct1)
    backup(t, "B", name: "iPad", type: "iPad14,1", date: sep1)
    #expect(try await scan(IOSBackupsScanner(), ctx).count == 2)
}

@Test func ios_fallbackDateAndUndated() async throws {
    let t = FixtureTree(); let ctx = t.context()
    backup(t, "A", name: "Phone", date: nil, infoDate: sep1)
    backup(t, "B", name: "Phone", date: nil)
    let device = try #require(try await scan(IOSBackupsScanner(), ctx).first)
    #expect(device.children.first { $0.badge == .latest }?.url?.lastPathComponent == "A")
}

@Test func ios_brokenBackups() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("\(backups)/NOINFO/Manifest.db", bytes: 100)
    backup(t, "NONAME", name: nil, date: oct1)
    t.file("\(backups)/.foo/x", bytes: 100)
    let items = try await scan(IOSBackupsScanner(), ctx)
    let broken = items.first { $0.titleKey == "ios.broken" }
    #expect(Set(broken?.children.map { $0.url!.lastPathComponent } ?? []) == ["NOINFO", "NONAME"])
    #expect(broken?.leaves.allSatisfy { $0.isRecommended && $0.badge == nil } == true)
    #expect(items.count == 1)
}

// MARK: - Versões de documentos

struct FakeVersion: Sendable { let url: URL; let date: Date?; let size: Int64 }

struct FakeVersions: DocumentVersionSource {
    var documents: [String: [URL]] = [:]
    var versions: [URL: [FakeVersion]] = [:]
    func documents(utis: [String]) -> [URL] { utis.flatMap { documents[$0] ?? [] } }
    func versions(of document: URL) -> [DocumentVersion] {
        (versions[document] ?? []).map { DocumentVersion(url: $0.url, modificationDate: $0.date, size: $0.size) }
    }
}

private func versionDates(_ hoursAgo: [Double]) -> [FakeVersion] {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    return hoursAgo.enumerated().map { i, h in
        FakeVersion(url: URL(fileURLWithPath: "/.DocumentRevisions-V100/v\(i)"), date: now.addingTimeInterval(-h * 3600), size: 1000)
    }
}

private func docVersions(_ hours: [Double], doc: URL = URL(fileURLWithPath: "/Users/x/a.pages")) async throws -> [JunkItem] {
    let src = FakeVersions(documents: ["com.apple.iwork.pages.pages": [doc]], versions: [doc: versionDates(hours)])
    let t = FixtureTree()
    return try await scan(DocumentVersionsScanner(source: src, apps: FakeApps()), t.context())
}

@Test func docVersions_thinningRule() async throws {
    let app = try #require(try await docVersions([0, 1, 2, 10, 11]).first)
    #expect(app.name == "Pages")
    let versions = try #require(app.children.first?.children)
    #expect(versions.map(\.isRecommended) == [false, true, true, false, false])
}

@Test func docVersions_twoVersionsNoneRecommended() async throws {
    let versions = try await docVersions([0, 1]).first?.children.first?.children ?? []
    #expect(versions.map(\.isRecommended) == [false, false])
}

@Test func docVersions_exactFourHoursNotRecommended() async throws {
    #expect(try await docVersions([0, 4, 8]).first?.children.first?.children.map(\.isRecommended) == [false, false, false])
    #expect(try await docVersions([0, 3.98, 8]).first?.children.first?.children.map(\.isRecommended) == [false, true, false])
}

@Test func docVersions_noVersionsNoApp() async throws {
    #expect(try await docVersions([]).isEmpty)
}

@Test func docVersions_numbersUTIsMerge() async throws {
    let a = URL(fileURLWithPath: "/x/a.numbers"), b = URL(fileURLWithPath: "/x/b.sffnumbers")
    let src = FakeVersions(documents: ["com.apple.iwork.numbers.numbers": [a], "com.apple.iwork.numbers.sffnumbers": [b]],
                           versions: [a: versionDates([0, 1]), b: versionDates([0, 1])])
    let items = try await scan(DocumentVersionsScanner(source: src, apps: FakeApps()), FixtureTree().context())
    #expect(items.map(\.name) == ["Numbers"])
    #expect(items[0].children.count == 2)
}

// MARK: - Xcode

private let xc = "Users/tester/Library/Developer/Xcode"

private func xcode(_ commands: FakeCommands = FakeCommands()) -> XcodeJunkScanner {
    XcodeJunkScanner(commands: commands, simctl: "/nonexistent/simctl")
}

private func sub(_ items: [JunkItem], _ key: String) -> JunkItem? {
    items.first { $0.titleKey == "xcode.\(key)" }
}

@Test func xcode_missingIsEmpty() async throws {
    #expect(try await scan(xcode(), FixtureTree().context()).isEmpty)
}

@Test func xcode_derivedData() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("\(xc)/DerivedData/MeuApp-abcdefghijklmnop/x", bytes: 10_000)
    t.file("\(xc)/DerivedData/ModuleCache.noindex/x", bytes: 10_000)
    t.file("\(xc)/DerivedData/SDKExplicitPrecompiledModules/x", bytes: 10_000)
    t.file("\(xc)/DerivedData/ModuleCache/x", bytes: 10_000)
    t.file("\(xc)/DerivedData/.DS_Store", bytes: 10)
    let items = try await scan(xcode(), ctx)
    let dd = try #require(sub(items, "derivedData"))
    let byName = Dictionary(uniqueKeysWithValues: dd.children.map { ($0.name, $0.isRecommended) })
    #expect(byName == ["MeuApp": true, "ModuleCache.noindex": false, "SDKExplicitPrecompiledModules": true])
    #expect(sub(items, "moduleCaches")?.children.map(\.name) == ["com.apple.dt.xcode"])
}

@Test func xcode_archivesNamedFromInfo() async throws {
    let t = FixtureTree(); let ctx = t.context()
    writePlist(t, "\(xc)/Archives/2026-10-20/MeuApp.xcarchive/Info.plist",
               ["Name": "MeuApp", "ApplicationProperties": ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "34"]])
    t.file("\(xc)/Archives/2026-10-20/Quebrado.xcarchive/x", bytes: 10)
    t.file("\(xc)/Archives/2026-10-20/notas.txt", bytes: 10)
    let archives = sub(try await scan(xcode(), ctx), "archives")
    #expect(archives?.children.map(\.name) == ["MeuApp 1.2 (34)"])
    #expect(archives?.children.first?.isRecommended == false)
}

@Test func xcode_deviceSupportLogsCachesDocs() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("\(xc)/iOS DeviceSupport/17.2 (21C62)/x", bytes: 10)
    t.file("\(xc)/iOS Device Logs/a.log", bytes: 10)
    t.file("Users/tester/Library/Developer/CoreSimulator/Caches/x", bytes: 10)
    t.file("\(xc)/DocumentationCache/v257/x", bytes: 10)
    t.file("var/folders/zz/C/org.llvm.clang/ModuleCache/x", bytes: 10)
    let items = try await scan(xcode(), ctx)
    #expect(sub(items, "iosDeviceSupport")?.children.map(\.name) == ["17.2 (21C62)"])
    #expect(sub(items, "deviceLogs")?.children.first?.isRecommended == true)
    #expect(sub(items, "simulatorCaches")?.children.first?.isRecommended == false)
    #expect(sub(items, "documentation")?.children.map(\.name) == ["iOS v257"])
    #expect(sub(items, "moduleCaches")?.children.map(\.name) == ["org.llvm.clang"])
}

@Test func xcode_simulatorsFromSimctl() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Developer/CoreSimulator/Devices/U1/data/x", bytes: 10)
    t.file("Users/tester/Library/Developer/CoreSimulator/Devices/U2/data/x", bytes: 10)
    let simctl = t.file("bin/simctl", bytes: 1)
    let json = """
    {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-17-2": [
      {"udid": "U1", "name": "iPhone 15", "state": "Shutdown", "isAvailable": false},
      {"udid": "U2", "name": "iPhone 15 Pro", "state": "Shutdown", "availability": "(available)"},
      {"udid": "U3", "name": "Gone", "state": "Shutdown", "isAvailable": false}],
     "unknown-key": [{"udid": "U9", "name": "x", "state": "Shutdown"}]}}
    """
    let cmds = ScriptedCommands(outputs: ["list": json, "-checkFirstLaunchStatus": "", "runtime": "{}"])
    let items = try await scan(XcodeJunkScanner(commands: cmds, simctl: simctl.path), ctx)
    let sims = items.filter { $0.titleKey == "xcode.simulators" }
    #expect(sims.map(\.name) == ["iOS 17.2"])
    let devices = Dictionary(uniqueKeysWithValues: (sims.first?.children ?? []).map { ($0.name, $0.isRecommended) })
    #expect(devices == ["iPhone 15": true, "iPhone 15 Pro": false])
}

@Test func xcode_simulatorsSkippedWhenToolsOutdated() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Developer/CoreSimulator/Devices/U1/x", bytes: 10)
    let simctl = t.file("bin/simctl", bytes: 1)
    let cmds = ScriptedCommands(outputs: ["list": #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-2":[{"udid":"U1","name":"a","state":"Shutdown","isAvailable":false}]}}"#],
                                failing: ["-checkFirstLaunchStatus"])
    let items = try await scan(XcodeJunkScanner(commands: cmds, simctl: simctl.path), ctx)
    #expect(!items.contains { $0.titleKey == "xcode.simulators" })
}

@Test func xcode_simulatorRemovalUsesSimctl() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Developer/CoreSimulator/Devices/U1/x", bytes: 10)
    let simctl = t.file("bin/simctl", bytes: 1)
    let cmds = ScriptedCommands(outputs: ["list": #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-2":[{"udid":"U1","name":"a","state":"Shutdown","isAvailable":false}]}}"#, "-checkFirstLaunchStatus": ""])
    let s = XcodeJunkScanner(commands: cmds, simctl: simctl.path)
    let items = try await scan(s, ctx)
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(), dryRun: false,
                             log: CleanupLog(directory: t.dir("logs")), commands: cmds)
    let sim = items.first { $0.titleKey == "xcode.simulators" }!
    for await _ in engine.clean([sim]) {}
    #expect(cmds.calls.contains([simctl.path, "delete", "U1"]))
}

/// Responde por argumento: a primeira chave contida nos argumentos define a saída.
final class ScriptedCommands: CommandRunner, @unchecked Sendable {
    let outputs: [String: String]
    let failing: Set<String>
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    init(outputs: [String: String], failing: Set<String> = []) { self.outputs = outputs; self.failing = failing }
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        lock.lock(); calls.append([executable] + arguments); lock.unlock()
        if arguments.contains(where: failing.contains) { return (1, "") }
        for (k, v) in outputs where arguments.contains(k) { return (0, v) }
        return (0, "")
    }
}
