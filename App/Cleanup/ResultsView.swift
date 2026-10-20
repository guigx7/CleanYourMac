import SwiftUI
import AppKit
import CleanYourMacCore

struct ResultsView: View {
    var model: CleanupFlowModel
    @State private var confirmRestart = false
    @State private var appeared = false
    @State private var pendingClean: [JunkItem]?
    @Environment(\.locale) private var locale

    private var tiles: [ResultTile] { model.report.map(ResultTile.make(from:)) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            header
                .padding(.top, 28)
                .padding(.bottom, 36)
            GeometryReader { geo in
                ScrollView {
                    tileGrid(size: CGSize(width: geo.size.width - 56, height: geo.size.height - 28))
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear { withAnimation(.smooth(duration: 0.5)) { appeared = true } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let was = HelperManager.shared.state
            HelperManager.shared.refresh()
            // Aprovado agora nos Ajustes: já mede o Cache do Sistema.
            if was != .active, HelperManager.shared.state == .active, model.canMeasureAdminGroups {
                Task { await model.measureAdminGroups() }
            }
        }
        .modifier(CleanConfirmation(model: model, pending: $pendingClean))
        .environment(\.requestClean) { pendingClean = $0 }
        .alert("results.restart.confirm.title", isPresented: $confirmRestart) {
            Button("common.cancel", role: .cancel) {}
            Button("results.restart", role: .destructive) { model.restart() }
        } message: {
            Text("results.restart.confirm.message")
        }
    }

    /// Na altura da barra de título: Recomeçar à esquerda, nome do módulo ao centro.
    private var topBar: some View {
        ZStack {
            Text("module.cleanup")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack {
                Button { confirmRestart = true } label: {
                    Label("results.restart", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .medium))
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
        VStack(spacing: 16) {
            Text(String(format: NSLocalizedString("results.header", comment: ""),
                        SizeFormatter.string(model.report?.totalSize ?? 0, locale: locale)))
                .font(.system(size: 32, weight: .semibold))
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
            if model.isPartial {
                Label("results.partial", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 10) {
                Button("results.reviewAll") { model.openReview() }
                    .buttonStyle(GlassButtonStyle(size: .large))
                if HelperManager.shared.state != .active, HelperManager.shared.state != .unavailable {
                    Button {
                        HelperManager.shared.install()
                    } label: {
                        Label(HelperManager.shared.state == .needsApproval ? "helper.approve" : "helper.install",
                              systemImage: "shield.lefthalf.filled")
                    }
                    .buttonStyle(GlassButtonStyle(size: .large))
                    .help(Text("helper.install.hint"))
                }
                if model.canMeasureAdminGroups && HelperManager.shared.state != .active {
                    Button {
                        Task { await model.measureAdminGroups() }
                    } label: {
                        if model.adminMeasure == .measuring {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("results.measureAdmin", systemImage: "lock")
                        }
                    }
                    .buttonStyle(GlassButtonStyle(size: .large))
                    .help(Text("results.measureAdmin.hint"))
                }
            }
        }
    }

    /// Cartão principal na coluna esquerda; à direita, o primeiro cartão ocupa a largura toda
    /// e os seguintes vêm em pares. Alturas calculadas para preencher a janela.
    private func tileGrid(size: CGSize) -> some View {
        let main = tiles.first { $0.kind == .systemJunk }
        let others = tiles.filter { $0.kind != .systemJunk }
        let rows = Self.rows(others)
        let spacing: CGFloat = 20
        let rowHeight = rows.isEmpty ? 0 : max(190, (size.height - spacing * CGFloat(rows.count - 1)) / CGFloat(rows.count))
        let totalHeight = max(size.height, rowHeight * CGFloat(rows.count) + spacing * CGFloat(max(0, rows.count - 1)))
        let mainWidth = others.isEmpty ? size.width : min(400, size.width * 0.36)
        let sideWidth = size.width - (main == nil ? 0 : mainWidth + spacing)
        return HStack(alignment: .top, spacing: spacing) {
            if let main {
                TileView(tile: main, model: model, prominent: true, width: mainWidth)
                    .frame(width: mainWidth, height: totalHeight)
                    .modifier(Cascade(index: 0, appeared: appeared))
            }
            if !others.isEmpty {
                VStack(spacing: spacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                        HStack(spacing: spacing) {
                            ForEach(Array(row.enumerated()), id: \.element.id) { c, tile in
                                TileView(tile: tile, model: model, prominent: false,
                                         width: (sideWidth - spacing * CGFloat(row.count - 1)) / CGFloat(row.count))
                                    .frame(width: (sideWidth - spacing * CGFloat(row.count - 1)) / CGFloat(row.count), height: rowHeight)
                                    .modifier(Cascade(index: 1 + r * 2 + c, appeared: appeared))
                            }
                        }
                    }
                }
                .frame(width: sideWidth)
            }
        }
    }

    static func rows(_ tiles: [ResultTile]) -> [[ResultTile]] {
        guard let first = tiles.first else { return [] }
        var out: [[ResultTile]] = [[first]]
        var rest = tiles.dropFirst()
        while !rest.isEmpty {
            out.append(Array(rest.prefix(2)))
            rest = rest.dropFirst(2)
        }
        return out
    }
}

/// Entrada em cascata dos cartões.
private struct Cascade: ViewModifier {
    var index: Int
    var appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(.smooth(duration: 0.45).delay(Double(index) * 0.05), value: appeared)
    }
}

private struct TileView: View {
    var tile: ResultTile
    var model: CleanupFlowModel
    var prominent: Bool
    /// Largura do cartão: os ícones grandes se ajustam a ela (sem estourar o cartão).
    var width: CGFloat
    @Environment(\.locale) private var locale
    @Environment(\.requestClean) private var requestClean

    private var completed: Int64? { model.completedTiles[tile.kind] }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: prominent ? 24 : 19, weight: .medium))
                            .lineSpacing(2)
                            .lineLimit(4)
                            .minimumScaleFactor(0.8)
                        Text(NSLocalizedString("tile.\(tile.kind.key).description", comment: ""))
                            .font(.system(size: prominent ? 16 : 15))
                            .foregroundStyle(Theme.secondaryText)
                            .lineSpacing(2)
                            .lineLimit(3)
                    }
                    if !prominent {
                        Spacer(minLength: 0)
                        icons
                    }
                }
                Spacer(minLength: 16)
                if prominent {
                    prominentIcons.frame(maxWidth: .infinity)
                    Spacer(minLength: 16)
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button("results.action.review") {
                        model.openReview(category: tile.category)
                    }
                    .buttonStyle(GlassButtonStyle(size: .large))
                    if tile.canClean {
                        Button("results.action.clean") {
                            let groups = Set(tile.kind.groups)
                            requestClean(model.report?.recommendedItems().filter { groups.contains($0.group) } ?? [])
                        }
                        .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
                    }
                }
            }
        }
    }

    private var title: String {
        if let completed, tile.size == 0 {
            return String(format: NSLocalizedString("tile.\(tile.kind.key).removed", comment: ""),
                          SizeFormatter.string(completed, locale: locale))
        }
        return String(format: NSLocalizedString("tile.\(tile.kind.key).found", comment: ""),
                      SizeFormatter.string(tile.size, locale: locale))
    }

    /// Ícones pequenos no canto superior direito.
    @ViewBuilder private var icons: some View {
        if tile.kind == .aiClutter, let items = model.report?.groups[.aiAgentsJunk]?.items.prefix(3), !items.isEmpty {
            HStack(spacing: 12) {
                ForEach(Array(items)) { item in
                    ItemIcon(source: item.icon, tint: .white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.18)))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        } else if let group = tile.iconGroups.first {
            CategoryBadge(symbol: group.symbol, size: 40)
        }
    }

    /// Três ícones grandes, o do meio maior (o maior grupo).
    @ViewBuilder private var prominentIcons: some View {
        let groups = tile.iconGroups
        let ordered = groups.count == 3 ? [groups[1], groups[0], groups[2]] : groups
        // Cabe na largura útil do cartão (padding de 28 dos dois lados): grande = 37%, pequenos = 23%.
        let usable = max(120, width - 56)
        let big = min(120, usable * 0.37), small = min(76, usable * 0.23)
        let gap = max(8, (usable - big - 2 * small) / 4)
        HStack(alignment: .center, spacing: gap) {
            ForEach(Array(ordered.enumerated()), id: \.element) { i, g in
                CategoryBadge(symbol: g.symbol, size: ordered.count == 3 && i == 1 ? big : (ordered.count == 3 ? small : big * 0.8))
            }
        }
    }
}

/// Estado "nada encontrado".
struct NothingFoundView: View {
    var model: CleanupFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .cleanup, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text("results.clean.title").font(Theme.display(40))
                Text("results.clean.message").font(.system(size: 17)).foregroundStyle(Theme.secondaryText)
            }
        } action: {
            PrimaryRoundButton(title: "results.restart", action: model.restart)
        }
    }
}

/// Pede uma limpeza passando pelas confirmações (admin, Gerenciamento de Apps).
private struct RequestCleanKey: EnvironmentKey {
    static let defaultValue: @MainActor ([JunkItem]) -> Void = { _ in }
}

extension EnvironmentValues {
    var requestClean: @MainActor ([JunkItem]) -> Void {
        get { self[RequestCleanKey.self] }
        set { self[RequestCleanKey.self] = newValue }
    }
}
