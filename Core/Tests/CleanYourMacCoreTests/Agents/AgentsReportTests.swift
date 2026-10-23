import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct AgentsReportTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ wt: String, _ rel: String, size: Int64) -> RebuildableItem {
        RebuildableItem(url: URL(fileURLWithPath: wt + "/" + rel, isDirectory: true), worktree: URL(fileURLWithPath: wt, isDirectory: true),
                        name: (rel as NSString).lastPathComponent, size: size, modified: now)
    }

    private func entry(_ wt: String, _ items: [RebuildableItem], recent: Bool) -> WorktreeEntry {
        WorktreeEntry(worktree: Worktree(url: URL(fileURLWithPath: wt, isDirectory: true), repo: URL(fileURLWithPath: "/r"), branch: "b",
                                         isOrphan: false),
                      items: items, lastActivity: now, isRecent: recent)
    }

    private func session(_ agent: String, _ id: String, size: Int64) -> AgentSession {
        AgentSession(id: "\(agent):\(id)", agent: agent, project: nil, urls: [URL(fileURLWithPath: "/h/.x/\(id)")], size: size,
                     lastModified: now, isOrphanRemains: false)
    }

    private func sample() -> AgentsReport {
        let old = entry("/w/a", [item("/w/a", "node_modules", size: 100), item("/w/a", "dist", size: 50)], recent: false)
        let fresh = entry("/w/b", [item("/w/b", "node_modules", size: 1000)], recent: true)
        return AgentsReport(home: URL(fileURLWithPath: "/h"), worktrees: [old, fresh],
                            sessions: [session("claude-code", "s1", size: 10), session("claude-code", "s2", size: 20),
                                       session("codex", "rollout-1", size: 5)],
                            buildFoldersSkipped: false)
    }

    @Test func tilesOnlySafe() {
        let r = sample()
        #expect(r.tiles.count == 3)
        let wt = r.tiles.first { $0.kind == .worktrees }
        #expect(wt?.count == 1)
        #expect(wt?.size == 150)
        #expect(wt?.ids == ["/w/a/node_modules", "/w/a/dist"])
        let claude = r.tiles.first { $0.kind == .sessions(agent: "claude-code") }
        #expect(claude?.count == 2)
        #expect(claude?.size == 30)
        #expect(claude?.ids == ["claude-code:s1", "claude-code:s2"])
        let codex = r.tiles.first { $0.kind == .sessions(agent: "codex") }
        #expect(codex?.count == 1 && codex?.size == 5)
        #expect(!r.tiles.contains { $0.kind == .sessions(agent: "gemini") })
        // Ordem: worktrees, depois as sessões na ordem do catálogo.
        #expect(r.tiles.map(\.kind) == [.worktrees, .sessions(agent: "claude-code"), .sessions(agent: "codex")])
        #expect(r.total == 6)
        #expect(!r.isEmpty)
    }

    @Test func removingDropsEmpty() {
        let r = sample().removing(["/w/a/node_modules", "/w/a/dist", "claude-code:s1"])
        #expect(r.worktrees.map(\.worktree.url.path) == ["/w/b"])
        // A worktree que sobrou está em uso: sem cartão de worktrees.
        #expect(!r.tiles.contains { $0.kind == .worktrees })
        #expect(r.tiles.first { $0.kind == .sessions(agent: "claude-code") }?.count == 1)
        #expect(r.total == 3)
        let partial = sample().removing(["/w/a/dist"])
        #expect(partial.worktrees.first?.items.map(\.name) == ["node_modules"])
        #expect(partial.tiles.first { $0.kind == .worktrees }?.size == 100)
        let none = sample().removing(Set(sample().worktrees.flatMap(\.items).map(\.url.path)).union(sample().sessions.map(\.id)))
        #expect(none.isEmpty && none.tiles.isEmpty)
    }

    @Test func targetsCarryAnalysisData() {
        let r = sample()
        let t = r.targets(for: ["/w/a/dist", "codex:rollout-1", "desconhecido"])
        #expect(t.count == 2)
        let dist = t.first { $0.id == "/w/a/dist" }
        #expect(dist?.urls.map(\.path) == ["/w/a/dist"])
        #expect(dist?.root.path == "/w/a")
        #expect(dist?.activity == now)
        #expect(dist?.size == 50)
        let codex = t.first { $0.id == "codex:rollout-1" }
        #expect(codex?.root.path == "/h/.codex")
        #expect(codex?.modified == now)
    }
}
