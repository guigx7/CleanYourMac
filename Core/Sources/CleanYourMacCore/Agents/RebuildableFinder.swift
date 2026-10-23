import Foundation

/// Pasta recriável (`node_modules`, build, cache) dentro de uma worktree.
public struct RebuildableItem: Hashable, Sendable {
    public let url: URL
    public let worktree: URL
    /// Nome do catálogo (`AgentsCatalog.rebuildable`), por exemplo `node_modules` ou `.angular/cache`.
    public let name: String
    public let size: Int64
    /// Data de modificação da própria pasta.
    public let modified: Date?
}

/// Uma worktree com as pastas recriáveis que podem ir para o Lixo.
public struct WorktreeEntry: Hashable, Sendable {
    public let worktree: Worktree
    /// `node_modules` primeiro, na ordem do catálogo; depois pelo caminho.
    public let items: [RebuildableItem]
    /// Data mais nova entre os arquivos de fora das recriáveis e o índice do registro da worktree.
    public let lastActivity: Date?
    /// Modificação nas últimas 24 h: a worktree está em uso.
    public let isRecent: Bool
}

/// Acha as pastas recriáveis de uma worktree. Regras (o que sai daqui vai para o Lixo; na dúvida, fica de fora):
/// - só diretórios reais: nada que seja link nem esteja sob um link;
/// - `node_modules` até o nível 4 (pasta-mãe com no máximo 4 componentes abaixo da worktree);
/// - cada parte do nome com a grafia exata do catálogo na listagem da pasta (o APFS não diferencia caixa);
/// - pastas de build só quando o git as ignora (`check-ignore`);
/// - com git, nada que contenha arquivo rastreado (`ls-files`, que falha fechado);
/// - sem git utilizável, ou com worktree órfã, só `node_modules`, sem chamar o git;
/// - não desce em `.git`, em recriáveis nem em repositórios aninhados (submódulos), cujo git é outro.
public struct RebuildableFinder: Sendable {
    public let git: GitTool?
    public let now: Date

    /// Janela de "em uso": 24 h.
    static let recentWindow: TimeInterval = 86_400
    /// Nível máximo da pasta-mãe de uma recriável.
    static let maxSearchDepth = 4
    /// Nível máximo das pastas olhadas para medir a atividade.
    static let maxActivityDepth = 3
    static let nodeModules = "node_modules"

    public init(git: GitTool?, now: Date) {
        self.git = git
        self.now = now
    }

    /// Verdadeiro quando não há git: as pastas de build ficam de fora em todas as worktrees.
    /// (Worktrees órfãs também ficam só com `node_modules`, mesmo com git.)
    public var buildFoldersSkipped: Bool { git == nil }

    /// `nil` quando a worktree não tem nenhuma pasta recriável.
    public func entry(for worktree: Worktree) -> WorktreeEntry? {
        let root = worktree.url.path
        // A própria worktree precisa ser um caminho real, sem link em nenhum nível.
        guard !root.isEmpty, root != "/", PathPolicy.realPath(root) == root, isRealDirectory(root) else { return nil }

        let useGit = git != nil && !worktree.isOrphan
        var candidates = findCandidates(root: root)
        if !useGit { candidates = candidates.filter { $0.name == Self.nodeModules } }
        if let git, useGit {
            let build = candidates.filter { $0.name != Self.nodeModules }.map(\.rel)
            let ignored = build.isEmpty ? [] : git.ignored(build, in: worktree.url)
            candidates = candidates.filter { $0.name == Self.nodeModules || ignored.contains($0.rel) }
            candidates = candidates.filter { !git.hasTracked($0.rel, in: worktree.url) }
        }
        guard !candidates.isEmpty else { return nil }

        let order = Dictionary(uniqueKeysWithValues: AgentsCatalog.rebuildable.enumerated().map { ($1, $0) })
        candidates.sort { (order[$0.name] ?? .max, $0.rel) < (order[$1.name] ?? .max, $1.rel) }

        let sizer = FileSizer(mode: .allocated)
        let items = candidates.map { c -> RebuildableItem in
            let path = root + "/" + c.rel
            return RebuildableItem(url: URL(fileURLWithPath: path, isDirectory: true), worktree: worktree.url, name: c.name,
                                   size: sizer.allocatedSize(of: URL(fileURLWithPath: path, isDirectory: true)),
                                   modified: lstatInfo(path).map(Self.mtime))
        }

        let last = lastActivity(root: root, isOrphan: worktree.isOrphan)
        let isRecent = last.map { now.timeIntervalSince($0) <= Self.recentWindow } ?? false
        return WorktreeEntry(worktree: worktree, items: items, lastActivity: last, isRecent: isRecent)
    }

    // MARK: - Busca

    private struct Candidate { let rel: String; let name: String }

    private func findCandidates(root: String) -> [Candidate] {
        let names = AgentsCatalog.rebuildable
        var found: [Candidate] = []
        var stack: [(rel: String, depth: Int)] = [("", 0)]
        while let (rel, depth) = stack.popLast() {
            autoreleasepool {
                let dir = rel.isEmpty ? root : root + "/" + rel
                let children = listDir(dir)
                let childSet = Set(children)
                for name in names {
                    let candRel = rel.isEmpty ? name : rel + "/" + name
                    // Cada parte do nome (`.angular`, `.angular/cache`) tem de ser diretório real e aparecer com a
                    // grafia EXATA na listagem da pasta-mãe: o APFS não diferencia caixa, e `lstat(".../build")`
                    // acharia `Build/`, que o git (com `core.ignorecase`) dá como ignorada sem achar o que é rastreado.
                    var ok = true
                    var partial = dir
                    for (i, part) in name.split(separator: "/").map(String.init).enumerated() {
                        let listed = i == 0 ? childSet.contains(part) : listDir(partial).contains(part)
                        partial += "/" + part
                        if !listed || !isRealDirectory(partial) { ok = false; break }
                    }
                    // Uma recriável que é repositório próprio não é do git desta worktree.
                    if ok, lstatInfo(partial + "/.git") == nil { found.append(Candidate(rel: candRel, name: name)) }
                }
                guard depth < Self.maxSearchDepth else { return }
                for child in children {
                    let childRel = rel.isEmpty ? child : rel + "/" + child
                    let childPath = root + "/" + childRel
                    guard child != ".git", !isRebuildablePath(childRel), isRealDirectory(childPath),
                          lstatInfo(childPath + "/.git") == nil else { continue }
                    stack.append((childRel, depth + 1))
                }
            }
        }
        return found
    }

    /// Verdadeiro quando o caminho termina num nome do catálogo (inclusive os de mais de uma parte), com a grafia
    /// exata: os componentes vêm de `contentsOfDirectory`.
    private func isRebuildablePath(_ rel: String) -> Bool {
        AgentsCatalog.rebuildable.contains { rel == $0 || rel.hasSuffix("/" + $0) }
    }

    // MARK: - Atividade

    /// Atividade da worktree: a data mais nova entre os arquivos de fora das recriáveis e, se não for órfã, o índice do
    /// registro. O removedor recalcula com esta mesma função para saber se o agente voltou a mexer.
    func lastActivity(root: String, isOrphan: Bool) -> Date? {
        var last = latestActivity(root: root)
        if !isOrphan, let index = registryIndexDate(root: root) {
            last = max(last ?? index, index)
        }
        return last
    }

    /// Data mais nova dos arquivos até o nível 3. Não desce em `.git` nem em pastas com nome do catálogo
    /// (grafia exata), listadas ou não. Não segue links.
    private func latestActivity(root: String) -> Date? {
        var latest: Date?
        var stack: [(rel: String, depth: Int)] = [("", 0)]
        while let (rel, depth) = stack.popLast() {
            autoreleasepool {
                let dir = rel.isEmpty ? root : root + "/" + rel
                for child in listDir(dir) where child != ".git" {
                    let childRel = rel.isEmpty ? child : rel + "/" + child
                    guard let st = lstatInfo(root + "/" + childRel) else { continue }
                    switch st.st_mode & S_IFMT {
                    case S_IFREG:
                        let d = Self.mtime(st)
                        latest = max(latest ?? d, d)
                    case S_IFDIR:
                        if depth < Self.maxActivityDepth, !isRebuildablePath(childRel) { stack.append((childRel, depth + 1)) }
                    default:
                        continue
                    }
                }
            }
        }
        return latest
    }

    /// Data do índice no registro da worktree (`<repo>/.git/worktrees/<n>/index`), lido do arquivo `.git` dela.
    private func registryIndexDate(root: String) -> Date? {
        let gitFile = root + "/.git"
        guard let st = lstatInfo(gitFile), st.st_mode & S_IFMT == S_IFREG, st.st_size < 64 * 1024,
              let data = FileManager.default.contents(atPath: gitFile),
              let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("gitdir:") {
            let p = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return nil }
            let dir = PathPolicy.lexicalPath(p.hasPrefix("/") ? p : root + "/" + p)
            return lstatInfo(dir + "/index").map(Self.mtime)
        }
        return nil
    }

    // MARK: - Utilitários

    private func lstatInfo(_ path: String) -> stat? {
        var st = stat()
        return lstat(path, &st) == 0 ? st : nil
    }

    /// Diretório de verdade: `lstat` não segue o link, então um link para pasta não passa.
    private func isRealDirectory(_ path: String) -> Bool {
        guard let st = lstatInfo(path) else { return false }
        return st.st_mode & S_IFMT == S_IFDIR
    }

    private func listDir(_ path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }

    private static func mtime(_ st: stat) -> Date {
        Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
    }
}
