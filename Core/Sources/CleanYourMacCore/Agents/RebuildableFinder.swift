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
    /// Data mais nova vista fora das recriáveis (arquivos mudados, pastas, `logs/HEAD`; o índice do git não conta).
    public let lastActivity: Date?
    /// Em uso: modificação nas últimas 24 h, sessão viva de um agente dentro dela, ou atividade que não deu para medir.
    public let isRecent: Bool
}

/// Acha as pastas recriáveis de uma worktree. Regras (o que sai daqui vai para o Lixo; na dúvida, fica de fora):
/// - só diretórios reais: nada que seja link nem esteja sob um link;
/// - `node_modules` até o nível 4 (pasta-mãe com no máximo 4 componentes abaixo da worktree);
/// - cada parte do nome com a grafia exata do catálogo na listagem da pasta (o APFS não diferencia caixa);
/// - pastas de build só quando o git as ignora (`check-ignore`) e o "produtor" delas está lá (`hasProducer`): um padrão
///   como `coverage/` no `.gitignore` vale em qualquer nível e pegaria `src/services/coverage`, que é código;
/// - com git, nada que contenha arquivo rastreado (`ls-files`, que falha fechado);
/// - sem git utilizável, ou com worktree órfã, só `node_modules`, sem chamar o git;
/// - não desce em `.git`, em recriáveis nem em repositórios aninhados (submódulos), cujo git é outro.
public struct RebuildableFinder: Sendable {
    public let git: GitTool?
    public let now: Date
    /// Pasta pessoal: de onde vêm as sessões vivas do Claude Code (`~/.claude/sessions`).
    public let home: URL
    /// Teto de entradas olhadas para medir a atividade; passou dele, a worktree conta como em uso.
    let activityEntryLimit: Int

    /// Janela de "em uso": 24 h.
    static let recentWindow: TimeInterval = 86_400
    /// Nível máximo da pasta-mãe de uma recriável.
    static let maxSearchDepth = 4
    static let nodeModules = "node_modules"

    public init(git: GitTool?, now: Date, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                activityEntryLimit: Int = 200_000) {
        self.git = git
        self.now = now
        self.home = home
        self.activityEntryLimit = activityEntryLimit
    }

    /// Verdadeiro quando não há git: as pastas de build ficam de fora em todas as worktrees.
    /// (Worktrees órfãs também ficam só com `node_modules`, mesmo com git.)
    public var buildFoldersSkipped: Bool { git == nil }

    /// `nil` quando a worktree não tem nenhuma pasta recriável.
    public func entry(for worktree: Worktree) -> WorktreeEntry? {
        let root = worktree.url.path
        guard let candidates = candidates(for: worktree), !candidates.isEmpty else { return nil }

        let sizer = FileSizer(mode: .allocated)
        // Pastas com 0 byte alocado (por exemplo `node_modules` só com links do workspace) não liberam nada: ficam de fora.
        let items = candidates.compactMap { c -> RebuildableItem? in
            let path = root + "/" + c.rel
            let size = sizer.allocatedSize(of: URL(fileURLWithPath: path, isDirectory: true))
            guard size > 0 else { return nil }
            return RebuildableItem(url: URL(fileURLWithPath: path, isDirectory: true), worktree: worktree.url, name: c.name,
                                   size: size, modified: lstatInfo(path).map(Self.mtime))
        }
        guard !items.isEmpty else { return nil }

        let a = activity(of: worktree, skipping: Set(candidates.map(\.rel)))
        return WorktreeEntry(worktree: worktree, items: items, lastActivity: a.latest, isRecent: a.isRecent(now: now))
    }

    /// As recriáveis que podem sair (antes do filtro de 0 byte), na ordem do catálogo; `nil` quando a worktree não é
    /// um caminho real.
    private func candidates(for worktree: Worktree) -> [Candidate]? {
        let root = worktree.url.path
        // A própria worktree precisa ser um caminho real, sem link em nenhum nível.
        guard !root.isEmpty, root != "/", PathPolicy.realPath(root) == root, isRealDirectory(root) else { return nil }

        let useGit = git != nil && !worktree.isOrphan
        var candidates = findCandidates(root: root)
        if !useGit { candidates = candidates.filter { $0.name == Self.nodeModules } }
        candidates = candidates.filter { Self.hasProducer(name: $0.name, path: root + "/" + $0.rel) }
        if let git, useGit {
            let build = candidates.filter { $0.name != Self.nodeModules }.map(\.rel)
            let ignored = build.isEmpty ? [] : git.ignored(build, in: worktree.url)
            candidates = candidates.filter { $0.name == Self.nodeModules || ignored.contains($0.rel) }
            candidates = candidates.filter { !git.hasTracked($0.rel, in: worktree.url) }
        }
        let order = Dictionary(uniqueKeysWithValues: AgentsCatalog.rebuildable.enumerated().map { ($1, $0) })
        candidates.sort { (order[$0.name] ?? .max, $0.rel) < (order[$1.name] ?? .max, $1.rel) }
        return candidates
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

    // MARK: - Produtor

    /// Recriáveis que um `package.json` na pasta-mãe produz (a mãe de `.angular`, no caso de `.angular/cache`).
    static let packageJsonProduced: Set<String> = [
        ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".vite", ".angular/cache", ".expo",
        "dist", "build", "out", "coverage", ".output",
    ]
    static let gradleFiles = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]

    /// Verdadeiro quando a pasta tem o sinal da ferramenta que a cria. O nome e o `check-ignore` não bastam: pasta de
    /// código com nome genérico (`src/features/build`) também é ignorada por um `build/` do `.gitignore`. Na dúvida, falso.
    /// - `node_modules`: sempre;
    /// - `package.json` na mãe: as de `packageJsonProduced`; `build` também com um arquivo do Gradle na mãe;
    /// - `target`: `Cargo.toml` ou `pom.xml` na mãe; `.gradle`: um arquivo do Gradle na mãe;
    /// - `.venv`/`venv`: `pyvenv.cfg` dentro; `__pycache__`: só arquivos `*.pyc`/`*.pyo` dentro (nenhuma pasta);
    /// - `.pytest_cache`/`.mypy_cache`: `CACHEDIR.TAG` ou `README.md` dentro;
    /// - `DerivedData`: `info.plist` ou a pasta `Build` ou `Index` dentro.
    /// Os arquivos e pastas são conferidos com a grafia exata na listagem e pelo tipo (`lstat`, sem seguir link).
    static func hasProducer(name: String, path: String) -> Bool {
        guard path.hasSuffix("/" + name) else { return false }
        let parent = String(path.dropLast(name.count + 1))
        func file(_ dir: String, _ n: String) -> Bool { entryType(dir, n) == S_IFREG }
        func folder(_ dir: String, _ n: String) -> Bool { entryType(dir, n) == S_IFDIR }
        switch name {
        case nodeModules:
            return true
        case "build":
            return file(parent, "package.json") || gradleFiles.contains { file(parent, $0) }
        case _ where packageJsonProduced.contains(name):
            return file(parent, "package.json")
        case "target":
            return file(parent, "Cargo.toml") || file(parent, "pom.xml")
        case ".gradle":
            return gradleFiles.contains { file(parent, $0) }
        case ".venv", "venv":
            return file(path, "pyvenv.cfg")
        case "__pycache__":
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: path), !children.isEmpty else { return false }
            return children.allSatisfy { ($0.hasSuffix(".pyc") || $0.hasSuffix(".pyo")) && file(path, $0) }
        case ".pytest_cache", ".mypy_cache":
            return file(path, "CACHEDIR.TAG") || file(path, "README.md")
        case "DerivedData":
            return file(path, "info.plist") || folder(path, "Build") || folder(path, "Index")
        default:
            return false
        }
    }

    /// Tipo (`S_IFREG`, `S_IFDIR`...) de `dir/name` quando o nome aparece com a grafia exata na listagem; senão `nil`.
    private static func entryType(_ dir: String, _ name: String) -> mode_t? {
        guard ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).contains(name) else { return nil }
        var st = stat()
        guard lstat(dir + "/" + name, &st) == 0 else { return nil }
        return st.st_mode & S_IFMT
    }

    // MARK: - Atividade

    /// O que diz se a worktree está em uso.
    struct Activity: Sendable {
        /// Data mais nova vista (arquivos, pastas, último commit ou checkout).
        var latest: Date?
        /// Em uso sem depender da data: sessão viva do agente na worktree ou teto de entradas estourado.
        var forced = false

        func isRecent(now: Date) -> Bool {
            forced || latest.map { now.timeIntervalSince($0) <= RebuildableFinder.recentWindow } ?? false
        }

        mutating func see(_ date: Date) { latest = max(latest ?? date, date) }
    }

    /// Atividade da worktree, recalculada do zero (as recriáveis puladas são as mesmas da análise). O removedor usa esta
    /// função para saber se o agente voltou a mexer.
    func activity(of worktree: Worktree) -> Activity {
        activity(of: worktree, skipping: Set((candidates(for: worktree) ?? []).map(\.rel)))
    }

    /// Regras (na dúvida, "em uso"):
    /// - sessão do Claude Code viva com o `cwd` dentro da worktree → em uso;
    /// - worktree dentro de um job do Claude Code que não terminou (`~/.claude/jobs/<id>`, ex.: `blocked`) → em uso;
    /// - com git e worktree ligada: os caminhos do `git status --no-optional-locks` (que não regrava o índice), a data
    ///   do último commit ou checkout (`lastReflogDate` de `<registro>/logs/HEAD`) e, nas pastas novas, tudo o que há dentro; caminho apagado conta
    ///   pela data da pasta que sobrou;
    /// - sem git, em órfã ou se o status falhar: tudo, sem limite de nível;
    /// - em todos os casos, as datas das pastas visitadas contam (um arquivo apagado só muda a pasta);
    /// - só as recriáveis que podem sair (`skipping`) e `.git` ficam de fora; nada de seguir links;
    /// - mais de `activityEntryLimit` entradas → em uso.
    /// O índice do registro (`.git/worktrees/<n>/index`) não conta: qualquer `git status` comum o regrava.
    private func activity(of worktree: Worktree, skipping: Set<String>) -> Activity {
        let root = worktree.url.path
        var a = Activity()
        if LiveAgentSessions.anyInside(root, sessions: LiveAgentSessions.current(home: home)) { a.forced = true }
        if let job = enclosingJob(root), SessionFinder.isJobActive(job) { a.forced = true }
        var budget = activityEntryLimit

        if let git, !worktree.isOrphan, let changed = git.changedPaths(in: worktree.url) {
            for raw in changed {
                let rel = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
                guard !rel.isEmpty, !rel.hasPrefix("/"), !rel.split(separator: "/").contains(".."),
                      !isInsideSkipped(rel, skipping) else { continue }
                let path = root + "/" + rel
                if let st = lstatInfo(path) {
                    a.see(Self.mtime(st))
                    if st.st_mode & S_IFMT == S_IFDIR, !walk(root: root, from: rel, skipping: skipping, into: &a, budget: &budget) {
                        a.forced = true
                        return a
                    }
                } else {
                    // Apagado: a data da pasta mais próxima que ainda existe.
                    var dir = (rel as NSString).deletingLastPathComponent
                    while true {
                        let p = dir.isEmpty ? root : root + "/" + dir
                        if let st = lstatInfo(p) { a.see(Self.mtime(st)); break }
                        if dir.isEmpty { break }
                        dir = (dir as NSString).deletingLastPathComponent
                    }
                }
            }
            if let registry = registry(of: root), let d = Self.lastReflogDate(registry + "/logs/HEAD") { a.see(d) }
            return a
        }

        if let st = lstatInfo(root) { a.see(Self.mtime(st)) }
        if !walk(root: root, from: "", skipping: skipping, into: &a, budget: &budget) { a.forced = true }
        return a
    }

    /// `~/.claude/jobs/<id>` que contém a worktree, se for o caso (pelo caminho como está e pelo real).
    private func enclosingJob(_ root: String) -> String? {
        let jobs = PathPolicy.lexicalPath(home.path) + "/.claude/jobs/"
        for path in [PathPolicy.lexicalPath(root), PathPolicy.realPath(root)] where path.hasPrefix(jobs) {
            guard let id = path.dropFirst(jobs.count).split(separator: "/").first else { continue }
            return jobs + id
        }
        return nil
    }

    /// Desce a partir de `from` (relativo à worktree), somando as datas de arquivos e pastas. Não desce em `.git` nem nas
    /// recriáveis de `skipping`; não segue links. Devolve `false` quando o teto de entradas estourou.
    private func walk(root: String, from: String, skipping: Set<String>, into a: inout Activity, budget: inout Int) -> Bool {
        var stack = [from]
        var ok = true
        while ok, let rel = stack.popLast() {
            autoreleasepool {
                let dir = rel.isEmpty ? root : root + "/" + rel
                for child in listDir(dir) where child != ".git" {
                    budget -= 1
                    if budget < 0 { ok = false; return }
                    let childRel = rel.isEmpty ? child : rel + "/" + child
                    guard !skipping.contains(childRel), let st = lstatInfo(root + "/" + childRel) else { continue }
                    a.see(Self.mtime(st))
                    if st.st_mode & S_IFMT == S_IFDIR { stack.append(childRel) }
                }
            }
        }
        return ok
    }

    private func isInsideSkipped(_ rel: String, _ skipping: Set<String>) -> Bool {
        if skipping.contains(rel) { return true }
        var prefix = ""
        for part in rel.split(separator: "/") {
            prefix += prefix.isEmpty ? String(part) : "/" + part
            if skipping.contains(prefix) { return true }
        }
        return false
    }

    /// Data do último commit ou checkout da worktree: o carimbo da última linha do reflog
    /// (`<antigo> <novo> <nome> <email> <segundos> <fuso>\t<mensagem>`). A data do arquivo não serve sozinha: o `git gc`
    /// do repositório principal expira o reflog e regrava o `logs/HEAD` de todas as worktrees sem que ninguém tenha feito
    /// commit. Arquivo vazio: `nil`; linha fora do formato: a data do arquivo (lado seguro).
    static func lastReflogDate(_ path: String) -> Date? {
        var st = stat()
        guard lstat(path, &st) == 0, st.st_mode & S_IFMT == S_IFREG, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let tail: Int64 = 65_536
        if Int64(st.st_size) > tail { try? handle.seek(toOffset: UInt64(Int64(st.st_size) - tail)) }
        // `readToEnd()` devolve `nil` no arquivo vazio; só um erro de leitura cai na data do arquivo.
        let data: Data
        do { data = try handle.readToEnd() ?? Data() } catch { return mtime(st) }
        let lines = data.split(separator: UInt8(ascii: "\n"))
        guard let last = lines.last else { return nil }
        let head = last.split(separator: UInt8(ascii: "\t"), maxSplits: 1, omittingEmptySubsequences: false).first ?? last
        let fields = String(decoding: head, as: UTF8.self).split(separator: " ")
        // Do fim: fuso (`-0300`) e segundos.
        guard fields.count >= 4, let zone = fields.last, zone.count == 5, zone.first == "+" || zone.first == "-",
              let seconds = TimeInterval(fields[fields.count - 2]), seconds > 0 else { return mtime(st) }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Registro da worktree (`<repo>/.git/worktrees/<n>`), lido do arquivo `.git` dela (`gitdir: …`).
    private func registry(of root: String) -> String? {
        guard let st = lstatInfo(root + "/.git"), st.st_mode & S_IFMT == S_IFREG,
              let data = FileManager.default.contents(atPath: root + "/.git"), data.count < 64 * 1024,
              let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("gitdir:") {
            let p = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return nil }
            return PathPolicy.lexicalPath(p.hasPrefix("/") ? p : root + "/" + p)
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
