import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct AgentsRemovalTests {
    private let now = Date()
    private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    private func setDate(_ url: URL, _ date: Date) {
        try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func reason(_ r: [String: Result<Void, CleanFailure>], _ id: String) -> String? {
        if case .failure(let f) = r[id] { return f.reason }
        return nil
    }

    private func succeeded(_ r: [String: Result<Void, CleanFailure>], _ id: String) -> Bool {
        if case .success = r[id] { return true }
        return false
    }

    /// Worktree órfã (sem git): só `node_modules`, analisada de verdade pelo `RebuildableFinder`.
    private func worktreeReport(_ fx: FixtureTree, home: URL, nodeModules: [String] = ["node_modules"]) -> AgentsReport {
        fx.file("home/wt/src/a.js", bytes: 100, modified: ago(3))
        for rel in nodeModules { fx.file("home/wt/\(rel)/pkg/index.js", bytes: 500, modified: ago(3)) }
        let wt = Worktree(url: fx.url("home/wt"), repo: nil, branch: nil, isOrphan: true)
        let entry = RebuildableFinder(git: nil, now: now).entry(for: wt)
        return AgentsReport(home: home, worktrees: entry.map { [$0] } ?? [], sessions: [], buildFoldersSkipped: true)
    }

    private func remover(_ fx: FixtureTree, _ trasher: FixtureTrasher, dryRun: Bool = false) -> AgentsRemover {
        AgentsRemover(trasher: trasher, home: fx.url("home"), dryRun: dryRun, log: CleanupLog(directory: fx.url("logs")))
    }

    /// Arquivo com data antiga e a mesma data nas pastas até `home/.claude`.
    private func make(_ fx: FixtureTree, _ rel: String, days: Double) {
        fx.file(rel, bytes: 100, modified: ago(days))
        var dir = (rel as NSString).deletingLastPathComponent
        while dir != "home" {
            setDate(fx.url(dir), ago(days))
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    private func claudeSession(_ fx: FixtureTree, _ id: String) {
        make(fx, "home/.claude/projects/-p/\(id).jsonl", days: 10)
        make(fx, "home/.claude/projects/-p/\(id)/subagents/a.jsonl", days: 10)
        make(fx, "home/.claude/todos/\(id)-agent-x.json", days: 10)
    }

    @Test func trashesUnchangedRebuildable() async throws {
        let fx = FixtureTree()
        let home = fx.dir("home")
        // `plugins` no meio do caminho não protege um `node_modules` de projeto.
        let report = worktreeReport(fx, home: home, nodeModules: ["plugins/node_modules"])
        let ids = Set(report.worktrees.flatMap(\.items).map(\.url.path))
        #expect(ids == [fx.url("home/wt/plugins/node_modules").path])
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher).remove(report.targets(for: ids))
        for id in ids { #expect(succeeded(r, id), "\(id): \(reason(r, id) ?? "")") }
        #expect(trasher.trashed.count == 1)
    }

    @Test func refusesWhenWorktreeChanged() async throws {
        let fx = FixtureTree()
        let home = fx.dir("home")
        let report = worktreeReport(fx, home: home)
        let nm = fx.url("home/wt/node_modules").path
        let targets = report.targets(for: [nm])
        #expect(targets.count == 1)
        setDate(fx.url("home/wt/node_modules"), ago(1))
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher).remove(targets)
        #expect(reason(r, nm) == "item changed")
        #expect(trasher.trashed.isEmpty)

        // O agente voltou a mexer na worktree (arquivo fora das recriáveis mais novo que na análise).
        let fx2 = FixtureTree()
        let report2 = worktreeReport(fx2, home: fx2.dir("home"))
        let nm2 = fx2.url("home/wt/node_modules").path
        setDate(fx2.url("home/wt/src/a.js"), now)
        let trasher2 = FixtureTrasher(fx2.url("trash"))
        let r2 = await remover(fx2, trasher2).remove(report2.targets(for: [nm2]))
        #expect(reason(r2, nm2) == "item changed")
        #expect(trasher2.trashed.isEmpty)
    }

    @Test func refusesSymlinkAndOutsideRoot() async throws {
        let fx = FixtureTree()
        let home = fx.dir("home")
        let report = worktreeReport(fx, home: home)
        let nm = fx.url("home/wt/node_modules")
        let target = report.targets(for: [nm.path])[0]
        // O alvo virou link.
        try FileManager.default.moveItem(at: nm, to: fx.url("home/elsewhere"))
        fx.symlink("home/wt/node_modules", to: fx.url("home/elsewhere"))
        // Fora da worktree.
        fx.dir("home/other/node_modules")
        let outside = AgentsTarget(id: fx.url("home/other/node_modules").path, urls: [fx.url("home/other/node_modules")], modified: nil,
                                   root: fx.url("home/wt"), size: 1, kind: .rebuildable(name: "node_modules", isOrphanWorktree: true))
        // Dentro da worktree, mas não é uma recriável .
        let notRebuildable = AgentsTarget(id: fx.url("home/wt/src").path, urls: [fx.url("home/wt/src")], modified: nil,
                                          root: fx.url("home/wt"), size: 1, kind: .rebuildable(name: "node_modules", isOrphanWorktree: true))
        // Sessões: caminhos do `neverTouch` e fora da raiz do agente.
        make(fx, "home/.claude/history.jsonl", days: 30)
        make(fx, "home/.claude/projects/-p/memory/MEMORY.md", days: 30)
        make(fx, "home/.claude/plugins/x.json", days: 30)
        make(fx, "home/.codex/state.sqlite", days: 30)
        fx.file("home/Documents/x.txt", bytes: 10, modified: ago(30))
        func session(_ id: String, _ rels: [String], root: String) -> AgentsTarget {
            AgentsTarget(id: id, urls: rels.map { fx.url($0) }, modified: now, root: fx.url(root), size: 1, kind: .session)
        }
        let sessions = [
            session("claude-code:history", ["home/.claude/history.jsonl"], root: "home/.claude"),
            session("claude-code:memory", ["home/.claude/projects/-p/memory"], root: "home/.claude"),
            session("claude-code:plugins", ["home/.claude/plugins/x.json"], root: "home/.claude"),
            session("codex:db", ["home/.codex/state.sqlite"], root: "home/.codex"),
            session("claude-code:docs", ["home/Documents/x.txt"], root: "home/.claude"),
            session("codex:wrong-root", ["home/.claude/todos"], root: "home/.codex"),
        ]
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher).remove([target, outside, notRebuildable] + sessions)
        #expect(reason(r, nm.path) == "item changed")
        #expect(reason(r, outside.id) == "kept: protected")
        #expect(reason(r, notRebuildable.id) == "kept: protected")
        for s in sessions { #expect(reason(r, s.id) == "kept: protected", "\(s.id)") }
        #expect(trasher.trashed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fx.url("home/.claude/history.jsonl").path))
    }

    @Test func sessionRemovedAsUnit() async throws {
        let fx = FixtureTree()
        let home = fx.dir("home")
        let a = "11111111-1111-4111-8111-111111111111", b = "22222222-2222-4222-8222-222222222222"
        claudeSession(fx, a)
        claudeSession(fx, b)
        let sessions = SessionFinder(home: home, now: now, worktrees: []).sessions()
        #expect(sessions.map { $0.urls.count } == [3, 3])
        let report = AgentsReport(home: home, worktrees: [], sessions: sessions, buildFoldersSkipped: false)
        #expect(report.targets(for: ["claude-code:\(a)"]).first?.root.path == fx.url("home/.claude").path)
        // Na sessão `b`, uma das três urls mudou depois da análise.
        setDate(fx.url("home/.claude/todos/\(b)-agent-x.json"), now)
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher).remove(report.targets(for: ["claude-code:\(a)", "claude-code:\(b)"]))
        #expect(succeeded(r, "claude-code:\(a)"))
        #expect(reason(r, "claude-code:\(b)") == "item changed")
        #expect(Set(trasher.trashed.map(\.lastPathComponent)) == ["\(a).jsonl", a, "\(a)-agent-x.json"])
        #expect(FileManager.default.fileExists(atPath: fx.url("home/.claude/projects/-p/\(b).jsonl").path))
        #expect(FileManager.default.fileExists(atPath: fx.url("home/.claude/projects/-p/\(b)").path))
    }

    @Test func dryRunAndLog() async throws {
        let fx = FixtureTree()
        let home = fx.dir("home")
        let a = "11111111-1111-4111-8111-111111111111"
        claudeSession(fx, a)
        let wtReport = worktreeReport(fx, home: home)
        let sessions = SessionFinder(home: home, now: now, worktrees: []).sessions()
        let report = AgentsReport(home: home, worktrees: wtReport.worktrees, sessions: sessions, buildFoldersSkipped: true)
        let nm = fx.url("home/wt/node_modules").path
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher, dryRun: true).remove(report.targets(for: [nm, "claude-code:\(a)"]))
        #expect(succeeded(r, nm) && succeeded(r, "claude-code:\(a)"))
        #expect(trasher.trashed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: nm))
        #expect(FileManager.default.fileExists(atPath: fx.url("home/.claude/projects/-p/\(a).jsonl").path))
        let logs = try FileManager.default.contentsOfDirectory(atPath: fx.url("logs").path)
        #expect(logs.count == 1 && logs[0].hasPrefix("agents-") && logs[0].hasSuffix(".json"))
        let log = try JSONDecoder.iso.decode(CleanReport.self, from: Data(contentsOf: fx.url("logs/" + logs[0])))
        #expect(log.dryRun && Set(log.removed) == [nm, "claude-code:\(a)"])
        #expect(log.freedBytes == report.targets(for: [nm, "claude-code:\(a)"]).reduce(0) { $0 + $1.size })
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
