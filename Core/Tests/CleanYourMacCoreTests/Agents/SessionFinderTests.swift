import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct SessionFinderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
    private func finder(_ fx: FixtureTree, worktrees: Set<URL> = []) -> SessionFinder {
        SessionFinder(home: fx.dir("home"), now: now, worktrees: worktrees)
    }
    private func touch(_ fx: FixtureTree, _ rel: String, days: Double) {
        try! FileManager.default.setAttributes([.modificationDate: ago(days)], ofItemAtPath: fx.url(rel).path)
    }
    /// Cria arquivo com a data e depois põe a mesma data nas pastas pais (para a pasta não ser mais nova que o conteúdo).
    private func make(_ fx: FixtureTree, _ rel: String, days: Double) {
        fx.file(rel, bytes: 100, modified: ago(days))
        var dir = (rel as NSString).deletingLastPathComponent
        while dir.hasPrefix("home/.") || dir.split(separator: "/").count > 2 {
            touch(fx, dir, days: days)
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    private func claudeSession(_ fx: FixtureTree, id: String, days: Double) {
        make(fx, "home/.claude/projects/-p/\(id).jsonl", days: days)
        make(fx, "home/.claude/projects/-p/\(id)/subagents/a.jsonl", days: days)
        make(fx, "home/.claude/file-history/\(id)/f@v1", days: days)
        make(fx, "home/.claude/session-env/\(id)/e", days: days)
        make(fx, "home/.claude/todos/\(id)-agent-x.json", days: days)
        touch(fx, "home/.claude/projects/-p/\(id)", days: days)
        touch(fx, "home/.claude/file-history/\(id)", days: days)
        touch(fx, "home/.claude/session-env/\(id)", days: days)
    }

    @Test func claudeSessionIsOneItem() {
        let fx = FixtureTree()
        claudeSession(fx, id: "11111111-1111-4111-8111-111111111111", days: 10)
        let s = finder(fx).sessions()
        #expect(s.count == 1)
        #expect(s.first?.id == "claude-code:11111111-1111-4111-8111-111111111111")
        #expect(s.first?.project == "-p")
        #expect(s.first?.urls.count == 5)
        #expect(s.first?.isOrphanRemains == false)
        #expect(s.first?.lastModified == ago(10))
        #expect(s.first!.size > 0)
    }

    @Test func touchedRemainKeepsSessionOut() {
        let fx = FixtureTree()
        claudeSession(fx, id: "11111111-1111-4111-8111-111111111111", days: 10)
        touch(fx, "home/.claude/session-env/11111111-1111-4111-8111-111111111111/e", days: 2)
        #expect(finder(fx).sessions().isEmpty)
    }

    @Test func claudeOrphanRemains() {
        let fx = FixtureTree()
        make(fx, "home/.claude/file-history/22222222-2222-4222-8222-222222222222/f@v1", days: 9)
        touch(fx, "home/.claude/file-history/22222222-2222-4222-8222-222222222222", days: 9)
        let s = finder(fx).sessions()
        #expect(s.count == 1)
        #expect(s.first?.isOrphanRemains == true)
        #expect(s.first?.project == nil)
    }

    @Test func recentAndMemoryNeverListed() {
        let fx = FixtureTree()
        claudeSession(fx, id: "33333333-3333-4333-8333-333333333333", days: 3)
        make(fx, "home/.claude/projects/-p/memory/m.md", days: 30)
        make(fx, "home/.claude/history.jsonl", days: 30)
        make(fx, "home/.claude/settings.json", days: 30)
        make(fx, "home/.claude/settings.local.json", days: 30)
        #expect(finder(fx).sessions().isEmpty)
    }

    @Test func symlinksAreNeverFollowed() {
        let fx = FixtureTree()
        let target = fx.file("outside/x.jsonl", bytes: 10, modified: ago(30))
        fx.symlink("home/.claude/projects/-p/link.jsonl", to: target)
        fx.symlink("home/.claude/file-history/lnk", to: fx.dir("outside"))
        #expect(finder(fx).sessions().isEmpty)
    }

    @Test func jobsRules() {
        let fx = FixtureTree()
        for (j, state) in [("j1", "done"), ("j2", "blocked"), ("j3", "done"), ("j4", "done"), ("j5", "weird")] {
            make(fx, "home/.claude/jobs/\(j)/state.json", days: 20)
            try! "{\"state\":\"\(state)\"}".write(to: fx.url("home/.claude/jobs/\(j)/state.json"), atomically: true, encoding: .utf8)
            touch(fx, "home/.claude/jobs/\(j)/state.json", days: 20)
        }
        make(fx, "home/.claude/jobs/j3/tmp/wt/.git", days: 20)
        try! "gitdir: /x/.git/worktrees/wt".write(to: fx.url("home/.claude/jobs/j3/tmp/wt/.git"), atomically: true, encoding: .utf8)
        touch(fx, "home/.claude/jobs/j3/tmp/wt/.git", days: 20)
        make(fx, "home/.claude/jobs/j4/backup/b", days: 20)
        for j in ["j1", "j2", "j3", "j4", "j5"] { touch(fx, "home/.claude/jobs/\(j)", days: 20) }
        let ids = finder(fx).sessions().map(\.id)
        #expect(ids == ["claude-code:job-j1"])
    }

    @Test func jobWithKnownWorktreeIsOut() {
        let fx = FixtureTree()
        make(fx, "home/.claude/jobs/j1/state.json", days: 20)
        try! "{\"state\":\"done\"}".write(to: fx.url("home/.claude/jobs/j1/state.json"), atomically: true, encoding: .utf8)
        touch(fx, "home/.claude/jobs/j1/state.json", days: 20)
        let wt = fx.dir("home/.claude/jobs/j1/tmp/other")
        touch(fx, "home/.claude/jobs/j1/tmp/other", days: 20)
        touch(fx, "home/.claude/jobs/j1/tmp", days: 20)
        touch(fx, "home/.claude/jobs/j1", days: 20)
        #expect(finder(fx, worktrees: [wt]).sessions().isEmpty)
        #expect(finder(fx).sessions().count == 1)
    }

    @Test func codexSessions() {
        let fx = FixtureTree()
        make(fx, "home/.codex/sessions/2026/09/01/rollout-x.jsonl", days: 20)
        make(fx, "home/.codex/sessions/2026/10/21/rollout-y.jsonl", days: 2)
        make(fx, "home/.codex/state.sqlite", days: 30)
        make(fx, "home/.codex/sessions/2026/09/01/logs.sqlite", days: 30)
        let s = finder(fx).sessions()
        #expect(s.map(\.id) == ["codex:rollout-x"])
    }

    @Test func geminiChats() {
        let fx = FixtureTree()
        make(fx, "home/.gemini/tmp/h1/chats/c.json", days: 20)
        let s = finder(fx).sessions()
        #expect(s.count == 1)
        #expect(s.first?.agent == "gemini")
        #expect(s.first?.project == "h1")
    }

    @Test func orderedByAgentThenDate() {
        let fx = FixtureTree()
        make(fx, "home/.gemini/tmp/h1/chats/c.json", days: 20)
        make(fx, "home/.codex/sessions/2026/09/01/rollout-x.jsonl", days: 20)
        make(fx, "home/.claude/projects/-p/55555555-5555-4555-8555-555555555555.jsonl", days: 10)
        make(fx, "home/.claude/projects/-p/44444444-4444-4444-8444-444444444444.jsonl", days: 15)
        #expect(finder(fx).sessions().map(\.id) == ["claude-code:44444444-4444-4444-8444-444444444444", "claude-code:55555555-5555-4555-8555-555555555555", "codex:rollout-x", "gemini:h1/c"])
    }

    @Test func nonUUIDNamesAreIgnored() {
        let fx = FixtureTree()
        make(fx, "home/.claude/projects/-p/foo/x", days: 30)
        make(fx, "home/.claude/projects/-p/.DS_Store", days: 30)
        make(fx, "home/.claude/file-history/notes/n", days: 30)
        make(fx, "home/.claude/todos/x.json", days: 30)
        for d in ["projects/-p/foo", "file-history/notes"] { touch(fx, "home/.claude/" + d, days: 30) }
        #expect(finder(fx).sessions().isEmpty)
    }

    @Test func deepWorktreeInJobKeepsJobOut() {
        let fx = FixtureTree()
        make(fx, "home/.claude/jobs/j5/state.json", days: 20)
        try! "{\"state\":\"done\"}".write(to: fx.url("home/.claude/jobs/j5/state.json"), atomically: true, encoding: .utf8)
        touch(fx, "home/.claude/jobs/j5/state.json", days: 20)
        make(fx, "home/.claude/jobs/j5/tmp/a/b/wt/.git", days: 20)
        try! "gitdir: /x/.git/worktrees/wt".write(to: fx.url("home/.claude/jobs/j5/tmp/a/b/wt/.git"), atomically: true, encoding: .utf8)
        touch(fx, "home/.claude/jobs/j5/tmp/a/b/wt/.git", days: 20)
        #expect(finder(fx).sessions().isEmpty)
    }
}
