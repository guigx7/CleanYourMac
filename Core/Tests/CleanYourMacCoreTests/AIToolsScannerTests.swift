import Testing
import Foundation
@testable import CleanYourMacCore

struct FakeProcesses: ProcessChecker {
    var running: Set<String> = []
    func isRunning(_ name: String, uid: uid_t) -> Bool { running.contains(name) }
}

private func ai() -> AIToolsScanner { AIToolsScanner(apps: FakeApps()) }

private func scan(_ s: any GroupScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}

private func tool(_ items: [JunkItem], _ name: String) -> JunkItem? { items.first { $0.name == name } }
private func kind(_ tool: JunkItem?, _ k: String) -> JunkItem? { tool?.children.first { $0.titleKey == "aiKind.\(k)" } }
private func paths(_ item: JunkItem?) -> [String] { item?.leaves.compactMap { $0.url?.lastPathComponent } ?? [] }

@Test func ai_claudeCodeCache() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/.claude/cache/a.bin", bytes: 10_000)
    let items = try await scan(ai(), ctx)
    let cc = tool(items, "Claude Code")
    #expect(paths(kind(cc, "caches")) == ["cache"])
    #expect(items.flatMap(\.leaves).allSatisfy { !$0.isRecommended })
}

@Test func ai_neverTouchesSessionsAndSettings() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/.claude/projects/x.jsonl", bytes: 100)
    t.file("Users/tester/.claude/settings.json", bytes: 100)
    t.file("Users/tester/.claude/history.jsonl", bytes: 100)
    t.file("Users/tester/Library/Application Support/Claude/Local Storage/x", bytes: 100)
    t.file("Users/tester/Library/Application Support/Claude/DawnGraphiteCache/x", bytes: 100)
    #expect(try await scan(ai(), ctx).isEmpty)
}

@Test func ai_kindsLogsAndTemporary() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/.claude/debug/log.txt", bytes: 100)
    t.file("Users/tester/.claude/shell-snapshots/s.sh", bytes: 100)
    t.file("Users/tester/.claude/cache/x", bytes: 100)
    let cc = tool(try await scan(ai(), ctx), "Claude Code")
    #expect(paths(kind(cc, "logs")) == ["debug"])
    #expect(paths(kind(cc, "temporary")) == ["shell-snapshots"])
    #expect(cc?.children.compactMap(\.titleKey) == ["aiKind.caches", "aiKind.logs", "aiKind.temporary"])
    #expect(kind(cc, "caches")?.displaysChildren == false)
}

private func versions(_ t: FixtureTree, active: String?) {
    for v in ["1.0.0", "1.0.1", "1.0.2"] { t.file("Users/tester/.local/share/claude/versions/\(v)", bytes: 1000) }
    if let active { t.symlink("Users/tester/.local/bin/claude", to: t.url("Users/tester/.local/share/claude/versions/\(active)")) }
}

@Test func ai_staleVersionsKeepActive() async throws {
    let t = FixtureTree(); let ctx = t.context()
    versions(t, active: "1.0.1")
    let cc = tool(try await scan(ai(), ctx), "Claude Code")
    #expect(paths(kind(cc, "staleVersions")).sorted() == ["1.0.0", "1.0.2"])
}

@Test func ai_noLinkNoStaleVersions() async throws {
    let t = FixtureTree(); let ctx = t.context()
    versions(t, active: nil)
    #expect(tool(try await scan(ai(), ctx), "Claude Code") == nil)
}

@Test func ai_linkOutsideVersionsNoStale() async throws {
    let t = FixtureTree(); let ctx = t.context()
    versions(t, active: nil)
    let other = t.file("elsewhere/claude", bytes: 10)
    t.symlink("Users/tester/.local/bin/claude", to: other)
    #expect(tool(try await scan(ai(), ctx), "Claude Code") == nil)
}

@Test func ai_hiddenAndHardlinkedVersionsIgnored() async throws {
    let t = FixtureTree(); let ctx = t.context()
    versions(t, active: "1.0.1")
    t.file("Users/tester/.local/share/claude/versions/.tmp123", bytes: 10)
    t.hardlink("elsewhere/link", to: t.url("Users/tester/.local/share/claude/versions/1.0.0"))
    let cc = tool(try await scan(ai(), ctx), "Claude Code")
    #expect(paths(kind(cc, "staleVersions")) == ["1.0.2"])
}

@Test func ai_staleVersionRecheckedBeforeDelete() async throws {
    let t = FixtureTree(); let ctx = t.context()
    versions(t, active: "1.0.1")
    let s = ai()
    let cc = tool(try await scan(s, ctx), "Claude Code")
    // O usuário atualiza: 1.0.2 passa a ser a ativa antes da limpeza.
    try FileManager.default.removeItem(at: t.url("Users/tester/.local/bin/claude"))
    t.symlink("Users/tester/.local/bin/claude", to: t.url("Users/tester/.local/share/claude/versions/1.0.2"))
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")))
    for await _ in engine.clean([kind(cc, "staleVersions")!]) {}
    #expect(!FileManager.default.fileExists(atPath: t.url("Users/tester/.local/share/claude/versions/1.0.0").path))
    #expect(FileManager.default.fileExists(atPath: t.url("Users/tester/.local/share/claude/versions/1.0.2").path))
}

@Test func ai_tmpFolders() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("private/tmp/claude-\(getuid())/x", bytes: 10)
    t.file("private/tmp/claude-999/x", bytes: 10)
    t.file("private/tmp/codex-daemon-501/x", bytes: 10)
    t.file("private/tmp/codex-browser-use/x", bytes: 10)
    let other = t.dir("private/tmp/real-opencode")
    t.symlink("private/tmp/opencode", to: other)
    let items = try await scan(ai(), ctx)
    #expect(paths(kind(tool(items, "Claude Code"), "temporary")) == ["claude-\(getuid())"])
    #expect(paths(kind(tool(items, "Codex"), "temporary")) == ["codex-browser-use"])
    #expect(tool(items, "OpenCode") == nil)
}

@Test func ai_bundleIDFamily() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Caches/com.anthropic.claudefordesktop.ShipIt/x", bytes: 10)
    t.file("var/folders/zz/C/com.anthropic.claudefordesktop.helper/x", bytes: 10)
    t.file("Users/tester/Library/Caches/com.anthropic.claudefordesktopX/x", bytes: 10)
    let claude = tool(try await scan(ai(), ctx), "Claude")
    #expect(paths(kind(claude, "caches")).sorted() == ["com.anthropic.claudefordesktop.ShipIt", "com.anthropic.claudefordesktop.helper"])
}

@Test func ai_appSupportChromiumOnly() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Application Support/Claude/Cache/x", bytes: 10)
    t.file("Users/tester/Library/Application Support/Claude/Local Storage/x", bytes: 10)
    #expect(paths(kind(tool(try await scan(ai(), ctx), "Claude"), "caches")) == ["Cache"])
}

@Test func ai_cacheFolderIsExact() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Caches/claude-cli-nodejs.old/x", bytes: 10)
    #expect(try await scan(ai(), ctx).isEmpty)
}

@Test func ai_cursorGlobDepth() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/.local/share/cursor-agent/a/b/c/x.log", bytes: 10)
    t.file("Users/tester/.local/share/cursor-agent/a/b/c/d/e/y.log", bytes: 10)
    t.file("Users/tester/.local/share/cursor-agent/z.txt", bytes: 10)
    #expect(paths(kind(tool(try await scan(ai(), ctx), "Cursor"), "logs")) == ["x.log"])
}

@Test func ai_emptyCodexTmpIsZeroItem() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.dir("Users/tester/.codex/tmp")
    let codex = tool(try await scan(ai(), ctx), "Codex")
    #expect(paths(kind(codex, "caches")) == ["tmp"])
    #expect(codex?.totalSize == 0)
}

@Test func ai_crossExclusionFromUserGroups() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/Library/Caches/com.openai.codex/x", bytes: 10)
    t.file("Users/tester/Library/Logs/Claude/main.log", bytes: 50_000)
    t.app("Applications/Claude.app", bundleID: "com.anthropic.claudefordesktop", electron: true)
    t.file("Users/tester/Library/Application Support/Claude/Cache/x", bytes: 10)
    let codex = tool(try await scan(ai(), ctx), "Codex")
    #expect(paths(kind(codex, "caches")) == ["com.openai.codex"])
    let uc = try await scan(CacheScanner.userCache(apps: FakeApps(), inventory: FolderAppInventory()), ctx)
    #expect(uc.isEmpty)
    #expect(try await scan(LogsScanner.userLogs(apps: FakeApps()), ctx).isEmpty)
}

@Test func ai_kindCleanKeepsOthers() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("Users/tester/.claude/cache/x", bytes: 10)
    let debug = t.file("Users/tester/.claude/debug/log", bytes: 10)
    let s = ai()
    let cc = tool(try await scan(s, ctx), "Claude Code")
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")))
    for await _ in engine.clean([kind(cc, "caches")!]) {}
    #expect(!FileManager.default.fileExists(atPath: t.url("Users/tester/.claude/cache").path))
    #expect(FileManager.default.fileExists(atPath: debug.path))
    #expect(FileManager.default.fileExists(atPath: t.url("Users/tester/.claude").path))
}

@Test func ai_runningToolTmpSkipped() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let tmp = t.file("private/tmp/claude-\(getuid())/x", bytes: 10)
    let cache = t.file("Users/tester/.claude/cache/x", bytes: 10)
    let s = ai()
    let cc = tool(try await scan(s, ctx), "Claude Code")!
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")),
                             processes: FakeProcesses(running: ["claude"]))
    var report: CleanReport?
    for await e in engine.clean([cc]) { if case .completed(let r) = e { report = r } }
    #expect(FileManager.default.fileExists(atPath: tmp.path))
    #expect(!FileManager.default.fileExists(atPath: cache.path))
    #expect(report?.failed.values.contains("in use") == true)
}

@Test func ai_sizeIsAllocated() async throws {
    // A baseline nova mostrou o tamanho alocado (caches Chromium com muitos arquivos pequenos).
    let t = FixtureTree(); let ctx = t.context()
    var expected: Int64 = 0
    for i in 0..<5 { expected += FixtureTree.allocated(t.file("Users/tester/.claude/cache/f\(i)", bytes: 100)) }
    let cc = tool(try await scan(ai(), ctx), "Claude Code")
    #expect(cc?.totalSize == expected)
}
