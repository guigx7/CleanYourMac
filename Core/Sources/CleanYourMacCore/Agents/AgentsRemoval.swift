import Foundation

/// Manda para o Lixo as pastas recriáveis e as sessões marcadas, revalidando cada alvo contra a análise. Na dúvida, fica.
///
/// Recriável (proteção estrutural, sem o `neverTouch`, para que `projeto/plugins/node_modules` possa sair):
/// - o caminho fica dentro da worktree (`root`) e termina num nome de `AgentsCatalog.rebuildable`; em worktree órfã, só
///   `node_modules` → senão `kept: protected`;
/// - cada parte do nome aparece com a grafia exata na listagem da pasta-mãe, a pasta é diretório de verdade (não link) e
///   não há link no caminho até ela; a data da pasta é a da análise; a atividade da worktree (`RebuildableFinder.activity`,
///   a mesma medida da análise) não ficou mais nova que a da análise e não há sessão viva do agente nela; o produtor da pasta continua lá (`RebuildableFinder.hasProducer`); com git e worktree ligada, nada rastreado dentro e a pasta de build ainda
///   ignorada → senão `item changed`.
///
/// Sessão (uma unidade: todas as urls são revalidadas antes de mover qualquer uma; se uma falha, nenhuma vai):
/// - cada url fica dentro de `~/.claude`, `~/.codex` ou `~/.gemini` (o `root`) e nada nela casa com
///   `AgentsCatalog.neverTouch` → senão `kept: protected`;
/// - nada virou link, não há link no caminho, nenhuma data ficou mais nova que a da análise e a conversa não virou de um
///   agente vivo (`SessionFinder.activeClaudeSessionIDs`) → senão `item changed`.
public struct AgentsRemover: Sendable {
    private let trasher: any Trasher
    private let home: URL
    private let dryRun: Bool
    private let log: CleanupLog
    private let git: GitTool?

    static let protected = CleanFailure(reason: "kept: protected")
    static let changed = CleanFailure(reason: "item changed")
    /// Tolerância na comparação de datas (o `Date` perde os nanossegundos).
    static let dateTolerance: TimeInterval = 0.001

    public init(trasher: any Trasher = FileTrasher(), home: URL = FileManager.default.homeDirectoryForCurrentUser, dryRun: Bool,
                log: CleanupLog,
                git: GitTool? = GitTool.locate(runner: SystemCommandRunner(), fileExists: { FileManager.default.fileExists(atPath: $0) })) {
        self.git = git
        self.trasher = trasher
        self.home = home
        self.dryRun = dryRun
        self.log = log
    }

    /// Resultado por id do alvo.
    public func remove(_ targets: [AgentsTarget]) async -> [String: Result<Void, CleanFailure>] {
        var out: [String: Result<Void, CleanFailure>] = [:]
        var removed: [String] = [], failed: [String: String] = [:], freed: Int64 = 0
        // Atividade de cada worktree medida uma vez, antes de mover qualquer pasta dela: mover a 1ª muda a data da
        // pasta-mãe, e a 2ª pareceria "mexida depois da análise".
        var activities: [String: RebuildableFinder.Activity] = [:]
        for target in targets {
            let result: Result<Void, CleanFailure>
            if let refusal = validate(target, activities: &activities) {
                result = .failure(refusal)
            } else if dryRun {
                result = .success(())
            } else {
                result = trash(target)
            }
            out[target.id] = result
            switch result {
            case .success: removed.append(target.id); freed += target.size
            case .failure(let f): failed[target.id] = f.reason
            }
        }
        _ = try? log.write(agents: CleanReport(freedBytes: freed, removed: removed, failed: failed, dryRun: dryRun))
        return out
    }

    private func trash(_ target: AgentsTarget) -> Result<Void, CleanFailure> {
        var moved: [String] = []
        for url in target.urls {
            do {
                try trasher.trash(url)
                moved.append(url.path)
            } catch {
                // Sessão que saiu pela metade: a razão (e o registro) dizem quais urls já estão no Lixo.
                let partial = moved.isEmpty ? "" : "partial: \(moved.count) moved (\(moved.joined(separator: ", "))); "
                return .failure(CleanFailure(reason: partial + error.localizedDescription))
            }
        }
        return .success(())
    }

    /// `nil` quando o alvo ainda é o que a análise viu.
    func validate(_ target: AgentsTarget, activities: inout [String: RebuildableFinder.Activity]) -> CleanFailure? {
        guard !target.urls.isEmpty else { return Self.protected }
        switch target.kind {
        case .rebuildable(let name, let isOrphan):
            return validateRebuildable(target, name: name, isOrphanWorktree: isOrphan, activities: &activities)
        case .session:
            // Primeiro as recusas por proteção de todas as urls, depois as mudanças: nada sai se uma falhar.
            for url in target.urls { if let f = sessionProtection(url, root: target.root) { return f } }
            for url in target.urls { if let f = sessionChange(url, modified: target.modified) { return f } }
            // A conversa virou de um agente vivo (sessão aberta ou job não terminal) depois da análise.
            if target.id.hasPrefix("claude-code:") {
                let id = String(target.id.dropFirst("claude-code:".count)).lowercased()
                if SessionFinder.isUUID(id), SessionFinder.activeClaudeSessionIDs(home: home).contains(id) { return Self.changed }
            }
            return nil
        }
    }

    // MARK: - Recriável

    private func validateRebuildable(_ target: AgentsTarget, name: String, isOrphanWorktree: Bool,
                                     activities: inout [String: RebuildableFinder.Activity]) -> CleanFailure? {
        guard target.urls.count == 1, let url = target.urls.first else { return Self.protected }
        let root = target.root.path, path = url.path
        guard PathPolicy.lexicalPath(root) == root, PathPolicy.lexicalPath(path) == path, root != "/",
              path.hasPrefix(root + "/"), AgentsCatalog.rebuildable.contains(name) else { return Self.protected }
        let rel = String(path.dropFirst(root.count + 1))
        guard rel == name || rel.hasSuffix("/" + name) else { return Self.protected }
        // Worktree órfã: a análise só lista `node_modules` (sem o git, nada prova que uma pasta de build é recriável).
        guard !isOrphanWorktree || name == RebuildableFinder.nodeModules else { return Self.protected }

        // Grafia exata de cada parte do nome na listagem (o APFS não diferencia caixa no `lstat`).
        let parts = name.split(separator: "/").map(String.init)
        var dir = String(path.dropLast(name.count + 1))
        for part in parts {
            guard ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).contains(part) else { return Self.changed }
            dir += "/" + part
        }
        // Sem link: nem no lugar da pasta nem no caminho até ela (inclusive a própria worktree).
        guard let st = lstatInfo(path), st.st_mode & S_IFMT == S_IFDIR else { return Self.changed }
        let parent = (path as NSString).deletingLastPathComponent
        guard PathPolicy.realPath(parent) == parent else { return Self.changed }
        guard let modified = target.modified, Self.same(Self.mtime(st), modified) else { return Self.changed }
        // O produtor (o `package.json` ao lado, o `pyvenv.cfg` dentro...) ainda está lá: a mesma regra da análise.
        guard RebuildableFinder.hasProducer(name: name, path: path) else { return Self.changed }
        // O agente voltou a mexer na worktree depois da análise (a mesma medida da análise), ou há uma sessão dele aberta
        // lá dentro, ou não deu para medir.
        let activity: RebuildableFinder.Activity
        if let cached = activities[root] {
            activity = cached
        } else {
            let wt = Worktree(url: URL(fileURLWithPath: root, isDirectory: true), repo: nil, branch: nil, isOrphan: isOrphanWorktree)
            activity = RebuildableFinder(git: git, now: Date(), home: home).activity(of: wt)
            activities[root] = activity
        }
        if activity.forced { return Self.changed }
        if let now = activity.latest {
            guard let before = target.activity, now.timeIntervalSince(before) <= Self.dateTolerance else { return Self.changed }
        }
        // Com git (e worktree ligada), o git confirma de novo: nada rastreado dentro e, nas pastas de build, ainda ignorada.
        // Sem git, a análise também só listou `node_modules` sem perguntar ao git; pasta de build sem git não sai.
        if !isOrphanWorktree {
            let wt = URL(fileURLWithPath: root, isDirectory: true)
            if let git {
                if git.hasTracked(rel, in: wt) { return Self.changed }
                if name != RebuildableFinder.nodeModules, !git.ignored([rel], in: wt).contains(rel) { return Self.changed }
            } else if name != RebuildableFinder.nodeModules {
                return Self.changed
            }
        }
        return nil
    }

    // MARK: - Sessão

    private func sessionProtection(_ url: URL, root: URL) -> CleanFailure? {
        let rootPath = root.path, path = url.path
        guard PathPolicy.lexicalPath(rootPath) == rootPath, PathPolicy.lexicalPath(path) == path, rootPath != "/",
              path.hasPrefix(rootPath + "/"), !AgentsCatalog.isNeverTouch(path, home: home) else { return Self.protected }
        // Dentro de uma pasta de sessão também não pode haver nada protegido.
        guard let st = lstatInfo(path), st.st_mode & S_IFMT == S_IFDIR else { return nil }
        var found: CleanFailure?
        walk(path) { child, _ in
            if AgentsCatalog.isNeverTouch(child, home: home) { found = Self.protected; return false }
            return true
        }
        return found
    }

    private func sessionChange(_ url: URL, modified: Date?) -> CleanFailure? {
        let path = url.path
        guard let modified, let st = lstatInfo(path) else { return Self.changed }
        let type = st.st_mode & S_IFMT
        guard type == S_IFDIR || type == S_IFREG else { return Self.changed }
        let parent = (path as NSString).deletingLastPathComponent
        guard PathPolicy.realPath(parent) == parent else { return Self.changed }
        guard Self.notNewer(Self.mtime(st), than: modified) else { return Self.changed }
        guard type == S_IFDIR else { return nil }
        var newer = false
        let complete = walk(path) { _, st in
            if !Self.notNewer(Self.mtime(st), than: modified) { newer = true; return false }
            return true
        }
        return newer || !complete ? Self.changed : nil
    }

    /// Percorre a pasta sem seguir links, até `SessionFinder.maxWalkEntries` entradas. `visit` devolve `false` para parar.
    /// Devolve `false` quando estourou o limite.
    @discardableResult
    private func walk(_ dir: String, _ visit: (String, stat) -> Bool) -> Bool {
        var stack = [dir]
        var n = 0
        while let d = stack.popLast() {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] {
                n += 1
                if n > SessionFinder.maxWalkEntries { return false }
                let p = d + "/" + name
                guard let st = lstatInfo(p) else { continue }
                if !visit(p, st) { return true }
                if st.st_mode & S_IFMT == S_IFDIR { stack.append(p) }
            }
        }
        return true
    }

    // MARK: - Utilitários

    private func lstatInfo(_ path: String) -> stat? {
        var st = stat()
        return lstat(path, &st) == 0 ? st : nil
    }

    private static func mtime(_ st: stat) -> Date {
        Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
    }

    private static func same(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < dateTolerance }

    private static func notNewer(_ a: Date, than b: Date) -> Bool { a.timeIntervalSince(b) <= dateTolerance }
}
