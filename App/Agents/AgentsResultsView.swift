import SwiftUI
import CleanYourMacCore

extension AgentsTile {
    /// Seção que o botão Revisar abre.
    var section: AgentsFlowModel.Section {
        switch kind {
        case .worktrees: .worktrees
        case .sessions: .sessions
        }
    }

    var symbol: String { section.symbol }

    func title(locale: Locale) -> String {
        let plural = count == 1 ? ".one" : ".other"
        switch kind {
        case .worktrees:
            return String(format: NSLocalizedString("agents.tile.worktrees.title" + plural, comment: ""), count)
        case .sessions(let agent):
            return String(format: NSLocalizedString("agents.tile.sessions.title" + plural, comment: ""), count, AgentsText.agentName(agent))
        }
    }

    func detail(locale: Locale) -> String {
        let key = section == .worktrees ? "agents.tile.worktrees.detail" : "agents.tile.sessions.detail"
        return String(format: NSLocalizedString(key, comment: ""), SizeFormatter.string(size, locale: locale))
    }
}

struct AgentsResultsView: View {
    var model: AgentsFlowModel
    @State private var appeared = false
    @Environment(\.locale) private var locale

    private var tiles: [AgentsTile] { model.report?.tiles ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            header.padding(.top, 28).padding(.bottom, 32)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                    ForEach(Array(tiles.enumerated()), id: \.element.kind) { i, tile in
                        tileView(tile)
                            .frame(height: 270)
                            .opacity(appeared ? 1 : 0)
                            .animation(.smooth(duration: 0.45).delay(Double(i) * 0.05), value: appeared)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.never)
        }
        .onAppear { withAnimation(.smooth(duration: 0.5)) { appeared = true } }
        .agentsPrompts(model)
    }

    private var topBar: some View {
        ZStack {
            Text("module.agents")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 18) {
                Button { model.back() } label: {
                    Label("review.back", systemImage: "chevron.left").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                Button { model.restart() } label: {
                    Label("results.restart", systemImage: "arrow.counterclockwise").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(height: 40)
    }

    private var header: some View {
        let total = SizeFormatter.string(model.report?.totalSize ?? 0, locale: locale)
        return VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(String(format: NSLocalizedString("agents.results.header", comment: ""), total))
                    .font(.system(size: 30, weight: .semibold))
                Text("agents.results.subtitle").font(.system(size: 16)).foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 640)
            Button("agents.results.reviewAll") {
                model.openManager(model.report?.worktrees.isEmpty == false ? .worktrees : .sessions)
            }
            .buttonStyle(GlassButtonStyle(size: .large))
            if model.report?.buildFoldersSkipped == true {
                Label("agents.noGit", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
            }
        }
    }

    private func tileView(_ tile: AgentsTile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    CategoryBadge(symbol: tile.symbol, size: 36, module: .agents).padding(.bottom, 4)
                    Text(verbatim: tile.title(locale: locale))
                        .font(.system(size: 19, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: tile.detail(locale: locale))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    Spacer()
                    Button("results.action.review") { model.openManager(tile.section, autoselect: true) }
                        .buttonStyle(GlassButtonStyle(size: .large))
                        .fixedSize()
                    Button("results.action.clean") { model.cleanTile(tile) }
                        .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
                        .fixedSize()
                }
            }
        }
    }
}
