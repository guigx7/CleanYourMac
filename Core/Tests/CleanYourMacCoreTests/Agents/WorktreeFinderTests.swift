import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct WorktreeFinderTests {
    private func find(_ fx: FixtureTree) throws -> [Worktree] {
        try WorktreeFinder(home: fx.root).worktrees(isCancelled: { false })
    }

    /// Monta um repositório com o registro de uma worktree ligada (sem rodar o git).
    private func link(_ fx: FixtureTree, repo: String, name: String, worktree: String,
                      gitdir: String? = nil, head: String = "ref: refs/heads/feature\n") {
        fx.dir("\(repo)/.git")
        fx.dir("\(repo)/.git/worktrees/\(name)")
        try! (gitdir ?? fx.url("\(worktree)/.git").path).write(to: fx.url("\(repo)/.git/worktrees/\(name)/gitdir"), atomically: true, encoding: .utf8)
        try! head.write(to: fx.url("\(repo)/.git/worktrees/\(name)/HEAD"), atomically: true, encoding: .utf8)
        fx.dir(worktree)
        try! "gitdir: \(fx.url("\(repo)/.git/worktrees/\(name)").path)\n".write(to: fx.url("\(worktree)/.git"), atomically: true, encoding: .utf8)
    }

    @Test func linkedWorktreesFromGitdir() throws {
        let fx = FixtureTree()
        link(fx, repo: "Projetos/a", name: "w1", worktree: "Projetos/a-w1")
        let r = try find(fx)
        #expect(r.count == 1)
        #expect(r.first?.url.path == fx.url("Projetos/a-w1").path)
        #expect(r.first?.repo?.path == fx.url("Projetos/a").path)
        #expect(r.first?.branch == "feature")
        #expect(r.first?.isOrphan == false)
    }

    @Test func detachedHeadHasNoBranch() throws {
        let fx = FixtureTree()
        link(fx, repo: "Projetos/a", name: "w1", worktree: "Projetos/a-w1", head: "0123456789abcdef0123456789abcdef01234567\n")
        #expect(try find(fx).first?.branch == nil)
    }

    @Test func gitdirVariants() throws {
        let fx = FixtureTree()
        // gitdir relativo, resolvido a partir de .git/worktrees/w2.
        link(fx, repo: "Projetos/a", name: "w2", worktree: "Projetos/a-w2", gitdir: "../../../../a-w2/.git")
        // Espaço e acento.
        link(fx, repo: "Projetos/a", name: "w3", worktree: "Projetos/São Paulo w3")
        // Registro sobrando: pasta da worktree apagada.
        link(fx, repo: "Projetos/a", name: "w4", worktree: "Projetos/a-w4")
        try FileManager.default.removeItem(at: fx.url("Projetos/a-w4"))
        // .git da worktree aponta para outro repositório.
        link(fx, repo: "Projetos/a", name: "w5", worktree: "Projetos/a-w5")
        fx.dir("Projetos/b/.git/worktrees/w5")
        try "gitdir: \(fx.url("Projetos/b/.git/worktrees/w5").path)\n".write(to: fx.url("Projetos/a-w5/.git"), atomically: true, encoding: .utf8)
        let paths = try find(fx).map(\.url.path)
        #expect(paths == [fx.url("Projetos/São Paulo w3").path, fx.url("Projetos/a-w2").path])
    }

    @Test func outsideHomeSkipped() throws {
        let fx = FixtureTree()
        link(fx, repo: "Projetos/a", name: "w1", worktree: "Projetos/a-w1", gitdir: "/private/tmp/x/.git")
        #expect(try find(fx).isEmpty)
    }

    @Test func agentRootOrphan() throws {
        let fx = FixtureTree()
        fx.dir(".claude/jobs/j1/tmp/wt")
        try "gitdir: \(fx.url("Projetos/sumiu/.git/worktrees/wt").path)\n".write(to: fx.url(".claude/jobs/j1/tmp/wt/.git"), atomically: true, encoding: .utf8)
        let r = try find(fx)
        #expect(r.count == 1)
        #expect(r.first?.isOrphan == true)
        #expect(r.first?.repo == nil)
        #expect(r.first?.url.path == fx.url(".claude/jobs/j1/tmp/wt").path)
    }

    @Test func repoClaudeWorktreesAreCandidates() throws {
        let fx = FixtureTree()
        link(fx, repo: "Projetos/a", name: "x", worktree: "Projetos/a/.claude/worktrees/x")
        let r = try find(fx)
        #expect(r.count == 1)
        #expect(r.first?.isOrphan == false)
        #expect(r.first?.repo?.path == fx.url("Projetos/a").path)
    }

    @Test func walkSkipsLibraryAndNodeModules() throws {
        let fx = FixtureTree()
        link(fx, repo: "Projetos/a/node_modules/pkg", name: "w", worktree: "Projetos/pkg-w")
        link(fx, repo: "Library/x", name: "w", worktree: "Projetos/lib-w")
        #expect(try find(fx).isEmpty)
    }

    @Test func cancellationThrows() throws {
        let fx = FixtureTree()
        for i in 0..<1100 { fx.dir("Projetos/d\(i)") }
        #expect(throws: CancellationError.self) {
            try WorktreeFinder(home: fx.root).worktrees(isCancelled: { true })
        }
    }
}
