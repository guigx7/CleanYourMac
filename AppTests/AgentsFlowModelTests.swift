import Testing
import Foundation
@testable import CleanYourMacCore
@testable import CleanYourMac

struct FakeAgentsScan: AgentsScanning {
    var report: AgentsReport
    func run() -> AsyncThrowingStream<AgentsScanEvent, Error> {
        let report = report
        return AsyncThrowingStream { cont in
            cont.yield(.progress("worktrees"))
            cont.yield(.finished(report))
            cont.finish()
        }
    }
}

final class RecordingAgentsRemover: AgentsRemoving, @unchecked Sendable {
    private(set) var removed: [[String]] = []
    var failing: Set<String> = []
    func remove(_ targets: [AgentsTarget]) async -> [String: Result<Void, CleanFailure>] {
        removed.append(targets.map(\.id))
        return Dictionary(uniqueKeysWithValues: targets.map {
            ($0.id, failing.contains($0.id) ? .failure(CleanFailure(reason: "denied")) : .success(()))
        })
    }
}

@MainActor
struct AgentsSetup {
    let remover = RecordingAgentsRemover()
    let model: AgentsFlowModel
    static let home = URL(fileURLWithPath: "/u")
    static let now = Date(timeIntervalSince1970: 1_792_000_000)

    static func entry(_ name: String, recent: Bool, sizes: [Int64]) -> WorktreeEntry {
        let wt = home.appendingPathComponent(".codex/worktrees/\(name)")
        let items = sizes.enumerated().map { i, size in
            RebuildableItem(url: wt.appendingPathComponent("p\(i)/node_modules"), worktree: wt, name: "node_modules", size: size, modified: now)
        }
        return WorktreeEntry(worktree: Worktree(url: wt, repo: nil, branch: nil, isOrphan: false), items: items, lastActivity: now,
                             isRecent: recent)
    }

    static func session(_ id: String, _ size: Int64) -> AgentSession {
        AgentSession(id: id, agent: "claude-code", project: nil, urls: [home.appendingPathComponent(".claude/projects/\(id)")], size: size,
                     lastModified: now, isOrphanRemains: false)
    }

    /// Worktree parada (2 pastas, 300), worktree recente (1 pasta, 50) e 2 sessões (10 e 20).
    static var report: AgentsReport {
        AgentsReport(home: home, worktrees: [entry("idle", recent: false, sizes: [100, 200]), entry("busy", recent: true, sizes: [50])],
                     sessions: [session("s1", 10), session("s2", 20)], buildFoldersSkipped: false)
    }

    static let idle = "/u/.codex/worktrees/idle/p0/node_modules"
    static let busy = "/u/.codex/worktrees/busy/p0/node_modules"

    init(report: AgentsReport = AgentsSetup.report, dryRun: Bool = false) {
        model = AgentsFlowModel(scan: FakeAgentsScan(report: report), remover: remover, dryRun: dryRun)
    }

    func scanned() async -> AgentsFlowModel {
        model.start()
        while model.phase == .scanning { await Task.yield() }
        return model
    }
}

@MainActor
@Suite struct AgentsFlowModelTests {
    @Test func scanToResults() async {
        let m = await AgentsSetup().scanned()
        #expect(m.phase == .results)
        #expect(m.selection.isEmpty && m.report?.total == 5)
    }

    @Test func emptyIsNothingFound() async {
        let empty = AgentsReport(home: AgentsSetup.home, worktrees: [], sessions: [], buildFoldersSkipped: false)
        let m = await AgentsSetup(report: empty).scanned()
        #expect(m.phase == .nothingFound)
    }

    @Test func tileCleanSelectsOnlySafeAndConfirms() async throws {
        let m = await AgentsSetup().scanned()
        let tile = try #require(m.report?.tiles.first { $0.kind == .worktrees })
        m.cleanTile(tile)
        #expect(m.selection == tile.ids && !m.selection.contains(AgentsSetup.busy))
        #expect(m.selectedCount == 2 && m.selectedSize == 300)
        #expect(m.confirmingRemoval && m.phase == .results)
    }

    @Test func recentWorktreeSelectableByHand() async {
        let m = await AgentsSetup().scanned()
        m.toggle(AgentsSetup.busy)
        #expect(m.selection == [AgentsSetup.busy] && m.selectedSize == 50)
        m.toggle(AgentsSetup.busy)
        #expect(m.selection.isEmpty)
        m.setAll(["s1", "s2"], selected: true)
        #expect(m.selectedCount == 2 && m.selectedSize == 30)
        m.setAll(["s1"], selected: false)
        #expect(m.selection == ["s2"])
    }

    @Test func openManagerAutoselectsTheTileOfTheSection() async {
        let m = await AgentsSetup().scanned()
        m.openManager(.worktrees)
        #expect(m.managerOpen && m.selection.isEmpty)
        m.openManager(.sessions, autoselect: true)
        #expect(m.selection == ["s1", "s2"] && m.section == .sessions)
    }

    @Test func stopIgnoresQueuedResult() async {
        let s = AgentsSetup()
        s.model.start()
        s.model.stop()
        for _ in 0..<20 { await Task.yield() }
        #expect(s.model.phase == .intro && s.model.report == nil)
    }

    @Test func removalUpdatesReportAndOutcome() async {
        let s = AgentsSetup()
        s.remover.failing = ["s2"]
        let m = await s.scanned()
        m.setAll([AgentsSetup.idle, "s1", "s2"], selected: true)
        m.requestRemoval()
        #expect(m.confirmingRemoval)
        m.confirmRemoval()
        while m.phase == .removing { await Task.yield() }
        #expect(s.remover.removed == [[AgentsSetup.idle, "s1", "s2"]])
        guard case .done(let o) = m.phase else { Issue.record("deveria concluir"); return }
        #expect(o.removed == 2 && o.freed == 110 && o.failed == ["s2": "denied"])
        #expect(m.report?.sessions.map(\.id) == ["s2"])
        #expect(m.report?.worktrees.first?.items.count == 1)
        #expect(m.selection == ["s2"])
        m.reviewMore()
        #expect(m.managerOpen && m.phase == .results)
    }

    @Test func backClearsSelection() async {
        let m = await AgentsSetup().scanned()
        m.toggle("s1")
        m.back()
        #expect(m.phase == .intro && m.selection.isEmpty)
    }
}
