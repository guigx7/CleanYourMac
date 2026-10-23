import Foundation
import Testing
@testable import CleanYourMacCore

/// Git falso: responde `check-ignore` e `ls-files` a partir de conjuntos fixos.
private final class FakeGitRunner: CommandRunner, @unchecked Sendable {
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
        let paths = Array(arguments[(sep + 1)...])
        if arguments.contains("check-ignore") {
            let hits = paths.filter { ignored.contains($0) }
            return hits.isEmpty ? (1, "") : (0, hits.map { $0 + "\n" }.joined())
        }
        if arguments.contains("ls-files") {
            let hits = paths.filter { tracked.contains($0) }
            return (0, hits.map { $0 + "/a.js\n" }.joined())
        }
        return (128, "fatal")
    }
}

@Suite struct RebuildableFinderTests {
    private let clt = "/Library/Developer/CommandLineTools/usr/bin/git"

    private func worktree(_ fx: FixtureTree, _ rel: String = "wt", orphan: Bool = false) -> Worktree {
        Worktree(url: fx.dir(rel), repo: orphan ? nil : fx.url("repo"), branch: "feature", isOrphan: orphan)
    }

    private func relPaths(_ entry: WorktreeEntry?, _ wt: Worktree) -> Set<String> {
        Set((entry?.items ?? []).map { String($0.url.path.dropFirst(wt.url.path.count + 1)) })
    }

    private func finder(_ runner: FakeGitRunner?, now: Date = Date()) -> RebuildableFinder {
        RebuildableFinder(git: runner.map { GitTool(executable: clt, runner: $0) }, now: now)
    }

    @Test func nodeModulesAtAnyDepthUpTo4() {
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/node_modules/a/index.js", bytes: 10)
        fx.file("wt/node_modules/a/node_modules/b/index.js", bytes: 10)
        fx.file("wt/apps/web/node_modules/c/index.js", bytes: 10)
        fx.file("wt/a/b/c/d/node_modules/x.js", bytes: 10)
        fx.file("wt/a/b/c/d/e/node_modules/y.js", bytes: 10)
        let entry = finder(FakeGitRunner()).entry(for: wt)
        #expect(relPaths(entry, wt) == ["node_modules", "apps/web/node_modules", "a/b/c/d/node_modules"])
        #expect(entry?.items.allSatisfy { $0.name == "node_modules" && $0.worktree == wt.url } == true)
        #expect(entry?.items.allSatisfy { $0.size > 0 && $0.modified != nil } == true)
    }

    @Test func buildFoldersNeedIgnore() {
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/node_modules/a.js", bytes: 10)
        fx.file("wt/dist/a.js", bytes: 10)
        fx.file("wt/build/a.js", bytes: 10)
        fx.file("wt/.angular/cache/a.json", bytes: 10)
        let f = finder(FakeGitRunner(ignored: ["dist", ".angular/cache"]))
        #expect(!f.buildFoldersSkipped)
        let entry = f.entry(for: wt)
        #expect(relPaths(entry, wt) == ["node_modules", "dist", ".angular/cache"])
        #expect(entry?.items.first?.name == "node_modules")
        #expect(entry?.items.contains { $0.name == ".angular/cache" } == true)
    }

    @Test func trackedBuildFolderSkipped() {
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/dist/a.js", bytes: 10)
        fx.file("wt/node_modules/a.js", bytes: 10)
        fx.file("wt/apps/web/node_modules/a.js", bytes: 10)
        let entry = finder(FakeGitRunner(ignored: ["dist"], tracked: ["dist", "apps/web/node_modules"])).entry(for: wt)
        #expect(relPaths(entry, wt) == ["node_modules"])
    }

    @Test func gitFailureKeepsBuildFoldersOut() {
        // Git que sempre falha: nada ignorado e tudo "rastreado" (falha fechado) → nada entra.
        final class Broken: CommandRunner, @unchecked Sendable {
            func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) { (128, "fatal") }
        }
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/dist/a.js", bytes: 10)
        fx.file("wt/node_modules/a.js", bytes: 10)
        #expect(RebuildableFinder(git: GitTool(executable: clt, runner: Broken()), now: Date()).entry(for: wt) == nil)
    }

    @Test func noGitOnlyNodeModules() {
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/node_modules/a.js", bytes: 10)
        fx.file("wt/dist/a.js", bytes: 10)
        let f = finder(nil)
        #expect(f.buildFoldersSkipped)
        #expect(relPaths(f.entry(for: wt), wt) == ["node_modules"])
    }

    @Test func orphanOnlyNodeModulesWithoutGitCalls() {
        let fx = FixtureTree()
        let wt = worktree(fx, orphan: true)
        fx.file("wt/node_modules/a.js", bytes: 10)
        fx.file("wt/dist/a.js", bytes: 10)
        let runner = FakeGitRunner(ignored: ["dist"])
        #expect(relPaths(finder(runner).entry(for: wt), wt) == ["node_modules"])
        #expect(runner.calls.isEmpty)
    }

    @Test func symlinkedFoldersSkipped() {
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("elsewhere/node_modules/a.js", bytes: 10)
        fx.file("elsewhere/pkg/a.js", bytes: 10)
        fx.symlink("wt/node_modules", to: fx.url("elsewhere/pkg"))
        fx.symlink("wt/apps", to: fx.url("elsewhere"))
        // `.angular` como link: `.angular/cache` não pode ser seguido.
        fx.file("elsewhere/ng/cache/a.json", bytes: 10)
        fx.symlink("wt/.angular", to: fx.url("elsewhere/ng"))
        #expect(finder(FakeGitRunner(ignored: [".angular/cache"])).entry(for: wt) == nil)
    }

    @Test func nestedRepoSkipped() {
        // Submódulo ou repositório aninhado: o git da worktree não responde por ele.
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/vendor/lib/.git/HEAD", bytes: 10)
        fx.file("wt/vendor/lib/node_modules/a.js", bytes: 10)
        #expect(finder(FakeGitRunner()).entry(for: wt) == nil)
    }

    @Test func recentWorktreeNotSafe() {
        let now = Date()
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/package.json", bytes: 10, modified: now.addingTimeInterval(-48 * 3600))
        fx.file("wt/src/x.ts", bytes: 10, modified: now.addingTimeInterval(-3 * 3600))
        fx.file("wt/node_modules/a.js", bytes: 10, modified: now)
        let entry = finder(FakeGitRunner(), now: now).entry(for: wt)
        #expect(entry?.isRecent == true)
        #expect(abs((entry?.lastActivity?.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-3 * 3600).timeIntervalSince1970) < 1)

        // Tudo com mais de 24 h; só a node_modules é nova → não conta.
        try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-25 * 3600)], ofItemAtPath: fx.url("wt/src/x.ts").path)
        let old = finder(FakeGitRunner(), now: now).entry(for: wt)
        #expect(old?.isRecent == false)
        #expect(abs((old?.lastActivity?.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-25 * 3600).timeIntervalSince1970) < 1)
    }

    @Test func registryIndexCountsUnlessOrphan() {
        let now = Date()
        let fx = FixtureTree()
        fx.file("repo/.git/worktrees/w1/index", bytes: 10, modified: now.addingTimeInterval(-3600))
        fx.dir("wt")
        try! "gitdir: \(fx.url("repo/.git/worktrees/w1").path)\n".write(to: fx.url("wt/.git"), atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-72 * 3600)], ofItemAtPath: fx.url("wt/.git").path)
        fx.file("wt/src/x.ts", bytes: 10, modified: now.addingTimeInterval(-48 * 3600))
        fx.file("wt/node_modules/a.js", bytes: 10, modified: now)

        let linked = finder(FakeGitRunner(), now: now).entry(for: worktree(fx))
        #expect(linked?.isRecent == true)
        let orphan = finder(FakeGitRunner(), now: now).entry(for: worktree(fx, orphan: true))
        #expect(orphan?.isRecent == false)
        #expect(abs((orphan?.lastActivity?.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-48 * 3600).timeIntervalSince1970) < 1)
    }

    @Test func emptyWorktreeIsNil() {
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/src/x.ts", bytes: 10)
        #expect(finder(FakeGitRunner()).entry(for: wt) == nil)
    }

    @Test func integrationWithRealGit() throws {
        let runner = SystemCommandRunner()
        guard let git = GitTool.locate(runner: runner, fileExists: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let fx = FixtureTree()
        let wt = Worktree(url: fx.dir("wt"), repo: nil, branch: nil, isOrphan: false)
        func g(_ args: [String]) -> Int32 {
            runner.run(git.executable, ["-C", wt.url.path, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args).status
        }
        #expect(g(["init", "-q"]) == 0)
        try "dist/\nnode_modules/\n".write(to: fx.url("wt/.gitignore"), atomically: true, encoding: .utf8)
        fx.file("wt/build/committed.txt", bytes: 10)
        fx.file("wt/src/x.ts", bytes: 10)
        #expect(g(["add", "-A"]) == 0)
        #expect(g(["commit", "-q", "-m", "init"]) == 0)
        fx.file("wt/dist/a.js", bytes: 10)
        fx.file("wt/São Paulo/dist/a.js", bytes: 10)
        fx.file("wt/out/a.js", bytes: 10) // não ignorada
        fx.file("wt/node_modules/a.js", bytes: 10)
        // Rastreada à força dentro de uma pasta ignorada.
        fx.file("wt/coverage/keep.txt", bytes: 10)
        try "dist/\nnode_modules/\ncoverage/\n".write(to: fx.url("wt/.gitignore"), atomically: true, encoding: .utf8)
        #expect(g(["add", "-f", "coverage/keep.txt"]) == 0)

        let entry = RebuildableFinder(git: git, now: Date()).entry(for: wt)
        #expect(relPaths(entry, wt) == ["node_modules", "dist", "São Paulo/dist"])
    }
}
