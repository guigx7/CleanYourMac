import Foundation

/// Cartão dos Resultados de "Agentes de IA".
public struct AgentsTile: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Pastas recriáveis das worktrees paradas (as em uso nas últimas 24 h ficam de fora).
        case worktrees
        /// Sessões antigas de um agente (id do `AgentsCatalog`).
        case sessions(agent: String)
    }

    public let kind: Kind
    /// Worktrees (no cartão de worktrees) ou sessões (no de sessões).
    public let count: Int
    public let size: Int64
    /// Ids marcáveis: caminhos das recriáveis ou ids das sessões.
    public let ids: Set<String>
}

/// Alvo da remoção, com o que a análise viu para revalidar antes de mandar para o Lixo.
public struct AgentsTarget: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Pasta recriável de uma worktree; `name` é o nome do catálogo (`node_modules`, `.angular/cache`...).
        case rebuildable(name: String, isOrphanWorktree: Bool)
        /// Sessão: todas as urls saem juntas ou nenhuma sai.
        case session
    }

    public let id: String
    public let urls: [URL]
    /// Recriável: data da própria pasta. Sessão: a data mais nova entre as urls.
    public let modified: Date?
    /// Worktree da recriável, ou `~/.claude`, `~/.codex`, `~/.gemini` da sessão. Nada sai de fora dela.
    public let root: URL
    public let size: Int64
    /// Atividade da worktree na análise (só nas recriáveis).
    public let activity: Date?
    public let kind: Kind

    public init(id: String, urls: [URL], modified: Date?, root: URL, size: Int64, activity: Date? = nil, kind: Kind) {
        self.id = id
        self.urls = urls
        self.modified = modified
        self.root = root
        self.size = size
        self.activity = activity
        self.kind = kind
    }
}

public struct AgentsReport: Sendable {
    public let home: URL
    public let worktrees: [WorktreeEntry]
    public let sessions: [AgentSession]
    /// Sem git: as pastas de build ficaram de fora (só `node_modules`).
    public let buildFoldersSkipped: Bool
    public let tiles: [AgentsTile]

    public init(home: URL, worktrees: [WorktreeEntry], sessions: [AgentSession], buildFoldersSkipped: Bool) {
        self.home = home
        self.worktrees = worktrees
        self.sessions = sessions
        self.buildFoldersSkipped = buildFoldersSkipped
        tiles = Self.makeTiles(worktrees: worktrees, sessions: sessions)
    }

    /// Itens marcáveis: cada pasta recriável e cada sessão.
    public var total: Int { worktrees.reduce(0) { $0 + $1.items.count } + sessions.count }

    public var totalSize: Int64 {
        worktrees.flatMap(\.items).reduce(0) { $0 + $1.size } + sessions.reduce(0) { $0 + $1.size }
    }

    public var isEmpty: Bool { total == 0 }

    /// Worktrees primeiro (só as paradas), depois um cartão por agente com sessões, na ordem do catálogo.
    static func makeTiles(worktrees: [WorktreeEntry], sessions: [AgentSession]) -> [AgentsTile] {
        var out: [AgentsTile] = []
        let idle = worktrees.filter { !$0.isRecent && !$0.items.isEmpty }
        if !idle.isEmpty {
            let items = idle.flatMap(\.items)
            out.append(AgentsTile(kind: .worktrees, count: idle.count, size: items.reduce(0) { $0 + $1.size },
                                  ids: Set(items.map(\.url.path))))
        }
        for agent in AgentsCatalog.agents {
            let mine = sessions.filter { $0.agent == agent.id }
            guard !mine.isEmpty else { continue }
            out.append(AgentsTile(kind: .sessions(agent: agent.id), count: mine.count, size: mine.reduce(0) { $0 + $1.size },
                                  ids: Set(mine.map(\.id))))
        }
        return out
    }

    /// O relatório sem os itens removidos: worktrees sem recriáveis saem e os cartões são recalculados.
    public func removing(_ ids: Set<String>) -> AgentsReport {
        let worktrees = worktrees.compactMap { e -> WorktreeEntry? in
            let items = e.items.filter { !ids.contains($0.url.path) }
            return items.isEmpty ? nil : WorktreeEntry(worktree: e.worktree, items: items, lastActivity: e.lastActivity, isRecent: e.isRecent)
        }
        return AgentsReport(home: home, worktrees: worktrees, sessions: sessions.filter { !ids.contains($0.id) },
                            buildFoldersSkipped: buildFoldersSkipped)
    }

    /// Pasta do agente de onde a sessão não pode sair.
    func sessionRoot(agent: String) -> URL {
        let layout = AgentsCatalog.agents.first { $0.id == agent }?.sessions
        let dir: String
        switch layout {
        case .claudeCode: dir = ".claude"
        case .codex: dir = ".codex"
        case .gemini: dir = ".gemini"
        // Agente desconhecido: raiz que não existe, e a remoção recusa.
        case nil: dir = ".cym-unknown-agent"
        }
        return home.appendingPathComponent(dir, isDirectory: true)
    }

    /// Alvos dos ids marcados, na ordem do relatório; ids desconhecidos são ignorados.
    public func targets(for ids: Set<String>) -> [AgentsTarget] {
        var out: [AgentsTarget] = []
        for e in worktrees {
            for item in e.items where ids.contains(item.url.path) {
                out.append(AgentsTarget(id: item.url.path, urls: [item.url], modified: item.modified, root: e.worktree.url, size: item.size,
                                        activity: e.lastActivity, kind: .rebuildable(name: item.name, isOrphanWorktree: e.worktree.isOrphan)))
            }
        }
        for s in sessions where ids.contains(s.id) {
            out.append(AgentsTarget(id: s.id, urls: s.urls, modified: s.lastModified, root: sessionRoot(agent: s.agent), size: s.size,
                                    kind: .session))
        }
        return out
    }
}

public enum AgentsScanEvent: Sendable {
    case progress(String)
    case finished(AgentsReport)
}

/// Orquestra a análise: worktrees, pastas recriáveis de cada uma e sessões antigas.
public final class AgentsScan: Sendable {
    private let home: URL
    private let now: @Sendable () -> Date

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, now: @escaping @Sendable () -> Date = { Date() }) {
        self.home = home
        self.now = now
    }

    public func run() -> AsyncThrowingStream<AgentsScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let flag = Flag()
            let thread = Thread { [home, now] in
                do {
                    let cancelled: @Sendable () -> Bool = { flag.isSet }
                    let date = now()
                    continuation.yield(.progress("worktrees"))
                    let worktrees = try WorktreeFinder(home: home).worktrees(isCancelled: cancelled)
                    continuation.yield(.progress("folders"))
                    let git = GitTool.locate(runner: SystemCommandRunner(), fileExists: { FileManager.default.fileExists(atPath: $0) })
                    let finder = RebuildableFinder(git: git, now: date)
                    var entries: [WorktreeEntry] = []
                    for wt in worktrees {
                        if cancelled() { throw CancellationError() }
                        if let e = finder.entry(for: wt) { entries.append(e) }
                    }
                    continuation.yield(.progress("sessions"))
                    if cancelled() { throw CancellationError() }
                    let sessions = SessionFinder(home: home, now: date, worktrees: Set(worktrees.map(\.url))).sessions()
                    if cancelled() { throw CancellationError() }
                    continuation.yield(.finished(AgentsReport(home: home, worktrees: entries, sessions: sessions,
                                                              buildFoldersSkipped: finder.buildFoldersSkipped)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            thread.stackSize = 8 << 20
            continuation.onTermination = { _ in flag.set() }
            thread.start()
        }
    }
}
