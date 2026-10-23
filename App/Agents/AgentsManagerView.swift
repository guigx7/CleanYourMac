import SwiftUI
import AppKit
import CleanYourMacCore

/// Gerenciador de Agentes de IA: seções | conteúdo da seção, com busca, seleção e rodapé.
struct AgentsManagerView: View {
    var model: AgentsFlowModel
    @State private var search = ""
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                List(AgentsFlowModel.Section.allCases, id: \.self,
                     selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) { s in
                    HStack {
                        Label(LocalizedStringKey.dynamic("agents.section.\(s.rawValue)"), systemImage: s.symbol)
                        Spacer()
                        Text(verbatim: SizeFormatter.string(size(of: s), locale: locale)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.sidebar)
                .frame(width: 230)
                Divider()
                switch model.section {
                case .worktrees: AgentsWorktreesSection(model: model, search: search)
                case .sessions: AgentsSessionsSection(model: model, search: search)
                }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(.primary)
        .tint(Theme.agentsTint)
        .agentsPrompts(model)
    }

    private func size(of section: AgentsFlowModel.Section) -> Int64 {
        guard let r = model.report else { return 0 }
        switch section {
        case .worktrees: return r.worktrees.flatMap(\.items).reduce(0) { $0 + $1.size }
        case .sessions: return r.sessions.reduce(0) { $0 + $1.size }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.closeManager() } label: { Label("review.back", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("agents.manager.title").font(.headline)
            Spacer()
            TextField("review.search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        let count = model.selectedCount
        return HStack(spacing: 14) {
            Spacer()
            Text(String(format: NSLocalizedString(count == 1 ? "review.selection.one" : "review.selection.other", comment: ""), count))
            Divider().frame(height: 16)
            AnimatedBytes(bytes: model.selectedSize).foregroundStyle(.secondary)
            Spacer()
            Button { model.requestRemoval() } label: { Text("agents.action.remove").frame(minWidth: 90) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canRemove)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// Selo pequeno ao lado do nome ("em uso", "repositório principal não encontrado").
struct AgentsBadge: View {
    var text: LocalizedStringKey
    var color: Color
    var help: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.14)))
            .help(Text(help))
            .fixedSize()
    }
}

// MARK: - Worktrees

/// Repositório → worktree → pastas recriáveis.
struct AgentsWorktreesSection: View {
    var model: AgentsFlowModel
    var search: String
    /// Repositórios começam abertos; worktrees, fechadas.
    @State private var collapsedRepos: Set<String> = []
    @State private var expandedWorktrees: Set<URL> = []

    private struct RepoGroup: Identifiable {
        let id: String
        let repo: URL?
        let entries: [WorktreeEntry]
        var size: Int64 { entries.flatMap(\.items).reduce(0) { $0 + $1.size } }
    }

    private func matches(_ e: WorktreeEntry) -> Bool {
        let w = e.worktree
        return [w.branch ?? "", w.url.path, w.repo?.lastPathComponent ?? ""].contains { ClutterSearch.matches($0, search) }
    }

    private var groups: [RepoGroup] {
        let entries = (model.report?.worktrees ?? []).filter(matches)
        return Dictionary(grouping: entries) { $0.worktree.repo?.path ?? "" }
            .map { key, list in
                RepoGroup(id: key, repo: list[0].worktree.repo,
                          entries: list.sorted { $0.items.reduce(0) { $0 + $1.size } > $1.items.reduce(0) { $0 + $1.size } })
            }
            .sorted { ($0.repo == nil ? 1 : 0, -$0.size) < ($1.repo == nil ? 1 : 0, -$1.size) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModuleSectionHeader(title: "agents.section.worktrees", description: "agents.section.worktrees.description") { EmptyView() }
            if model.report?.buildFoldersSkipped == true {
                Label("agents.noGit", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            Divider()
            list
        }
    }

    @ViewBuilder private var list: some View {
        let groups = groups
        if groups.isEmpty {
            ModuleEmptyView(symbol: "arrow.triangle.branch", text: "agents.empty")
        } else {
            List {
                ForEach(groups) { g in
                    let all = g.entries.flatMap(\.items).map(\.url.path)
                    // A caixa do repositório marca só as worktrees paradas (a em uso se marca na linha dela); com algo
                    // marcado fora delas fica mista, e desmarcar tira todas as pastas do repositório.
                    let idle = g.entries.filter { !$0.isRecent }.flatMap(\.items).map(\.url.path)
                    let idleState = SelectionModel.State.of(idle, selected: model.isSelected)
                    let otherMarked = all.contains { model.isSelected($0) && !idle.contains($0) }
                    let state: SelectionModel.State = otherMarked && idleState != .mixed ? .mixed : idleState
                    ModuleGroupRow(title: g.repo?.lastPathComponent ?? NSLocalizedString("agents.repo.unknown", comment: ""),
                                   size: g.size, count: all.count, selectedCount: all.filter(model.isSelected).count,
                                   expanded: !collapsedRepos.contains(g.id), tint: Theme.agentsTint,
                                   checkState: idle.isEmpty ? nil : state,
                                   onCheck: {
                                       if idleState == .on { model.setAll(all, selected: false) } else { model.setAll(idle, selected: true) }
                                   },
                                   onExpand: { collapsedRepos.formSymmetricDifference([g.id]) }) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: g.repo?.path ?? "/")).resizable().interpolation(.high)
                    }
                    .help(Text(verbatim: g.repo.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""))
                    if !collapsedRepos.contains(g.id) {
                        ForEach(g.entries, id: \.worktree.url) { e in
                            AgentsWorktreeRow(entry: e, model: model, expanded: expandedWorktrees.contains(e.worktree.url)) {
                                expandedWorktrees.formSymmetricDifference([e.worktree.url])
                            }
                            .padding(.leading, 34)
                            if expandedWorktrees.contains(e.worktree.url) {
                                ForEach(e.items, id: \.url) { item in
                                    ModuleFileRow(url: item.url, size: item.size, date: item.modified, dateHelp: "agents.date.modified",
                                                  selected: model.isSelected(item.url.path), tint: Theme.agentsTint,
                                                  subtitle: relativeParent(item)) { model.toggle(item.url.path) }
                                        .padding(.leading, 68)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    /// Pasta-mãe da recriável dentro da worktree (`apps/web`), ou o nome da worktree se ela está na raiz.
    private func relativeParent(_ item: RebuildableItem) -> String {
        let parent = item.url.deletingLastPathComponent().path, root = item.worktree.path
        let name = item.worktree.lastPathComponent
        guard parent.hasPrefix(root + "/") else { return name }
        return name + "/" + parent.dropFirst(root.count + 1)
    }
}

/// Uma worktree: caixa das pastas dela, branch, selos, caminho, "mudou há X" e o tamanho.
struct AgentsWorktreeRow: View {
    var entry: WorktreeEntry
    var model: AgentsFlowModel
    var expanded: Bool
    var onExpand: () -> Void
    @Environment(\.locale) private var locale

    private var ids: [String] { entry.items.map(\.url.path) }
    private var size: Int64 { entry.items.reduce(0) { $0 + $1.size } }

    private var branch: String {
        entry.worktree.branch ?? NSLocalizedString("agents.worktree.detached", comment: "")
    }

    private var changed: String? {
        guard let date = entry.lastActivity else { return nil }
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        return String(format: NSLocalizedString("agents.worktree.changed", comment: ""), f.localizedString(for: date, relativeTo: Date()))
    }

    var body: some View {
        let state = SelectionModel.State.of(ids, selected: model.isSelected)
        HStack(spacing: 10) {
            TriStateCheckbox(state: state, tint: Theme.agentsTint, label: branch) { model.setAll(ids, selected: state != .on) }
            Button(action: onExpand) {
                HStack(spacing: 10) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").frame(width: 14).foregroundStyle(.secondary)
                    Image(systemName: "arrow.triangle.branch").frame(width: 22).foregroundStyle(Theme.agentsTint)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: branch).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                            if entry.isRecent {
                                AgentsBadge(text: "agents.worktree.inUse", color: .orange, help: "agents.worktree.inUseHelp")
                            }
                            if entry.worktree.isOrphan {
                                AgentsBadge(text: "agents.worktree.orphan", color: .secondary, help: "agents.worktree.orphanHelp")
                            }
                        }
                        Text(verbatim: (entry.worktree.url.path as NSString).abbreviatingWithTildeInPath)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                            .help(Text(verbatim: entry.worktree.url.path))
                    }
                    Spacer()
                    if let changed {
                        Text(verbatim: changed).font(.callout).foregroundStyle(entry.isRecent ? Color.orange : .secondary).lineLimit(1)
                    }
                    Text(verbatim: SizeFormatter.string(size, locale: locale)).foregroundStyle(.secondary).monospacedDigit()
                        .frame(minWidth: 70, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(format: NSLocalizedString(expanded ? "apps.hide" : "apps.show", comment: ""), branch)))
            Button { NSWorkspace.shared.activateFileViewerSelecting([entry.worktree.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help(Text("apps.reveal"))
        }
    }
}

// MARK: - Sessões

/// Agente → projeto → sessão, os restos de sessões apagadas de cada agente e os agentes ainda não suportados.
struct AgentsSessionsSection: View {
    var model: AgentsFlowModel
    var search: String
    /// Agentes começam abertos; projetos e restos, fechados.
    @State private var collapsedAgents: Set<String> = []
    @State private var expandedGroups: Set<String> = []

    /// Agentes que guardam conversas em formatos que ainda não limpamos: aparecem se a pasta existir.
    static let unsupported: [(name: String, path: String)] = [
        ("OpenCode", ".local/share/opencode"), ("Cursor", ".cursor"), ("Copilot", ".copilot"),
    ]

    private var unsupportedFound: [String] {
        let home = model.report?.home ?? FileManager.default.homeDirectoryForCurrentUser
        return Self.unsupported.filter { FileManager.default.fileExists(atPath: home.appendingPathComponent($0.path).path) }.map(\.name)
    }

    private struct SubGroup: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let sessions: [AgentSession]
        var size: Int64 { sessions.reduce(0) { $0 + $1.size } }
    }

    private struct AgentGroup: Identifiable {
        let id: String
        let sessions: [AgentSession]
        /// Projetos (do maior para o menor) e, no fim, os restos de sessões apagadas.
        let subgroups: [SubGroup]
        /// Sessões sem projeto (Codex), direto embaixo do agente.
        let loose: [AgentSession]
        var size: Int64 { sessions.reduce(0) { $0 + $1.size } }
    }

    private func matches(_ s: AgentSession) -> Bool {
        let project = AgentsText.projectLabel(s) ?? ""
        return [s.urls.first?.lastPathComponent ?? "", project, AgentsText.agentName(s.agent)].contains { ClutterSearch.matches($0, search) }
    }

    private var groups: [AgentGroup] {
        let all = (model.report?.sessions ?? []).filter(matches)
        return AgentsCatalog.agents.compactMap { agent in
            let mine = all.filter { $0.agent == agent.id }
            guard !mine.isEmpty else { return nil }
            let newest: (AgentSession, AgentSession) -> Bool = { $0.lastModified > $1.lastModified }
            let live = mine.filter { !$0.isOrphanRemains }
            var subgroups = Dictionary(grouping: live.filter { AgentsText.projectLabel($0) != nil }) { AgentsText.projectLabel($0)! }
                .map { label, list in
                    SubGroup(id: agent.id + "/" + label, title: label, symbol: "folder.fill", sessions: list.sorted(by: newest))
                }
                .sorted { $0.size > $1.size }
            let remains = mine.filter(\.isOrphanRemains)
            if !remains.isEmpty {
                subgroups.append(SubGroup(id: agent.id + "#remains", title: NSLocalizedString("agents.session.remains", comment: ""),
                                          symbol: "archivebox.fill", sessions: remains.sorted(by: newest)))
            }
            return AgentGroup(id: agent.id, sessions: mine, subgroups: subgroups,
                              loose: live.filter { AgentsText.projectLabel($0) == nil }.sorted(by: newest))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModuleSectionHeader(title: "agents.section.sessions", description: "agents.section.sessions.description") { EmptyView() }
            Divider()
            list
        }
    }

    @ViewBuilder private var list: some View {
        let groups = groups, unsupported = unsupportedFound
        if groups.isEmpty && unsupported.isEmpty {
            ModuleEmptyView(symbol: "bubble.left.and.bubble.right", text: "agents.empty")
        } else {
            List {
                ForEach(groups) { g in
                    let ids = g.sessions.map(\.id)
                    let state = SelectionModel.State.of(ids, selected: model.isSelected)
                    ModuleGroupRow(title: AgentsText.agentName(g.id), size: g.size, count: ids.count,
                                   selectedCount: ids.filter(model.isSelected).count, expanded: !collapsedAgents.contains(g.id),
                                   tint: Theme.agentsTint, checkState: state,
                                   onCheck: { model.setAll(ids, selected: state != .on) },
                                   onExpand: { collapsedAgents.formSymmetricDifference([g.id]) }) {
                        CategoryBadge(symbol: "terminal.fill", size: 28, module: .agents)
                    }
                    if !collapsedAgents.contains(g.id) {
                        ForEach(g.subgroups) { sub in subgroup(sub) }
                        ForEach(g.loose) { s in sessionRow(s).padding(.leading, 34) }
                    }
                }
                ForEach(unsupported, id: \.self) { name in
                    Label(String(format: NSLocalizedString("agents.unsupported", comment: ""), name), systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                        .padding(.leading, 4)
                        .help(Text("agents.unsupported.help"))
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder private func subgroup(_ sub: SubGroup) -> some View {
        let ids = sub.sessions.map(\.id)
        let state = SelectionModel.State.of(ids, selected: model.isSelected)
        ModuleGroupRow(title: sub.title, size: sub.size, count: ids.count, selectedCount: ids.filter(model.isSelected).count,
                       expanded: expandedGroups.contains(sub.id), tint: Theme.agentsTint, checkState: state,
                       onCheck: { model.setAll(ids, selected: state != .on) },
                       onExpand: { expandedGroups.formSymmetricDifference([sub.id]) }) {
            Image(systemName: sub.symbol).resizable().scaledToFit().padding(4).foregroundStyle(Theme.agentsTint)
        }
        .padding(.leading, 34)
        if expandedGroups.contains(sub.id) {
            ForEach(sub.sessions) { s in sessionRow(s).padding(.leading, 68) }
        }
    }

    @ViewBuilder private func sessionRow(_ s: AgentSession) -> some View {
        if let url = s.urls.first {
            ModuleFileRow(url: url, size: s.size, date: s.lastModified, dateHelp: "agents.date.modified",
                          selected: model.isSelected(s.id), tint: Theme.agentsTint) { model.toggle(s.id) }
        }
    }
}

// MARK: - Alertas

/// Confirmação da remoção: Lixo sempre; com sessões, que não dá mais para retomá-las; com o Codex, que ele pode seguir
/// listando as conversas.
struct AgentsPrompts: ViewModifier {
    var model: AgentsFlowModel
    @Environment(\.locale) private var locale

    private var removal: Binding<Bool> {
        Binding(get: { model.confirmingRemoval }, set: { model.confirmingRemoval = $0 })
    }

    func body(content: Content) -> some View {
        content
            .alert(removalTitle, isPresented: removal) {
                Button("common.cancel", role: .cancel) {}
                Button("agents.action.remove", role: .destructive) { model.confirmRemoval() }
            } message: {
                Text(removalMessage)
            }
    }

    private var removalTitle: String {
        let n = model.selectedCount
        return String(format: NSLocalizedString(n == 1 ? "agents.confirm.title.one" : "agents.confirm.title.other", comment: ""), n,
                      SizeFormatter.string(model.selectedSize, locale: locale))
    }

    private var removalMessage: String {
        let sessions = (model.report?.sessions ?? []).filter { model.isSelected($0.id) }
        var parts = [NSLocalizedString("agents.confirm.trash", comment: "")]
        if !sessions.isEmpty { parts.append(NSLocalizedString("agents.confirm.sessions", comment: "")) }
        if sessions.contains(where: { $0.agent == "codex" }) { parts.append(NSLocalizedString("agents.confirm.codex", comment: "")) }
        let inUse = (model.report?.worktrees ?? []).filter(\.isRecent).flatMap(\.items)
        if inUse.contains(where: { model.isSelected($0.url.path) }) { parts.append(NSLocalizedString("agents.confirm.inUse", comment: "")) }
        if model.dryRun { parts.append(NSLocalizedString("agents.confirm.dryRun", comment: "")) }
        return parts.joined(separator: "\n\n")
    }
}

extension View {
    func agentsPrompts(_ model: AgentsFlowModel) -> some View { modifier(AgentsPrompts(model: model)) }
}
