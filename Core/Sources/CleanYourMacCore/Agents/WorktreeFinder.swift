import Foundation

/// Worktree **ligada** de um repositório git (nunca o checkout principal).
public struct Worktree: Hashable, Sendable {
    public let url: URL
    /// Repositório principal; `nil` quando ele não existe mais (worktree órfã).
    public let repo: URL?
    /// Branch lida do `HEAD` do registro; `nil` quando destacada (detached) ou sem registro.
    public let branch: String?
    public let isOrphan: Bool

    public init(url: URL, repo: URL?, branch: String?, isOrphan: Bool) {
        self.url = url
        self.repo = repo
        self.branch = branch
        self.isOrphan = isOrphan
    }
}

/// Descobre as worktrees ligadas dentro da pasta pessoal lendo só os arquivos do git
/// (`.git/worktrees/<n>/gitdir`, `.git/worktrees/<n>/HEAD` e o arquivo `.git` da worktree); não roda o git.
public struct WorktreeFinder: Sendable {
    private let home: URL
    private let realHome: String
    /// `st_dev` de um caminho (sem seguir link); trocável nos testes para simular um volume montado.
    private let device: @Sendable (String) -> dev_t?

    /// Pastas em que a varredura não desce (grafia exata): as recriáveis do catálogo, `Pods` e `.build`.
    static let prunedNames: Set<String> = Set(AgentsCatalog.rebuildable.filter { !$0.contains("/") }).union(["Pods", ".build"])

    public init(home: URL) {
        self.init(home: home, device: { path in
            var st = stat()
            return lstat(path, &st) == 0 ? st.st_dev : nil
        })
    }

    init(home: URL, device: @escaping @Sendable (String) -> dev_t?) {
        self.home = home
        realHome = PathPolicy.realPath(home.path)
        self.device = device
    }

    public func worktrees(isCancelled: @Sendable () -> Bool) throws -> [Worktree] {
        let repos = try findRepos(isCancelled: isCancelled)
        var found: [String: Worktree] = [:]

        // 1. Registros dos repositórios (`.git/worktrees/<n>`).
        for repo in repos {
            if isCancelled() { throw CancellationError() }
            let registry = repo + "/.git/worktrees"
            for name in listDir(registry) {
                try autoreleasepool {
                    if isCancelled() { throw CancellationError() }
                    let entry = registry + "/" + name
                    guard let raw = readText(entry + "/gitdir") else { return }
                    let wtGit = resolve(raw.trimmingCharacters(in: .whitespacesAndNewlines), base: entry)
                    guard (wtGit as NSString).lastPathComponent == ".git" else { return }
                    let wt = PathPolicy.realPath((wtGit as NSString).deletingLastPathComponent)
                    guard isInsideHome(wt), isDirectory(wt),
                          let target = gitdirTarget(of: wt), PathPolicy.realPath(target) == PathPolicy.realPath(entry) else { return }
                    found[wt] = Worktree(url: URL(fileURLWithPath: wt, isDirectory: true), repo: URL(fileURLWithPath: repo, isDirectory: true),
                                         branch: branch(entry), isOrphan: false)
                }
            }
        }

        // 2. Raízes do catálogo e `<repo>/.claude/worktrees/*`: achadas pelo arquivo `.git` da própria worktree.
        var candidates: [String] = []
        for agent in AgentsCatalog.agents {
            for root in agent.worktreeRoots { candidates += expand(realHome, root.split(separator: "/").map(String.init)) }
        }
        for repo in repos { candidates += listDir(repo + "/.claude/worktrees").map { repo + "/.claude/worktrees/" + $0 } }
        for c in candidates {
            try autoreleasepool {
                if isCancelled() { throw CancellationError() }
                let wt = PathPolicy.realPath(c)
                guard found[wt] == nil, isInsideHome(wt), isDirectory(wt), let target = gitdirTarget(of: wt) else { return }
                // `<repo>/.git/worktrees/<n>`
                let entry = target
                let repoGit = ((entry as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
                let parent = (entry as NSString).deletingLastPathComponent
                guard (parent as NSString).lastPathComponent == "worktrees", (repoGit as NSString).lastPathComponent == ".git" else { return }
                let repo = (repoGit as NSString).deletingLastPathComponent
                let url = URL(fileURLWithPath: wt, isDirectory: true)
                guard isDirectory(repoGit) else {
                    found[wt] = Worktree(url: url, repo: nil, branch: nil, isOrphan: true)
                    return
                }
                let repoURL = URL(fileURLWithPath: PathPolicy.realPath(repo), isDirectory: true)
                // Ligada só se o registro aponta de volta para esta pasta; cópia da pasta ou registro podado é órfã.
                if let raw = readText(entry + "/gitdir"),
                   PathPolicy.realPath(resolve(raw.trimmingCharacters(in: .whitespacesAndNewlines), base: entry)) == PathPolicy.realPath(wt + "/.git") {
                    found[wt] = Worktree(url: url, repo: repoURL, branch: branch(entry), isOrphan: false)
                } else {
                    found[wt] = Worktree(url: url, repo: repoURL, branch: nil, isOrphan: true)
                }
            }
        }
        if isCancelled() { throw CancellationError() }
        return found.values.sorted { $0.url.path < $1.url.path }
    }

    // MARK: - Varredura dos repositórios

    /// Repositórios (pasta com `.git` diretório) sob a pasta pessoal. Não desce em `Library`, `.Trash`, pacotes, ocultos,
    /// links, pastas de build e dependências (`prunedNames`, com a grafia exata), `go/pkg`, nem em outro volume
    /// (`st_dev` diferente do da pasta pessoal).
    private func findRepos(isCancelled: @Sendable () -> Bool) throws -> [String] {
        var repos: [String] = []
        guard let homeDevice = device(realHome) else { return repos }
        var stack = [realHome]
        var n = 0
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        while let dir = stack.popLast() {
            try autoreleasepool {
                n += 1
                if n == 1 || n & 0x3FF == 0, isCancelled() { throw CancellationError() }
                guard let items = try? FileManager.default.contentsOfDirectory(
                    at: URL(fileURLWithPath: dir, isDirectory: true), includingPropertiesForKeys: Array(keys), options: []) else { return }
                for item in items {
                    let name = item.lastPathComponent
                    if name == ".git" {
                        if isDirectory(item.path) { repos.append(dir) }
                        continue
                    }
                    if name.hasPrefix(".") || name == "Library" || Self.prunedNames.contains(name) { continue }
                    if name == "pkg", (dir as NSString).lastPathComponent == "go" { continue }
                    guard let v = try? item.resourceValues(forKeys: keys), v.isDirectory == true,
                          v.isSymbolicLink != true, v.isPackage != true, device(item.path) == homeDevice else { continue }
                    stack.append(item.path)
                }
            }
        }
        return repos
    }

    // MARK: - Leitura dos arquivos do git

    /// Destino do arquivo `.git` de uma worktree (`gitdir: <caminho>`), resolvido e normalizado.
    private func gitdirTarget(of worktree: String) -> String? {
        let gitFile = worktree + "/.git"
        guard !isDirectory(gitFile), let text = readText(gitFile) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("gitdir:") {
            let p = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            return p.isEmpty ? nil : resolve(p, base: worktree)
        }
        return nil
    }

    private func branch(_ registryEntry: String) -> String? {
        guard let head = readText(registryEntry + "/HEAD")?.trimmingCharacters(in: .whitespacesAndNewlines),
              head.hasPrefix("ref: refs/heads/") else { return nil }
        let b = String(head.dropFirst("ref: refs/heads/".count))
        return b.isEmpty ? nil : b
    }

    // MARK: - Utilitários

    private func resolve(_ path: String, base: String) -> String {
        PathPolicy.lexicalPath(path.hasPrefix("/") ? path : base + "/" + path)
    }

    private func isInsideHome(_ path: String) -> Bool { path.hasPrefix(realHome + "/") }

    private func isDirectory(_ path: String) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
    }

    private func readText(_ path: String) -> String? {
        guard let d = FileManager.default.contents(atPath: path), d.count < 64 * 1024 else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func listDir(_ path: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
    }

    /// Expande um padrão relativo com `*` de um nível.
    private func expand(_ base: String, _ parts: [String]) -> [String] {
        guard let first = parts.first else { return [base] }
        let rest = Array(parts.dropFirst())
        if first == "*" { return listDir(base).flatMap { expand(base + "/" + $0, rest) } }
        return expand(base + "/" + first, rest)
    }
}
