import Foundation

/// Catálogo fixo dos agentes de IA cobertos pelo módulo "Agentes de IA".
/// Caminhos de `worktreeRoots` são relativos a `~` e aceitam `*` como curinga de um nível.
public enum AgentsCatalog {
    public enum SessionLayout: String, Sendable {
        case claudeCode, codex, gemini
    }

    public struct Agent: Sendable, Equatable {
        public let id: String
        public let name: String
        public let worktreeRoots: [String]
        public let sessions: SessionLayout
    }

    public static let agents: [Agent] = [
        // O padrão `<repo>/.claude/worktrees/*` depende do repositório e é tratado no localizador de worktrees.
        Agent(id: "claude-code", name: "Claude Code", worktreeRoots: [".claude/jobs/*/tmp/*"], sessions: .claudeCode),
        Agent(id: "codex", name: "Codex", worktreeRoots: [".codex/worktrees/*"], sessions: .codex),
        Agent(id: "gemini", name: "Gemini CLI", worktreeRoots: [], sessions: .gemini),
    ]

    /// Pastas que um build ou instalação recria (`node_modules` sempre primeiro).
    public static let rebuildable: [String] = [
        "node_modules",
        ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".vite", ".angular/cache", ".expo",
        "dist", "build", "out", "coverage", ".output", "target", ".gradle", "DerivedData",
        "__pycache__", ".pytest_cache", ".mypy_cache", ".venv", "venv",
    ]

    /// Nunca tocar: memória, histórico, ajustes, skills, plugins e bancos dos agentes.
    public static let neverTouch: [String] = [
        "~/.claude/projects/*/memory",
        "~/.claude/history.jsonl",
        "~/.claude/settings*.json",
        "~/.claude.json",
        "skills",
        "plugins",
        "opencode.db",
        "*.sqlite",
    ]
}
