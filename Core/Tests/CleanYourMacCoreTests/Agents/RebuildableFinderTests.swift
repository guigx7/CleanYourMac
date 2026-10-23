import Foundation
import Testing
@testable import CleanYourMacCore

extension FixtureTree {
    /// Põe a data em tudo sob `rel` (arquivos e pastas, inclusive a própria), sem seguir links.
    func age(_ rel: String, _ date: Date) {
        var paths = [url(rel).path]
        if let e = FileManager.default.enumerator(atPath: url(rel).path) {
            for case let child as String in e { paths.append(url(rel).path + "/" + child) }
        }
        let t = timespec(tv_sec: Int(date.timeIntervalSince1970), tv_nsec: 0)
        for p in paths.reversed() {
            var times = [t, t]
            _ = utimensat(AT_FDCWD, p, &times, AT_SYMLINK_NOFOLLOW)
        }
    }
}

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
        let paths = arguments[(sep + 1)...].map { $0.hasPrefix(":(icase,literal)") ? String($0.dropFirst(":(icase,literal)".count)) : $0 }
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
        fx.file("wt/package.json", bytes: 10)
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

    @Test func caseVariantNotMatched() {
        // O APFS acha `Node_Modules` por `node_modules`; só a grafia exata do catálogo vale.
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/Node_Modules/a.js", bytes: 10)
        fx.file("wt/Build/a.js", bytes: 10)
        fx.file("wt/.Angular/cache/a.json", bytes: 10)
        fx.file("wt/.angular/Cache/a.json", bytes: 10)
        #expect(finder(FakeGitRunner(ignored: ["build", "Build", ".angular/cache"])).entry(for: wt) == nil)
        #expect(finder(nil).entry(for: wt) == nil)
        #expect(finder(FakeGitRunner(), now: Date()).entry(for: worktree(fx, orphan: true)) == nil)
    }

    /// C2: a atividade só pula as candidatas de verdade. `build` não ignorada (ou sem produtor) pode ser código: conta.
    @Test func activitySkipsOnlyRealCandidates() {
        let now = Date()
        let old = now.addingTimeInterval(-48 * 3600)
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/src/x.ts", bytes: 10)
        fx.file("wt/build/out.js", bytes: 10)
        fx.file("wt/node_modules/a.js", bytes: 10)
        fx.age("wt", old)
        fx.age("wt/node_modules", now)
        let quiet = finder(FakeGitRunner(), now: now).entry(for: wt)
        #expect(relPaths(quiet, wt) == ["node_modules"])
        #expect(quiet?.isRecent == false)

        fx.age("wt/build", now)
        try! FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: fx.url("wt").path)
        let busy = finder(FakeGitRunner(), now: now).entry(for: wt)
        #expect(relPaths(busy, wt) == ["node_modules"])
        #expect(busy?.isRecent == true)
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
        fx.age("wt", now.addingTimeInterval(-48 * 3600))
        fx.age("wt/node_modules", now)
        try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3 * 3600)], ofItemAtPath: fx.url("wt/src/x.ts").path)
        let entry = finder(FakeGitRunner(), now: now).entry(for: wt)
        #expect(entry?.isRecent == true)
        #expect(abs((entry?.lastActivity?.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-3 * 3600).timeIntervalSince1970) < 1)

        // Tudo com mais de 24 h; só a node_modules é nova → não conta.
        try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-25 * 3600)], ofItemAtPath: fx.url("wt/src/x.ts").path)
        let old = finder(FakeGitRunner(), now: now).entry(for: wt)
        #expect(old?.isRecent == false)
        #expect(abs((old?.lastActivity?.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-25 * 3600).timeIntervalSince1970) < 1)
    }

    /// O índice do registro não conta como atividade: qualquer `git status` o regrava.
    @Test func registryIndexIgnored() {
        let now = Date()
        let fx = FixtureTree()
        fx.file("repo/.git/worktrees/w1/index", bytes: 10, modified: now.addingTimeInterval(-3600))
        fx.dir("wt")
        try! "gitdir: \(fx.url("repo/.git/worktrees/w1").path)\n".write(to: fx.url("wt/.git"), atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-72 * 3600)], ofItemAtPath: fx.url("wt/.git").path)
        fx.file("wt/src/x.ts", bytes: 10, modified: now.addingTimeInterval(-48 * 3600))
        fx.file("wt/node_modules/a.js", bytes: 10, modified: now)
        fx.age("wt/src", now.addingTimeInterval(-48 * 3600))
        try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-48 * 3600)], ofItemAtPath: fx.url("wt").path)

        for wt in [worktree(fx), worktree(fx, orphan: true)] {
            let entry = finder(FakeGitRunner(), now: now).entry(for: wt)
            #expect(entry?.isRecent == false)
            #expect(abs((entry?.lastActivity?.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-48 * 3600).timeIntervalSince1970) < 1)
        }
    }

    /// `node_modules` vazia (ou só com links do workspace) não libera nada: não entra.
    @Test func zeroByteItemsSkipped() {
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.dir("wt/node_modules")
        fx.dir("wt/packages/core/node_modules")
        _ = fx.symlink("wt/packages/core/node_modules/dep", to: fx.url("wt/packages/core"))
        fx.file("wt/apps/web/node_modules/a.js", bytes: 10)
        #expect(relPaths(finder(FakeGitRunner()).entry(for: wt), wt) == ["apps/web/node_modules"])

        let fx2 = FixtureTree()
        let wt2 = worktree(fx2)
        fx2.dir("wt/node_modules")
        #expect(finder(FakeGitRunner()).entry(for: wt2) == nil)
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
        fx.file("wt/package.json", bytes: 10)
        fx.file("wt/São Paulo/package.json", bytes: 10)
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

    // MARK: - C2: "em uso" em monorepo

    private func home(_ fx: FixtureTree) -> URL { fx.dir("home") }

    /// Worktree sem git (ou órfã): arquivo 5 níveis abaixo mexido agora conta, sem limite de nível.
    @Test func deepChangeIsRecentWithoutGit() {
        let now = Date()
        let old = now.addingTimeInterval(-48 * 3600)
        for orphan in [false, true] {
            let fx = FixtureTree()
            let wt = worktree(fx, orphan: orphan)
            fx.file("wt/apps/web/src/app/page.tsx", bytes: 10)
            fx.file("wt/node_modules/a.js", bytes: 10)
            fx.age("wt", old)
            let f = RebuildableFinder(git: orphan ? GitTool(executable: clt, runner: FakeGitRunner()) : nil, now: now, home: home(fx))
            #expect(f.entry(for: wt)?.isRecent == false)
            try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-300)],
                                                   ofItemAtPath: fx.url("wt/apps/web/src/app/page.tsx").path)
            let e = f.entry(for: wt)
            #expect(e?.isRecent == true, "órfã: \(orphan)")
            #expect(abs((e?.lastActivity?.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-300).timeIntervalSince1970) < 1)
        }
    }

    /// Arquivo apagado: só a data da pasta mostra a mudança.
    @Test func deletedFileCountsByFolderDate() throws {
        let now = Date()
        let fx = FixtureTree()
        let wt = worktree(fx, orphan: true)
        fx.file("wt/a/b/c/d/gone.ts", bytes: 10)
        fx.file("wt/node_modules/a.js", bytes: 10)
        fx.age("wt", now.addingTimeInterval(-48 * 3600))
        let f = RebuildableFinder(git: nil, now: now, home: home(fx))
        #expect(f.entry(for: wt)?.isRecent == false)
        try FileManager.default.removeItem(at: fx.url("wt/a/b/c/d/gone.ts"))
        #expect(f.entry(for: wt)?.isRecent == true)
    }

    /// Passou do teto de entradas sem git: "em uso" (lado seguro).
    @Test func entryLimitMeansInUse() {
        let now = Date()
        let fx = FixtureTree()
        let wt = worktree(fx, orphan: true)
        for i in 0..<10 { fx.file("wt/src/f\(i).ts", bytes: 10) }
        fx.file("wt/node_modules/a.js", bytes: 10)
        fx.age("wt", now.addingTimeInterval(-48 * 3600))
        #expect(RebuildableFinder(git: nil, now: now, home: home(fx)).entry(for: wt)?.isRecent == false)
        #expect(RebuildableFinder(git: nil, now: now, home: home(fx), activityEntryLimit: 5).entry(for: wt)?.isRecent == true)
    }

    /// Sessão do Claude Code aberta (pid vivo) com o `cwd` dentro da worktree: em uso, mesmo sem nada mudado.
    @Test func liveAgentSessionMeansInUse() throws {
        let now = Date()
        let fx = FixtureTree()
        let wt = worktree(fx, orphan: true)
        fx.file("wt/src/x.ts", bytes: 10)
        fx.file("wt/node_modules/a.js", bytes: 10)
        fx.age("wt", now.addingTimeInterval(-48 * 3600))
        let h = home(fx)
        func session(_ pid: Int32, cwd: String) throws {
            try Data("{\"pid\":\(pid),\"sessionId\":\"79d527e8-7405-4796-b500-efd974f99154\",\"cwd\":\"\(cwd)\",\"status\":\"idle\"}".utf8)
                .write(to: fx.dir("home/.claude/sessions").appendingPathComponent("\(pid).json"))
        }
        // Processo morto, pasta vizinha com o mesmo começo de nome e pid inválido não contam.
        try session(Int32.max, cwd: fx.url("wt/src").path)
        try session(getpid(), cwd: fx.url("wt-outra").path)
        try session(0, cwd: fx.url("wt").path)
        #expect(RebuildableFinder(git: nil, now: now, home: h).entry(for: wt)?.isRecent == false)
        try session(getpid(), cwd: fx.url("wt/src").path)
        #expect(RebuildableFinder(git: nil, now: now, home: h).entry(for: wt)?.isRecent == true)
    }

    /// Git de verdade, worktree ligada de verdade (`git worktree add`): monorepo com mudança a 5 níveis, commit novo
    /// (`logs/HEAD`) e arquivo apagado. O `git status` não pode regravar o índice.
    @Test func integrationActivityWithRealGit() throws {
        let runner = SystemCommandRunner()
        guard let git = GitTool.locate(runner: runner, fileExists: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let now = Date()
        let old = now.addingTimeInterval(-48 * 3600)
        let fx = FixtureTree()
        func g(_ dir: String, _ args: [String]) -> Int32 {
            runner.run(git.executable, ["-C", fx.url(dir).path, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args).status
        }
        fx.dir("repo")
        #expect(g("repo", ["init", "-q"]) == 0)
        try "node_modules/\n".write(to: fx.url("repo/.gitignore"), atomically: true, encoding: .utf8)
        fx.file("repo/apps/web/src/app/page.tsx", bytes: 10)
        fx.file("repo/apps/web/src/app/gone.tsx", bytes: 10)
        fx.file("repo/package.json", bytes: 10)
        #expect(g("repo", ["add", "-A"]) == 0)
        #expect(g("repo", ["commit", "-q", "-m", "init"]) == 0)
        #expect(g("repo", ["worktree", "add", "-q", "-b", "feat", fx.url("wt").path]) == 0)
        fx.file("wt/node_modules/a.js", bytes: 10)
        let registry = fx.url("repo/.git/worktrees/wt")
        let wt = Worktree(url: fx.url("wt"), repo: fx.url("repo"), branch: "feat", isOrphan: false)
        let logsHEAD = registry.appendingPathComponent("logs/HEAD")
        /// Reflog com os carimbos antigos (como se os commits fossem de 2 dias atrás).
        func ageReflog() throws {
            let reflog = try String(contentsOf: logsHEAD, encoding: .utf8)
            let rewritten = reflog.split(separator: "\n").map { line -> String in
                var parts = line.components(separatedBy: "\t")
                var head = parts[0].split(separator: " ").map(String.init)
                head[head.count - 2] = "\(Int(old.timeIntervalSince1970))"
                parts[0] = head.joined(separator: " ")
                return parts.joined(separator: "\t")
            }.joined(separator: "\n") + "\n"
            try rewritten.write(to: logsHEAD, atomically: false, encoding: .utf8)
        }
        func ageFiles() {
            fx.age("wt", old)
            fx.age("repo/.git/worktrees/wt", old)
        }
        func ageAll() throws {
            try ageReflog()
            ageFiles()
        }
        let f = RebuildableFinder(git: git, now: now, home: home(fx))
        let indexBefore = try FileManager.default.attributesOfItem(atPath: registry.appendingPathComponent("index").path)[.modificationDate] as? Date
        try ageAll()
        let indexAged = try FileManager.default.attributesOfItem(atPath: registry.appendingPathComponent("index").path)[.modificationDate] as? Date
        #expect(indexBefore != nil)
        #expect(f.entry(for: wt)?.isRecent == false)
        // `--no-optional-locks`: o índice continua com a mesma data.
        let indexAfter = try FileManager.default.attributesOfItem(atPath: registry.appendingPathComponent("index").path)[.modificationDate] as? Date
        #expect(indexAfter == indexAged)

        // Mudança a 5 níveis (o conteúdo muda, como faz um agente).
        try "export default 1\n".write(to: fx.url("wt/apps/web/src/app/page.tsx"), atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-300)], ofItemAtPath: fx.url("wt/apps/web/src/app/page.tsx").path)
        fx.age("wt/apps/web/src/app", old)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-300)], ofItemAtPath: fx.url("wt/apps/web/src/app/page.tsx").path)
        let changed = f.entry(for: wt)
        #expect(changed?.isRecent == true)
        #expect(abs((changed?.lastActivity?.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-300).timeIntervalSince1970) < 1)

        // Volta ao conteúdo commitado: limpo de novo.
        #expect(g("wt", ["checkout", "-q", "--", "apps/web/src/app/page.tsx"]) == 0)
        try ageAll()
        #expect(f.entry(for: wt)?.isRecent == false)

        // `logs/HEAD` regravado sem commit novo (o `git gc` expira o reflog de todas as worktrees): só a data do arquivo
        // mudou, a última entrada é antiga → não conta.
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: logsHEAD.path)
        #expect(f.entry(for: wt)?.isRecent == false)

        // Commit novo na worktree: a última entrada do `logs/HEAD` é de agora, mesmo com os arquivos antigos.
        #expect(g("wt", ["commit", "-q", "--allow-empty", "-m", "vazio"]) == 0)
        ageFiles()
        #expect(f.entry(for: wt)?.isRecent == true)
        try ageAll()
        #expect(f.entry(for: wt)?.isRecent == false)

        // Reflog fora do formato: vale a data do arquivo (lado seguro).
        let saved = try Data(contentsOf: logsHEAD)
        try "lixo\n".write(to: logsHEAD, atomically: false, encoding: .utf8)
        #expect(f.entry(for: wt)?.isRecent == true)
        try saved.write(to: logsHEAD)
        ageFiles()
        #expect(f.entry(for: wt)?.isRecent == false)

        // Arquivo rastreado apagado: a data da pasta-mãe.
        try FileManager.default.removeItem(at: fx.url("wt/apps/web/src/app/gone.tsx"))
        #expect(f.entry(for: wt)?.isRecent == true)
    }

    /// Último carimbo do reflog: arquivo vazio (reflog expirado pelo `git gc`) não tem data, mesmo com o arquivo novo.
    @Test func lastReflogDateParsing() throws {
        let fx = FixtureTree()
        let log = fx.file("logs/HEAD", bytes: 0)
        #expect(RebuildableFinder.lastReflogDate(log.path) == nil)
        try "a b Nome <e@x> 1700000000 -0300\tcommit: x\nb c Nome <e@x> 1790000000 +0000\tcheckout: y\n".write(to: log, atomically: false, encoding: .utf8)
        #expect(RebuildableFinder.lastReflogDate(log.path) == Date(timeIntervalSince1970: 1_790_000_000))
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try "sem formato\n".write(to: log, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: log.path)
        #expect(RebuildableFinder.lastReflogDate(log.path) == old)
        #expect(RebuildableFinder.lastReflogDate(fx.url("logs/nada").path) == nil)
    }

    // MARK: - C1: produtor da pasta

    /// Um caso: arquivos a criar (caminho relativo à worktree → bytes; `/` no fim cria pasta), a recriável e se ela entra.
    private func producerCase(_ files: [String], _ rel: String, _ expected: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/\(rel)/payload.bin", bytes: 10)
        for f in files {
            if f.hasSuffix("/") { fx.dir("wt/" + f) } else { fx.file("wt/" + f, bytes: 10) }
        }
        // O git ignora tudo o que for perguntado: só o produtor decide.
        let names = AgentsCatalog.rebuildable
        var ignored = Set<String>()
        for prefix in ["", "a/", "a/b/", "src/services/", "src/features/"] { for n in names { ignored.insert(prefix + n) } }
        let got = relPaths(finder(FakeGitRunner(ignored: ignored)).entry(for: wt), wt).contains(rel)
        #expect(got == expected, "\(rel) com \(files)", sourceLocation: sourceLocation)
    }

    @Test func packageJsonProducer() {
        for name in [".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".vite", ".angular/cache", ".expo",
                     "dist", "build", "out", "coverage", ".output"] {
            producerCase(["package.json"], name, true)
            producerCase(["a/package.json"], "a/" + name, true)
            producerCase([], name, false)
            // Produtor de outra pasta (o avô) não vale.
            producerCase(["package.json"], "a/" + name, false)
            // Grafia diferente ou pasta no lugar do arquivo não valem.
            producerCase(["Package.json"], name, false)
            producerCase(["package.json/"], name, false)
        }
    }

    @Test func codeFolderWithGenericNameIsNotBuild() {
        // A prova real: `src/services/coverage/load-coverage.ts` com `coverage/` no `.gitignore`.
        producerCase(["package.json", "src/services/coverage/load-coverage.ts"], "src/services/coverage", false)
        producerCase(["package.json", "src/features/build/BuildCard.tsx"], "src/features/build", false)
    }

    @Test func gradleProducer() {
        for f in ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"] {
            producerCase([f], "build", true)
            producerCase([f], ".gradle", true)
        }
        producerCase([], ".gradle", false)
        producerCase(["package.json"], ".gradle", false)
        producerCase(["Cargo.toml"], "build", false)
    }

    @Test func targetProducer() {
        producerCase(["Cargo.toml"], "target", true)
        producerCase(["pom.xml"], "target", true)
        producerCase(["package.json"], "target", false)
        producerCase([], "target", false)
    }

    @Test func venvProducer() {
        for name in [".venv", "venv"] {
            producerCase([name + "/pyvenv.cfg"], name, true)
            producerCase([], name, false)
            producerCase(["pyvenv.cfg"], name, false)
            producerCase([name + "/pyvenv.cfg/"], name, false)
        }
    }

    @Test func pycacheOnlyBytecode() {
        producerCase([], "__pycache__", false) // `payload.bin` não é bytecode
        let fx = FixtureTree()
        let wt = worktree(fx)
        fx.file("wt/__pycache__/a.cpython-312.pyc", bytes: 10)
        fx.file("wt/__pycache__/b.cpython-312.pyo", bytes: 10)
        fx.file("wt/pkg/__pycache__/c.pyc", bytes: 10)
        fx.file("wt/pkg/__pycache__/helper.py", bytes: 10)
        fx.file("wt/lib/__pycache__/d.pyc", bytes: 10)
        fx.file("wt/lib/__pycache__/sub/e.pyc", bytes: 10)
        let got = relPaths(finder(FakeGitRunner(ignored: ["__pycache__", "pkg/__pycache__", "lib/__pycache__"])).entry(for: wt), wt)
        #expect(got == ["__pycache__"])
    }

    @Test func toolCacheProducer() {
        for name in [".pytest_cache", ".mypy_cache"] {
            producerCase([name + "/CACHEDIR.TAG"], name, true)
            producerCase([name + "/README.md"], name, true)
            producerCase([], name, false)
            producerCase(["CACHEDIR.TAG"], name, false)
        }
    }

    @Test func derivedDataProducer() {
        producerCase(["DerivedData/info.plist"], "DerivedData", true)
        producerCase(["DerivedData/Build/"], "DerivedData", true)
        producerCase(["DerivedData/Index/"], "DerivedData", true)
        producerCase([], "DerivedData", false)
        producerCase(["DerivedData/build/"], "DerivedData", false)
        producerCase(["DerivedData/Build"], "DerivedData", false) // arquivo, não pasta
    }

    @Test func nodeModulesNeedsNoProducer() {
        producerCase([], "node_modules", true)
        producerCase([], "a/b/node_modules", true)
    }

    /// Com o git de verdade: pastas de código nunca commitadas e ignoradas por um padrão de qualquer nível ficam de fora.
    @Test func integrationUncommittedCodeFoldersStayOut() throws {
        let runner = SystemCommandRunner()
        guard let git = GitTool.locate(runner: runner, fileExists: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let fx = FixtureTree()
        let wt = Worktree(url: fx.dir("wt"), repo: nil, branch: nil, isOrphan: false)
        func g(_ args: [String]) -> Int32 {
            runner.run(git.executable, ["-C", wt.url.path, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args).status
        }
        #expect(g(["init", "-q"]) == 0)
        try "coverage/\nbuild/\ndist/\n".write(to: fx.url("wt/.gitignore"), atomically: true, encoding: .utf8)
        fx.file("wt/package.json", bytes: 10)
        #expect(g(["add", "-A"]) == 0)
        #expect(g(["commit", "-q", "-m", "init"]) == 0)
        fx.file("wt/src/services/coverage/load-coverage.ts", bytes: 10)
        fx.file("wt/src/features/build/BuildCard.tsx", bytes: 10)
        fx.file("wt/coverage/lcov.info", bytes: 10)
        fx.file("wt/dist/a.js", bytes: 10)
        let entry = RebuildableFinder(git: git, now: Date()).entry(for: wt)
        #expect(relPaths(entry, wt) == ["coverage", "dist"])
    }

    @Test func integrationCaseInsensitiveBuildWithTrackedFiles() throws {
        // `Build/` versionada e `.gitignore` com `build/`: no APFS o git diz que `build` é ignorada, mas nada pode sair.
        let runner = SystemCommandRunner()
        guard let git = GitTool.locate(runner: runner, fileExists: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let fx = FixtureTree()
        let wt = Worktree(url: fx.dir("wt"), repo: nil, branch: nil, isOrphan: false)
        func g(_ args: [String]) -> Int32 {
            runner.run(git.executable, ["-C", wt.url.path, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args).status
        }
        #expect(g(["init", "-q"]) == 0)
        fx.file("wt/Build/script.sh", bytes: 10)
        #expect(g(["add", "-A"]) == 0)
        #expect(g(["commit", "-q", "-m", "init"]) == 0)
        try "build/\n".write(to: fx.url("wt/.gitignore"), atomically: true, encoding: .utf8)
        #expect(git.hasTracked("build", in: wt.url))
        #expect(RebuildableFinder(git: git, now: Date()).entry(for: wt) == nil)
    }
}
