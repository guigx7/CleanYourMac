import Testing
import Foundation
@testable import CleanYourMacCore

private func scan(_ s: any GroupScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}
private let userLogs = LogsScanner.userLogs(apps: FakeApps())
private let systemLogs = LogsScanner.systemLogs(apps: FakeApps())

@Test func userLogs_smallFileExcluded() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Logs/a.log", bytes: 1146)
    #expect(try await scan(userLogs, ctx).isEmpty)
}

@Test func userLogs_thresholdIsStrict() async throws {
    let t = FixtureTree(); let ctx = t.context()
    // Em APFS (blocos de 4 KB) não dá para alocar exatamente 10 240; 8 192 fica abaixo do limite.
    t.file("Users/tester/Library/Logs/exact.log", bytes: 8192)
    t.file("Users/tester/Library/Logs/over.log", bytes: 12_288)
    #expect(try await scan(userLogs, ctx).map(\.name) == ["over"])
}

@Test func userLogs_fileItemNameStripsExtension() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Logs/warp.log", bytes: 50_000)
    t.file("Users/tester/Library/Logs/warp.log.old.0", bytes: 50_000)
    #expect(Set(try await scan(userLogs, ctx).map(\.name)) == ["warp", "warp.log.old"])
}

@Test func userLogs_folderKeepsOnlyBigFiles() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let a = t.file("Users/tester/Library/Logs/DiagnosticReports/a", bytes: 20_480)
    let b = t.file("Users/tester/Library/Logs/DiagnosticReports/b", bytes: 24_576)
    for i in 0..<10 { t.file("Users/tester/Library/Logs/DiagnosticReports/s\(i)", bytes: 4096) }
    let items = try await scan(userLogs, ctx)
    #expect(items.map(\.name) == ["DiagnosticReports"])
    #expect(items[0].children.count == 2)
    #expect(items[0].totalSize == FixtureTree.allocated(a) + FixtureTree.allocated(b))
    #expect(!items[0].displaysChildren)
}

@Test func userLogs_folderRecursive() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Logs/X/sub/deep.log", bytes: 50_000)
    let items = try await scan(userLogs, ctx)
    #expect(items.map(\.name) == ["X"])
    #expect(items[0].children.map(\.name) == ["deep.log"])
}

@Test func userLogs_folderOfSmallFilesDropped() async throws {
    let t = FixtureTree(); let ctx = t.context()
    for i in 0..<8 { t.file("Users/tester/Library/Logs/TeamSpeak/f\(i)", bytes: 8192) }
    #expect(try await scan(userLogs, ctx).isEmpty)
}

@Test func userLogs_dsStoreSkipped() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Logs/X/.DS_Store", bytes: 20_000)
    t.file("Users/tester/Library/Logs/X/a.log", bytes: 20_000)
    #expect(try await scan(userLogs, ctx).first?.children.map(\.name) == ["a.log"])
}

@Test func userLogs_sandboxLogs() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Containers/com.foo/Data/Library/Logs/foo.log", bytes: 50_000)
    #expect(try await scan(userLogs, ctx).map(\.name) == ["foo"])
}

@Test func userLogs_quarantineIncludedIfNonEmpty() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2", bytes: 20_480)
    t.file("Users/tester/Library/Preferences/com.apple.LaunchServices.QuarantineEvents", bytes: 0)
    #expect(try await scan(userLogs, ctx).map(\.name) == ["com.apple.LaunchServices"])
}

@Test func userLogs_excludesAITools() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Logs/Claude/main.log", bytes: 1_000_000)
    #expect(try await scan(userLogs, ctx).isEmpty)
}

@Test func userLogs_allRecommended() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Logs/X/a.log", bytes: 50_000)
    t.file("Users/tester/Library/Logs/b.log", bytes: 50_000)
    #expect(try await scan(userLogs, ctx).flatMap(\.leaves).allSatisfy { $0.isRecommended })
}

@Test func userLogs_removalKeepsSmallFiles() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let big = t.file("Users/tester/Library/Logs/X/big.log", bytes: 50_000)
    let small = t.file("Users/tester/Library/Logs/X/small.log", bytes: 1000)
    let item = try #require(try await scan(userLogs, ctx).first)
    let engine = CleanEngine(policies: Registry.policies(for: [userLogs], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")))
    for await _ in engine.clean([item]) {}
    #expect(!FileManager.default.fileExists(atPath: big.path))
    #expect(FileManager.default.fileExists(atPath: small.path))
}

@Test func systemLogs_localLogsChildren() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Library/Logs/DiagnosticReports/a.ips", bytes: 20_000)
    t.file("Library/Logs/DiagnosticReports/b.diag", bytes: 4000)
    let items = try await scan(systemLogs, ctx)
    #expect(items.map(\.name) == ["DiagnosticReports"])
    #expect(items[0].children.map(\.name) == ["a.ips"])
}

@Test func systemLogs_localSmallFileExcluded() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Library/Logs/LKDC-setup.log", bytes: 308)
    #expect(try await scan(systemLogs, ctx).isEmpty)
}

@Test func systemLogs_aslWholeFolderNoSizeLimit() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("private/var/log/asl/x.asl", bytes: 1000)
    t.file("private/var/log/asl/y.asl", bytes: 2000)
    let items = try await scan(systemLogs, ctx)
    #expect(items.map(\.name) == ["asl"])
    #expect(items[0].children.count == 2)
}

@Test func systemLogs_privateKnownName() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("private/var/log/wifi.log", bytes: 50_000)
    t.file("private/var/log/keybagd.log.0", bytes: 50_000)
    #expect(try await scan(systemLogs, ctx).map(\.name) == ["wifi"])
}

@Test func systemLogs_privatePatternMatches() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("private/var/log/system.log.3.gz", bytes: 20_000)
    t.file("private/var/log/system.log.4.gz", bytes: 1000)
    t.file("private/var/log/WIFI.LOG.0.BZ2", bytes: 20_000)
    #expect(Set(try await scan(systemLogs, ctx).map(\.name)) == ["system.log.3", "WIFI.LOG.0"])
}

@Test func systemLogs_diagnosticsNotScanned() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("private/var/db/diagnostics/x", bytes: 1_000_000)
    #expect(try await scan(systemLogs, ctx).isEmpty)
}

@Test func systemLogs_requiresAdminToClean() {
    #expect(GroupID.systemLogs.requiresAdmin)
    #expect(!GroupID.systemLogs.requiresAdminToScan)
    #expect(!GroupID.userLogs.requiresAdmin)
}

@Test func userLogs_coreSimulatorExcluded() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Logs/CoreSimulator/CoreSimulator.log", bytes: 50_000)
    #expect(try await scan(userLogs, ctx).isEmpty)
}
