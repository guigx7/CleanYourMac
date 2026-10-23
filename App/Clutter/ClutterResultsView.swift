import SwiftUI
import CleanYourMacCore

extension ClutterTile {
    /// Categoria que o botão Revisar abre.
    var section: ClutterFlowModel.Section {
        switch kind {
        case .similarRecent, .similarPhotos, .similarGeneric: .similar
        case .duplicatesDesktop, .duplicatesDocuments, .duplicatesFresh, .duplicatesGeneric: .duplicates
        case .largeOld: .largeOld
        case .downloads: .downloads
        }
    }

    var symbol: String { ClutterCategory(rawValue: section.rawValue)?.symbol ?? "doc.fill" }

    func title(locale: Locale) -> String {
        let size = SizeFormatter.string(self.size, locale: locale)
        switch kind {
        case .largeOld: return String(format: NSLocalizedString("clutter.tile.largeOld.title", comment: ""), size)
        case .downloads: return String(format: NSLocalizedString("clutter.tile.downloads.title", comment: ""), size, app?.title ?? "")
        default:
            let key = "clutter.tile.\(kind.rawValue).title" + (count == 1 ? ".one" : ".other")
            return String(format: NSLocalizedString(key, comment: ""), count)
        }
    }

    func detail(locale: Locale) -> String {
        String(format: NSLocalizedString("clutter.tile.\(kind.rawValue).detail", comment: ""), SizeFormatter.string(size, locale: locale))
    }
}

struct ClutterResultsView: View {
    var model: ClutterFlowModel
    @State private var appeared = false
    @Environment(\.locale) private var locale

    private var tiles: [ClutterTile] { model.report?.tiles ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            header.padding(.top, 28).padding(.bottom, 32)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                    ForEach(Array(tiles.enumerated()), id: \.element.kind) { i, tile in
                        tileView(tile)
                            .frame(height: 230)
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
    }

    private var topBar: some View {
        ZStack {
            Text("module.clutter")
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
        let total = model.report?.total ?? 0
        return VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(String(format: NSLocalizedString(total == 1 ? "clutter.results.header.one" : "clutter.results.header.other", comment: ""), total))
                    .font(.system(size: 30, weight: .semibold))
                Text("clutter.results.subtitle").font(.system(size: 16)).foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 640)
            HStack(spacing: 10) {
                Button("clutter.results.reviewAll") { model.openManager(.largeOld) }
                    .buttonStyle(GlassButtonStyle(size: .large))
                if model.report?.isPartial == true {
                    Button("clutter.results.rescan") { model.restart() }
                        .buttonStyle(GlassButtonStyle(size: .large))
                        .help(Text("clutter.results.partial"))
                }
            }
        }
    }

    private func tileView(_ tile: ClutterTile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    CategoryBadge(symbol: tile.symbol, size: 36, module: .clutter).padding(.bottom, 4)
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
                HStack {
                    Spacer()
                    Button("results.action.review") { model.openManager(tile.section, autoselect: true) }
                        .buttonStyle(GlassButtonStyle(size: .large))
                        .fixedSize()
                }
            }
        }
    }
}
