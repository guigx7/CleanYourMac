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
        fx.age("home/wt", ago(3))
        let wt = Worktree(url: fx.url("home/wt"), repo: nil, branch: nil, isOrphan: true)
        let entry = RebuildableFinder(git: nil, now: now, home: home).entry(for: wt)
        return AgentsReport(home: home, worktrees: entry.map { [$0] } ?? [], sessions: [], buildFoldersSkipped: true)
    }

    private func remover(_ fx: FixtureTree, _ trasher: FixtureTrasher, dryRun: Bool = false, git: GitTool? = nil) -> AgentsRemover {
        AgentsRemover(trasher: trasher, home: fx.url("home"), dryRun: dryRun, log: CleanupLog(directory: fx.url("logs")), git: git)
    }

    private func git(_ runner: GitRunnerStub) -> GitTool {
        GitTool(executable: "/Library/Developer/CommandLineTools/usr/bin/git", runner: runner)
    }

    /// Worktree ligada (com git), com `node_modules` e as pastas de build pedidas, analisada pelo `RebuildableFinder`.
    private func linkedReport(_ fx: FixtureTree, build: [String], runner: GitRunnerStub) -> AgentsReport {
        fx.file("home/wt/src/a.js", bytes: 100, modified: ago(3))
        fx.file("home/wt/package.json", bytes: 10, modified: ago(3))
        for rel in ["node_modules"] + build { fx.file("home/wt/\(rel)/pkg/index.js", bytes: 500, modified: ago(3)) }
        fx.age("home/wt", ago(3))
        let wt = Worktree(url: fx.url("home/wt"), repo: fx.url("home/repo"), branch: "b", isOrphan: false)
        let entry = RebuildableFinder(git: git(runner), now: now, home: fx.url("home")).entry(for: wt)
        return AgentsReport(home: fx.url("home"), worktrees: entry.map { [$0] } ?? [], sessions: [], buildFoldersSkipped: false)
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

    // MARK: - Fix round 1

    /// Rastreado (ou deixou de ser ignorado) depois da análise: o git é consultado de novo antes do Lixo.
    @Test func gitRecheckedBeforeTrash() async throws {
        let fx = FixtureTree()
        let analysis = GitRunnerStub(ignored: ["dist"])
        let report = linkedReport(fx, build: ["dist"], runner: analysis)
        let nm = fx.url("home/wt/node_modules").path, dist = fx.url("home/wt/dist").path
        #expect(Set(report.worktrees.flatMap(\.items).map(\.url.path)) == [nm, dist])
        let targets = report.targets(for: [nm, dist])

        // Mesmo git da análise: passa.
        let ok = await remover(fx, FixtureTrasher(fx.url("trash")), dryRun: true, git: git(analysis)).remove(targets)
        #expect(succeeded(ok, nm) && succeeded(ok, dist))

        // Depois da análise: `node_modules` passou a ser rastreada e `dist` deixou de ser ignorada.
        let later = GitRunnerStub(ignored: [], tracked: ["node_modules"])
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher, git: git(later)).remove(targets)
        #expect(reason(r, nm) == "item changed")
        #expect(reason(r, dist) == "item changed")
        #expect(trasher.trashed.isEmpty)
        #expect(later.calls.contains { $0.contains("ls-files") } && later.calls.contains { $0.contains("check-ignore") })
    }

    /// A 2ª url de uma sessão é negada pelo Lixo: a razão e o registro dizem o que já foi.
    @Test func partialSessionIsReported() async throws {
        let fx = FixtureTree()
        let home = fx.dir("home")
        let a = "11111111-1111-4111-8111-111111111111"
        claudeSession(fx, a)
        let sessions = SessionFinder(home: home, now: now, worktrees: []).sessions()
        let report = AgentsReport(home: home, worktrees: [], sessions: sessions, buildFoldersSkipped: false)
        let urls = sessions[0].urls
        #expect(urls.count == 3)
        let trasher = FixtureTrasher(fx.url("trash"))
        trasher.deny = [urls[1].path]
        let id = "claude-code:\(a)"
        let r = await remover(fx, trasher).remove(report.targets(for: [id]))
        let why = reason(r, id) ?? ""
        #expect(why.hasPrefix("partial: 1 moved"))
        #expect(why.contains(urls[0].path) && !why.contains(urls[2].path))
        #expect(trasher.trashed == [urls[0]])
        let logs = try FileManager.default.contentsOfDirectory(atPath: fx.url("logs").path)
        let log = try JSONDecoder.iso.decode(CleanReport.self, from: Data(contentsOf: fx.url("logs/" + logs[0])))
        #expect(log.removed.isEmpty)
        #expect(log.failed[id] == why)
    }

    @Test func parentBecameLinkIsRefused() async throws {
        // Recriável: `apps/web` virou link depois da análise.
        let fx = FixtureTree()
        let report = worktreeReport(fx, home: fx.dir("home"), nodeModules: ["apps/web/node_modules"])
        let nm = fx.url("home/wt/apps/web/node_modules").path
        let targets = report.targets(for: [nm])
        #expect(targets.count == 1)
        try FileManager.default.moveItem(at: fx.url("home/wt/apps/web"), to: fx.url("home/wt/apps/web-real"))
        fx.symlink("home/wt/apps/web", to: fx.url("home/wt/apps/web-real"))
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher).remove(targets)
        #expect(reason(r, nm) == "item changed")

        // Sessão: a pasta do projeto virou link.
        let fx2 = FixtureTree()
        let home2 = fx2.dir("home")
        let a = "11111111-1111-4111-8111-111111111111"
        claudeSession(fx2, a)
        let report2 = AgentsReport(home: home2, worktrees: [], sessions: SessionFinder(home: home2, now: now, worktrees: []).sessions(),
                                   buildFoldersSkipped: false)
        let targets2 = report2.targets(for: ["claude-code:\(a)"])
        #expect(targets2.count == 1)
        let p = fx2.url("home/.claude/projects/-p")
        let date = try FileManager.default.attributesOfItem(atPath: p.path)[.modificationDate] as! Date
        try FileManager.default.moveItem(at: p, to: fx2.url("home/.claude/projects/-q"))
        fx2.symlink("home/.claude/projects/-p", to: fx2.url("home/.claude/projects/-q"))
        setDate(fx2.url("home/.claude/projects"), date)
        let trasher2 = FixtureTrasher(fx2.url("trash"))
        let r2 = await remover(fx2, trasher2).remove(targets2)
        #expect(reason(r2, "claude-code:\(a)") == "item changed")
        #expect(trasher.trashed.isEmpty && trasher2.trashed.isEmpty)
    }

    @Test func differentSpellingIsRefused() async throws {
        let fx = FixtureTree()
        let report = worktreeReport(fx, home: fx.dir("home"))
        let nm = fx.url("home/wt/node_modules")
        let targets = report.targets(for: [nm.path])
        // Renomeada só na caixa (o `lstat` do APFS ainda acharia `node_modules`).
        try FileManager.default.moveItem(at: nm, to: fx.url("home/wt/nm-tmp"))
        try FileManager.default.moveItem(at: fx.url("home/wt/nm-tmp"), to: fx.url("home/wt/Node_Modules"))
        let manual = AgentsTarget(id: fx.url("home/wt/Node_Modules").path, urls: [fx.url("home/wt/Node_Modules")], modified: nil,
                                  root: fx.url("home/wt"), size: 1, kind: .rebuildable(name: "node_modules", isOrphanWorktree: true))
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher).remove(targets + [manual])
        #expect(reason(r, nm.path) == "item changed")
        #expect(reason(r, manual.id) == "kept: protected")
        #expect(trasher.trashed.isEmpty)
    }

    /// `.angular/cache` é conferido pelas duas partes: `.Angular/cache` e `.angular/Cache` são recusadas.
    @Test func angularCacheCheckedByBothParts() async throws {
        for rename in [nil, (".angular", ".Angular"), (".angular/cache", ".angular/Cache")] as [(String, String)?] {
            let fx = FixtureTree()
            let stub = GitRunnerStub(ignored: [".angular/cache"])
            let report = linkedReport(fx, build: [".angular/cache"], runner: stub)
            let cache = fx.url("home/wt/.angular/cache").path
            let targets = report.targets(for: [cache])
            #expect(targets.count == 1)
            if let (from, to) = rename {
                try FileManager.default.moveItem(at: fx.url("home/wt/" + from), to: fx.url("home/wt/tmp-rename"))
                try FileManager.default.moveItem(at: fx.url("home/wt/tmp-rename"), to: fx.url("home/wt/" + to))
            }
            let r = await remover(fx, FixtureTrasher(fx.url("trash")), dryRun: true, git: git(stub)).remove(targets)
            if rename == nil { #expect(succeeded(r, cache), "\(reason(r, cache) ?? "")") }
            else { #expect(reason(r, cache) == "item changed", "\(rename!)") }
        }
        // Só `cache`, fora de `.angular`: não é a recriável do catálogo.
        let fx = FixtureTree()
        fx.dir("home/wt/cache")
        let manual = AgentsTarget(id: fx.url("home/wt/cache").path, urls: [fx.url("home/wt/cache")], modified: nil, root: fx.url("home/wt"),
                                  size: 1, kind: .rebuildable(name: ".angular/cache", isOrphanWorktree: false))
        let r = await remover(fx, FixtureTrasher(fx.url("trash"))).remove([manual])
        #expect(reason(r, manual.id) == "kept: protected")
    }

    @Test func sessionFolderWithProtectedInsideIsRefused() async throws {
        let fx = FixtureTree()
        let home = fx.dir("home")
        let a = "11111111-1111-4111-8111-111111111111"
        claudeSession(fx, a)
        make(fx, "home/.claude/projects/-p/\(a)/subagents/cache.sqlite", days: 10)
        let report = AgentsReport(home: home, worktrees: [], sessions: SessionFinder(home: home, now: now, worktrees: []).sessions(),
                                  buildFoldersSkipped: false)
        let targets = report.targets(for: ["claude-code:\(a)"])
        #expect(targets.count == 1)
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher).remove(targets)
        #expect(reason(r, "claude-code:\(a)") == "kept: protected")
        #expect(trasher.trashed.isEmpty)
    }

    // MARK: - Revisão final

    /// C1: o produtor (`package.json` ao lado) some depois da análise → a pasta de build não sai.
    @Test func producerRecheckedBeforeTrash() async throws {
        let fx = FixtureTree()
        let stub = GitRunnerStub(ignored: ["dist"])
        let report = linkedReport(fx, build: ["dist"], runner: stub)
        let dist = fx.url("home/wt/dist").path
        let targets = report.targets(for: [dist])
        #expect(targets.count == 1)
        try FileManager.default.removeItem(at: fx.url("home/wt/package.json"))
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher, git: git(stub)).remove(targets)
        #expect(reason(r, dist) == "item changed")
        #expect(trasher.trashed.isEmpty)

        // Alvo montado à mão para uma pasta de código sem produtor: também recusado.
        let fx2 = FixtureTree()
        fx2.file("home/wt/src/services/coverage/load-coverage.ts", bytes: 10, modified: ago(3))
        fx2.file("home/wt/package.json", bytes: 10, modified: ago(3))
        let cov = fx2.url("home/wt/src/services/coverage")
        let st = try FileManager.default.attributesOfItem(atPath: cov.path)[.modificationDate] as? Date
        let manual = AgentsTarget(id: cov.path, urls: [cov], modified: st, root: fx2.url("home/wt"), size: 1,
                                  kind: .rebuildable(name: "coverage", isOrphanWorktree: false))
        let r2 = await remover(fx2, FixtureTrasher(fx2.url("trash")), git: git(GitRunnerStub(ignored: ["src/services/coverage"]))).remove([manual])
        #expect(reason(r2, manual.id) == "item changed")
    }

    /// C2: a remoção usa a mesma atividade da análise: mudança a 5 níveis ou sessão viva do agente na worktree recusam.
    @Test func refusesDeepChangeAndLiveAgent() async throws {
        let fx = FixtureTree()
        fx.file("home/wt/apps/web/src/app/page.tsx", bytes: 10)
        let report = worktreeReport(fx, home: fx.dir("home"))
        let nm = fx.url("home/wt/node_modules").path
        let targets = report.targets(for: [nm])
        #expect(targets.count == 1)
        #expect(succeeded(await remover(fx, FixtureTrasher(fx.url("trash")), dryRun: true).remove(targets), nm))
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fx.url("home/wt/apps/web/src/app/page.tsx").path)
        let r = await remover(fx, FixtureTrasher(fx.url("trash")), dryRun: true).remove(targets)
        #expect(reason(r, nm) == "item changed")

        let fx2 = FixtureTree()
        let report2 = worktreeReport(fx2, home: fx2.dir("home"))
        let nm2 = fx2.url("home/wt/node_modules").path
        let targets2 = report2.targets(for: [nm2])
        try Data("{\"pid\":\(getpid()),\"sessionId\":\"x\",\"cwd\":\"\(fx2.url("home/wt").path)\"}".utf8)
            .write(to: fx2.dir("home/.claude/sessions").appendingPathComponent("\(getpid()).json"))
        let trasher2 = FixtureTrasher(fx2.url("trash"))
        let r2 = await remover(fx2, trasher2).remove(targets2)
        #expect(reason(r2, nm2) == "item changed")
        #expect(trasher2.trashed.isEmpty)
    }

    /// Duas pastas da mesma worktree: mover a 1ª muda a data da pasta-mãe, e a 2ª não pode ser recusada por isso.
    @Test func secondItemOfSameWorktreeStillLeaves() async throws {
        let fx = FixtureTree()
        let stub = GitRunnerStub(ignored: ["dist"])
        let report = linkedReport(fx, build: ["dist"], runner: stub)
        let nm = fx.url("home/wt/node_modules").path, dist = fx.url("home/wt/dist").path
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher, git: git(stub)).remove(report.targets(for: [nm, dist]))
        #expect(succeeded(r, nm), "\(reason(r, nm) ?? "")")
        #expect(succeeded(r, dist), "\(reason(r, dist) ?? "")")
        #expect(trasher.trashed.count == 2)
    }

    /// M1: em worktree órfã, só `node_modules` pode sair, mesmo com um alvo de build montado à mão.
    @Test func orphanOnlyNodeModulesOnRemoval() async throws {
        let fx = FixtureTree()
        fx.file("home/wt/dist/a.js", bytes: 10, modified: ago(3))
        fx.file("home/wt/package.json", bytes: 10, modified: ago(3))
        let dist = fx.url("home/wt/dist")
        let date = try FileManager.default.attributesOfItem(atPath: dist.path)[.modificationDate] as? Date
        let manual = AgentsTarget(id: dist.path, urls: [dist], modified: date, root: fx.url("home/wt"), size: 1,
                                  kind: .rebuildable(name: "dist", isOrphanWorktree: true))
        let stub = GitRunnerStub(ignored: ["dist"])
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher, git: git(stub)).remove([manual])
        #expect(reason(r, manual.id) == "kept: protected")
        #expect(trasher.trashed.isEmpty)
    }

    @Test func otherNeverTouchPatternsAreProtected() async throws {
        let fx = FixtureTree()
        make(fx, "home/.claude/settings.json", days: 30)
        make(fx, "home/.claude/settings.local.json", days: 30)
        make(fx, "home/.claude/skills/x/SKILL.md", days: 30)
        make(fx, "home/.codex/skills/y.md", days: 30)
        make(fx, "home/.gemini/opencode.db", days: 30)
        let cases: [(String, String, String)] = [
            ("claude-code:s", "home/.claude/settings.json", "home/.claude"),
            ("claude-code:sl", "home/.claude/settings.local.json", "home/.claude"),
            ("claude-code:sk", "home/.claude/skills", "home/.claude"),
            ("codex:sk", "home/.codex/skills/y.md", "home/.codex"),
            ("gemini:db", "home/.gemini/opencode.db", "home/.gemini"),
        ]
        let targets = cases.map { AgentsTarget(id: $0.0, urls: [fx.url($0.1)], modified: now, root: fx.url($0.2), size: 1, kind: .session) }
        let trasher = FixtureTrasher(fx.url("trash"))
        let r = await remover(fx, trasher).remove(targets)
        for t in targets { #expect(reason(r, t.id) == "kept: protected", "\(t.id)") }
        #expect(trasher.trashed.isEmpty)
    }
}

/// Git falso: responde `check-ignore` e `ls-files` a partir de conjuntos fixos e guarda as chamadas.
final class GitRunnerStub: CommandRunner, @unchecked Sendable {
    let ignored: Set<String>
    let tracked: Set<String>
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }

    init(ignored: Set<String> = [], tracked: Set<String> = []) {
        self.ignored = ignored
        self.tracked = tracked
    }

    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        lock.lock(); _calls.append(arguments); lock.unlock()
        guard let sep = arguments.firstIndex(of: "--") else { return (128, "fatal") }
        let paths = arguments[(sep + 1)...].map { $0.hasPrefix(":(icase,literal)") ? String($0.dropFirst(":(icase,literal)".count)) : $0 }
        if arguments.contains("check-ignore") {
            let hits = paths.filter { ignored.contains($0) }
            return hits.isEmpty ? (1, "") : (0, hits.map { $0 + "\n" }.joined())
        }
        if arguments.contains("ls-files") {
            return (0, paths.filter { tracked.contains($0) }.map { $0 + "/a.js\n" }.joined())
        }
        return (128, "fatal")
    }
}


private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}