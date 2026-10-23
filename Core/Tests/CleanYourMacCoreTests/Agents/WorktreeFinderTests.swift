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

    @Test func prunedRegistryInAgentRootIsOrphanWithRepo() throws {
        let fx = FixtureTree()
        // Repositório oculto (fora da varredura): só o passo 2 acha a worktree.
        fx.dir(".repos/r/.git/worktrees")
        fx.dir(".codex/worktrees/x")
        try "gitdir: \(fx.url(".repos/r/.git/worktrees/x").path)\n".write(to: fx.url(".codex/worktrees/x/.git"), atomically: true, encoding: .utf8)
        let r = try find(fx)
        #expect(r.count == 1)
        #expect(r.first?.isOrphan == true)
        #expect(r.first?.repo?.path == fx.url(".repos/r").path)
        #expect(r.first?.branch == nil)
    }

    @Test func copiedFolderPointingToOtherRegistryIsOrphan() throws {
        let fx = FixtureTree()
        link(fx, repo: ".repos/r", name: "w1", worktree: ".claude/jobs/j1/tmp/original")
        fx.dir(".claude/jobs/j1/tmp/copia")
        try "gitdir: \(fx.url(".repos/r/.git/worktrees/w1").path)\n".write(to: fx.url(".claude/jobs/j1/tmp/copia/.git"), atomically: true, encoding: .utf8)
        let r = try find(fx)
        let copia = r.first { $0.url.lastPathComponent == "copia" }
        #expect(r.count == 2)
        #expect(copia?.isOrphan == true)
        #expect(copia?.branch == nil)
        #expect(copia?.repo?.path == fx.url(".repos/r").path)
        #expect(r.first { $0.url.lastPathComponent == "original" }?.isOrphan == false)
    }

    @Test func validWorktreeFoundOnlyByAgentRoot() throws {
        let fx = FixtureTree()
        link(fx, repo: ".repos/r", name: "w1", worktree: ".codex/worktrees/w1")
        let r = try find(fx)
        #expect(r.count == 1)
        #expect(r.first?.isOrphan == false)
        #expect(r.first?.branch == "feature")
        #expect(r.first?.repo?.path == fx.url(".repos/r").path)
    }

    @Test func submoduleLikeGitFileIsIgnored() throws {
        let fx = FixtureTree()
        fx.dir(".codex/worktrees/s")
        try "gitdir: ../../../Projetos/a/.git/modules/s\n".write(to: fx.url(".codex/worktrees/s/.git"), atomically: true, encoding: .utf8)
        #expect(try find(fx).isEmpty)
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
