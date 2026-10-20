import Foundation

/// Catálogo fixo de ferramentas de IA (docs/re/specs/ai-agents-junk.md). Lista fechada de caminhos:
/// nada fora daqui é tocado (sessões, credenciais, histórico e ajustes ficam sempre).
public enum AICatalog {
    public enum Kind: String, CaseIterable, Sendable {
        case caches, logs, temporary, staleVersions

        var label: String {
            switch self {
            case .caches: "Caches"
            case .logs: "Logs"
            case .temporary: "Temporary files"
            case .staleVersions: "Stale versions"
            }
        }

        var symbol: String {
            switch self {
            case .caches: "archivebox"
            case .logs: "doc.text"
            case .temporary: "clock"
            case .staleVersions: "square.stack.3d.down.right"
            }
        }
    }

    enum Target: Sendable {
        case whole
        /// Arquivos que casam com o padrão, até 4 níveis abaixo da pasta.
        case glob(String)
        /// Filhos diretos são versões; mantém só a apontada pelo link.
        case versions(activeLink: String)
    }

    struct Location: Sendable {
        let path: String
        let target: Target
        let kind: Kind
    }

    struct Tool: Sendable {
        let id: String
        let name: String
        let bundleIDs: [String]
        let cacheFolders: [String]
        let appSupportNames: [String]
        let locations: [Location]
        /// Pastas de primeiro nível em /private/tmp (nome exato; `{uid}` é trocado pelo uid).
        let tmpNames: [String]
        /// Processo que, rodando, impede limpar as pastas temporárias.
        let process: String?
    }

    static let chromiumSubfolders = ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnWebGPUCache",
                                     "GraphiteDawnCache", "Service Worker/CacheStorage"]

    static func whole(_ path: String, _ kind: Kind) -> Location { Location(path: path, target: .whole, kind: kind) }

    static let tools: [Tool] = [
        Tool(id: "claude_code", name: "Claude Code", bundleIDs: [], cacheFolders: ["claude-cli-nodejs"], appSupportNames: [],
             locations: [
                whole("~/.claude/debug", .logs),
                whole("~/.claude/cache", .caches),
                whole("~/.claude/telemetry", .caches),
                whole("~/.claude/stats-cache.json", .caches),
                whole("~/.claude/mcp-needs-auth-cache.json", .caches),
                whole("~/.claude/plugins/install-counts-cache.json", .caches),
                whole("~/.claude/shell-snapshots", .temporary),
                Location(path: "~/.local/share/claude/versions", target: .versions(activeLink: "~/.local/bin/claude"), kind: .staleVersions),
             ], tmpNames: ["claude-{uid}"], process: "claude"),
        Tool(id: "claude_desktop", name: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"], cacheFolders: [],
             appSupportNames: ["Claude"], locations: [whole("~/Library/Logs/Claude", .logs)], tmpNames: [], process: nil),
        Tool(id: "codex", name: "Codex", bundleIDs: ["com.openai.codex", "com.openai.sky.CUAService"], cacheFolders: ["Codex"],
             appSupportNames: ["Codex"],
             locations: [
                whole("~/.codex/tmp", .caches),
                whole("~/.codex/cache/codex_apps_tools", .caches),
                whole("~/.codex/cache/codex_apps_server_info", .caches),
             ], tmpNames: ["codex-browser-use"], process: "codex"),
        Tool(id: "gemini_antigravity", name: "Gemini / Antigravity", bundleIDs: ["com.google.antigravity"], cacheFolders: [],
             appSupportNames: ["Antigravity", "Antigravity IDE"],
             locations: ["Default/Cache", "Default/Code Cache", "Default/GPUCache", "Default/DawnGraphiteCache",
                         "Default/DawnWebGPUCache", "Default/Service Worker/CacheStorage", "GraphiteDawnCache",
                         "component_crx_cache", "extensions_crx_cache"]
                .map { whole("~/.gemini/antigravity-browser-profile/\($0)", .caches) } + [whole("~/.gemini/tmp", .caches)],
             tmpNames: [], process: nil),
        Tool(id: "cursor", name: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"], cacheFolders: [],
             appSupportNames: ["Cursor"],
             locations: [Location(path: "~/.local/share/cursor-agent", target: .glob("*.log"), kind: .logs)],
             tmpNames: [], process: nil),
        Tool(id: "opencode", name: "OpenCode", bundleIDs: [], cacheFolders: [], appSupportNames: [],
             locations: [whole("~/.local/share/opencode/log", .logs), whole("~/.cache/opencode", .caches)],
             tmpNames: ["opencode"], process: "opencode"),
        Tool(id: "chrome_devtools_mcp", name: "Chrome DevTools MCP", bundleIDs: [], cacheFolders: [], appSupportNames: [],
             locations: ["Default/Cache", "Default/Code Cache", "Default/GPUCache", "Default/DawnCache", "Default/GrShaderCache",
                         "Default/GraphiteDawnCache", "Default/Service Worker/CacheStorage", "GraphiteDawnCache",
                         "component_crx_cache", "extensions_crx_cache"]
                .map { whole("~/.cache/chrome-devtools-mcp/chrome-profile/\($0)", .caches) },
             tmpNames: [], process: nil),
    ]

    static let cacheRoots = ["~/Library/Caches", "$DARWIN", "/Library/Caches"]
    static let logRoots = ["~/Library/Logs", "/Library/Logs"]

    static func inFamily(_ name: String, _ bid: String) -> Bool {
        name == bid || name.hasPrefix(bid + ".") || name.hasPrefix(bid + "-")
    }

    /// O caminho pertence a alguma ferramenta do catálogo (exclusão cruzada com caches/registros do usuário).
    public static func claims(_ url: URL, context ctx: ScanContext) -> Bool {
        let path = real(url)
        func inside(_ base: URL) -> Bool {
            let b = real(base)
            return path == b || path.hasPrefix(b + "/")
        }
        let parent = real(url.deletingLastPathComponent())
        let name = url.lastPathComponent
        for tool in tools {
            for loc in tool.locations where inside(ctx.resolve(loc.path)) { return true }
            for appName in tool.appSupportNames {
                for sub in chromiumSubfolders where inside(ctx.resolve("~/Library/Application Support/\(appName)/\(sub)")) { return true }
            }
            for bid in tool.bundleIDs {
                if inside(ctx.resolve("~/Library/Containers/\(bid)/Data/Library/Caches")) { return true }
                for root in cacheRoots + logRoots where parent == real(ctx.resolve(root)) && inFamily(name, bid) { return true }
            }
            for folder in tool.cacheFolders {
                for root in ["~/Library/Caches", "$DARWIN"] where parent == real(ctx.resolve(root)) && name == folder { return true }
            }
        }
        return false
    }

    static func real(_ url: URL) -> String {
        PathPolicy.realPath(url.path)
    }
}

/// Detritos de IA: ferramenta → kind → caminhos. Nada vem recomendado.
public struct AIToolsScanner: ScopedScanner {
    public let group = GroupID.aiAgentsJunk
    private let apps: any AppLookup
    /// Alocado: a baseline nova bateu com o tamanho em disco (não o lógico que a spec supunha).
    private let sizer = FileSizer()

    public init(apps: any AppLookup = WorkspaceAppLookup()) {
        self.apps = apps
    }

    struct Found {
        let url: URL
        let kind: AICatalog.Kind
        let removal: RemovalAction
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(items: AICatalog.tools.flatMap { find($0, context).map(\.url) })
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        var out: [JunkItem] = []
        var total: Int64 = 0
        for tool in AICatalog.tools {
            try Task.checkCancellation()
            var seen = Set<String>()
            let found = find(tool, context).filter { seen.insert(AICatalog.real($0.url)).inserted }
            var kinds: [JunkItem] = []
            for kind in AICatalog.Kind.allCases {
                let leaves = found.filter { $0.kind == kind }.map { f -> JunkItem in
                    report(ScanProgress(group: group, currentPath: f.url.path, bytesFound: total))
                    let size = sizer.allocatedSize(of: f.url)
                    total += size
                    return JunkItem(group: group, name: f.url.lastPathComponent, url: f.url, size: size,
                                    icon: .file(f.url), removal: f.removal)
                }
                guard !leaves.isEmpty else { continue }
                kinds.append(JunkItem(id: "\(group.rawValue):\(tool.id):\(kind.rawValue)", group: group, name: kind.label,
                                      url: nil, size: 0, icon: .symbol(kind.symbol), children: leaves,
                                      displaysChildren: false, titleKey: "aiKind.\(kind.rawValue)"))
            }
            guard !kinds.isEmpty else { continue }
            let app = tool.bundleIDs.lazy.compactMap { apps.application(bundleID: $0) }.first
            out.append(JunkItem(id: "\(group.rawValue):\(tool.id)", group: group, name: tool.name, url: nil, size: 0,
                                icon: app.map { .app($0.url) } ?? .symbol("terminal"), children: kinds))
        }
        return out
    }

    // MARK: - Busca

    private func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    private func children(_ dir: URL) -> [URL] {
        let real = URL(fileURLWithPath: PathPolicy.realPath(dir.path), isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: real, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func find(_ tool: AICatalog.Tool, _ ctx: ScanContext) -> [Found] {
        var out: [Found] = []
        for loc in tool.locations {
            let base = ctx.resolve(loc.path)
            guard exists(base), !RuleBasedScanner.isSymlink(base) else { continue }
            switch loc.target {
            case .whole:
                out.append(Found(url: base, kind: loc.kind, removal: .delete(base)))
            case .glob(let pattern):
                out += globFiles(base, pattern: pattern).map { Found(url: $0, kind: loc.kind, removal: .delete($0)) }
            case .versions(let linkPath):
                let link = ctx.resolve(linkPath)
                out += staleVersions(base, link: link).map { Found(url: $0, kind: loc.kind, removal: .deleteStaleVersion($0, activeLink: link)) }
            }
        }
        for bid in tool.bundleIDs {
            for root in AICatalog.cacheRoots {
                out += children(ctx.resolve(root)).filter { AICatalog.inFamily($0.lastPathComponent, bid) && !RuleBasedScanner.isSymlink($0) }
                    .map { Found(url: $0, kind: .caches, removal: .delete($0)) }
            }
            out += children(ctx.resolve("~/Library/Containers/\(bid)/Data/Library/Caches")).filter { !RuleBasedScanner.isSymlink($0) }
                .map { Found(url: $0, kind: .caches, removal: .delete($0)) }
            for root in AICatalog.logRoots {
                out += children(ctx.resolve(root)).filter { AICatalog.inFamily($0.lastPathComponent, bid) && !RuleBasedScanner.isSymlink($0) }
                    .map { Found(url: $0, kind: .logs, removal: .delete($0)) }
            }
        }
        for folder in tool.cacheFolders {
            for root in ["~/Library/Caches", "$DARWIN"] {
                let u = ctx.resolve(root).appendingPathComponent(folder)
                if exists(u), !RuleBasedScanner.isSymlink(u) { out.append(Found(url: u, kind: .caches, removal: .delete(u))) }
            }
        }
        for appName in tool.appSupportNames {
            for sub in AICatalog.chromiumSubfolders {
                let u = ctx.resolve("~/Library/Application Support/\(appName)/\(sub)")
                if exists(u), !RuleBasedScanner.isSymlink(u) { out.append(Found(url: u, kind: .caches, removal: .delete(u))) }
            }
        }
        let tmp = ctx.resolve("/private/tmp")
        for template in tool.tmpNames {
            let u = tmp.appendingPathComponent(template.replacingOccurrences(of: "{uid}", with: String(ctx.uid)))
            guard exists(u), !RuleBasedScanner.isSymlink(u),
                  let owner = try? FileManager.default.attributesOfItem(atPath: u.path)[.ownerAccountID] as? NSNumber,
                  owner.uint32Value == ctx.uid else { continue }
            let removal: RemovalAction = tool.process.map { .deleteUnlessRunning(u, process: $0) } ?? .delete(u)
            out.append(Found(url: u, kind: .temporary, removal: removal))
        }
        return out
    }

    /// Arquivos que casam com o padrão, no máximo 4 níveis abaixo de `base`.
    private func globFiles(_ base: URL, pattern: String) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        let baseDepth = base.standardizedFileURL.pathComponents.count
        let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        var out: [URL] = []
        while let u = e?.nextObject() as? URL {
            let depth = u.standardizedFileURL.pathComponents.count - baseDepth
            if depth >= 4 { e?.skipDescendants() }
            guard depth <= 4, let v = try? u.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true, v.isSymbolicLink != true,
                  fnmatch(pattern, u.lastPathComponent, 0) == 0 else { continue }
            out.append(u)
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Todos os filhos menos a versão ativa; nenhum se o link não resolver para dentro da pasta.
    func staleVersions(_ dir: URL, link: URL) -> [URL] {
        let candidates = children(dir).filter { !$0.lastPathComponent.hasPrefix(".") }
        guard FileManager.default.fileExists(atPath: link.path) else { return [] }
        let active = AICatalog.real(link)
        guard candidates.contains(where: { AICatalog.real($0) == active }) else { return [] }
        return candidates.filter { u in
            guard AICatalog.real(u) != active else { return false }
            var st = stat()
            if lstat(u.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_nlink > 1 { return false }
            return true
        }
    }
}
