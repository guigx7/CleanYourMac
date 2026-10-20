import SwiftUI
import CleanYourMacCore

struct ResultsView: View {
    var model: CleanupFlowModel
    @State private var confirmRestart = false
    @State private var appeared = false
    @Environment(\.locale) private var locale

    private var tiles: [ResultTile] { model.report.map(ResultTile.make(from:)) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { confirmRestart = true } label: {
                    Label("results.restart", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(GlassButtonStyle())
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)

            VStack(spacing: 14) {
                Text(String(format: NSLocalizedString("results.header", comment: ""),
                            SizeFormatter.string(model.report?.totalSize ?? 0, locale: locale)))
                    .font(Theme.display(34))
                    .multilineTextAlignment(.center)
                if model.isPartial {
                    Label("results.partial", systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                Button("results.reviewAll") { model.openReview() }
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(.top, 8)
            .padding(.bottom, 28)

            ScrollView {
                tileGrid
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            }
            .scrollIndicators(.never)
        }
        .onAppear { withAnimation(.smooth(duration: 0.5)) { appeared = true } }
        .alert("results.restart.confirm.title", isPresented: $confirmRestart) {
            Button("common.cancel", role: .cancel) {}
            Button("results.restart", role: .destructive) { model.restart() }
        } message: {
            Text("results.restart.confirm.message")
        }
    }

    @ViewBuilder private var tileGrid: some View {
        let main = tiles.first { $0.kind == .systemJunk }
        let others = tiles.filter { $0.kind != .systemJunk }
        HStack(alignment: .top, spacing: 16) {
            if let main {
                TileView(tile: main, model: model, prominent: true)
                    .frame(maxWidth: others.isEmpty ? .infinity : 380)
                    .frame(minHeight: 360)
                    .modifier(Cascade(index: 0, appeared: appeared))
            }
            if !others.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { i, tile in
                        TileView(tile: tile, model: model, prominent: false)
                            .frame(minHeight: 172)
                            .modifier(Cascade(index: i + 1, appeared: appeared))
                    }
                }
            }
        }
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
    @Environment(\.locale) private var locale

    private var completed: Int64? { model.completedTiles[tile.kind] }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                if !prominent { icons }
                Text(title)
                    .font(prominent ? Theme.display(26) : .system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(NSLocalizedString("tile.\(tile.kind.key).description", comment: ""))
                    .font(.system(size: prominent ? 15 : 13))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(prominent ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if prominent {
                    Spacer(minLength: 16)
                    icons.frame(maxWidth: .infinity)
                }
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    Spacer()
                    Button("results.action.review") {
                        model.openReview(category: tile.category)
                    }
                    .buttonStyle(GlassButtonStyle())
                    if tile.canClean {
                        Button("results.action.clean") { model.clean(tile: tile.kind) }
                            .buttonStyle(GlassButtonStyle(prominent: true))
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

    @ViewBuilder private var icons: some View {
        if tile.kind == .aiClutter, let items = model.report?.groups[.aiAgentsJunk]?.items.prefix(3), !items.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(items)) { ItemIcon(source: $0.icon, tint: .white).frame(width: 34, height: 34) }
            }
        } else {
            HStack(spacing: prominent ? 22 : 8) {
                ForEach(tile.iconGroups, id: \.self) { g in
                    CategoryBadge(symbol: g.symbol, size: prominent ? 64 : 34)
                }
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
