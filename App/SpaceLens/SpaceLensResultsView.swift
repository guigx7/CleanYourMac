import SwiftUI
import AppKit
import CleanYourMacCore

/// Resultados: uso do disco, lista da pasta atual à esquerda, mapa de bolhas à direita, caminho e seleção embaixo.
struct SpaceLensResultsView: View {
    var model: SpaceLensFlowModel
    @Environment(\.locale) private var locale
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            header.padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 14)
            HStack(spacing: 18) {
                GlassCard { list }
                    .frame(width: 360)
                GlassCard {
                    BubbleMap(entries: model.entries, hovered: $hovered) { entry in
                        if case .node(let node) = entry { model.open(node) }
                    }
                }
            }
            .padding(.horizontal, 28)
            pathBar.padding(.horizontal, 28).padding(.vertical, 10)
            footer
        }
    }

    private var topBar: some View {
        ZStack {
            Text("module.spaceLens").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            HStack(spacing: 18) {
                Button { model.back() } label: {
                    Label("review.back", systemImage: "chevron.left").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                Button { model.restart() } label: {
                    Label("results.restart", systemImage: "arrow.counterclockwise").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(height: 40)
    }

    private var header: some View {
        let report = model.report
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.current?.displayName ?? "").font(Theme.display(30)).lineLimit(1).truncationMode(.middle)
                if let current = model.current {
                    Text(String(format: NSLocalizedString("lens.folder.summary", comment: ""), SizeFormatter.string(model.displayedSize(current), locale: locale),
                                current.items.formatted(.number.notation(.compactName).locale(locale))))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            if let report {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(String(format: NSLocalizedString("lens.volume.used", comment: ""), SizeFormatter.string(report.used, locale: locale),
                                SizeFormatter.string(report.capacity, locale: locale)))
                        .font(.system(size: 13, weight: .semibold))
                    ProgressView(value: Double(report.used), total: Double(max(report.capacity, 1)))
                        .tint(Theme.accent(for: .spaceLens))
                        .frame(width: 220)
                    Text(report.volumeName).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.entries) { entry in
                    SpaceEntryRow(entry: entry, model: model, isHovered: hovered == entry.id)
                        .onHover { hovered = $0 ? entry.id : (hovered == entry.id ? nil : hovered) }
                    Divider().opacity(0.25)
                }
                if model.current?.isUnreadable == true {
                    Label("lens.unreadable", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 10)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack)
                .accessibilityLabel(Text("lens.nav.back"))
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward)
                .accessibilityLabel(Text("lens.nav.forward"))
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array((model.current?.ancestry ?? []).enumerated()), id: \.offset) { i, node in
                        if i > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(Theme.secondaryText) }
                        Button(node.displayName) { model.jump(to: node) }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: node === model.current ? .semibold : .regular))
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(String(format: NSLocalizedString(model.selection.count == 1 ? "review.selection.one" : "review.selection.other", comment: ""),
                        model.selection.count))
            Divider().frame(height: 16)
            Text(SizeFormatter.string(model.selectionSize, locale: locale)).monospacedDigit().foregroundStyle(Theme.secondaryText)
            Spacer()
            if !model.selection.isEmpty {
                Button("lens.select.clear") { model.clearSelection() }.buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
            }
            Button("lens.action.review") { model.review() }
                .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
                .disabled(model.selection.isEmpty)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.black.opacity(0.12))
    }
}

/// Linha da lista: caixa, ícone, nome e tamanho; pastas abrem com clique duplo ou pela seta.
struct SpaceEntryRow: View {
    var entry: SpaceLensFlowModel.Entry
    var model: SpaceLensFlowModel
    var isHovered: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            switch entry {
            case .node(let node):
                if model.isProtected(node) {
                    // Pasta do sistema ou essencial: sem caixa, com a explicação.
                    Image(systemName: "info.circle")
                        .frame(width: 16)
                        .foregroundStyle(Theme.secondaryText)
                        .help(Text("lens.protected"))
                        .accessibilityLabel(Text("lens.protected"))
                } else {
                    let on = Binding(get: { model.isSelected(node) }, set: { _ in model.toggle(node) })
                    Toggle(isOn: on) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .disabled(!model.canToggle(node))
                        .accessibilityLabel(Text(node.displayName))
                }
                SpaceNodeIcon(node: node).frame(width: 22, height: 22)
                Text(node.displayName).lineLimit(1).truncationMode(.middle)
                if node.hasUnreadable { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.secondaryText) }
                Spacer()
                Text(SizeFormatter.string(node.size, locale: locale)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                if node.isDirectory {
                    Button { model.open(node) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(String(format: NSLocalizedString("lens.open", comment: ""), node.displayName)))
                }
            case .others(let size, let nodes):
                Image(systemName: "ellipsis.circle").frame(width: 22 + 16 + 10)
                Text("lens.others").lineLimit(1)
                Text(verbatim: "(\(nodes.count))").foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(SizeFormatter.string(size, locale: locale)).monospacedDigit().foregroundStyle(Theme.secondaryText)
            case .purgeable(let size):
                Image(systemName: "sparkles").frame(width: 22 + 16 + 10)
                Text("lens.purgeable").lineLimit(1)
                Spacer()
                Text(SizeFormatter.string(size, locale: locale)).monospacedDigit().foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(isHovered ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if case .node(let n) = entry { model.open(n) } }
    }
}

/// Mapa de bolhas da pasta atual: área proporcional ao tamanho; clique numa pasta entra nela.
struct BubbleMap: View {
    var entries: [SpaceLensFlowModel.Entry]
    @Binding var hovered: String?
    var onOpen: (SpaceLensFlowModel.Entry) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width - 24, height: geo.size.height - 24)
            let circles = BubbleLayout.pack(entries.map { Double($0.size) }, in: size, minRadius: 5, padding: 4)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(entries, circles).enumerated()), id: \.element.0.id) { i, pair in
                    let (entry, c) = pair
                    BubbleView(entry: entry, circle: c, index: i, isHovered: hovered == entry.id)
                        .position(x: c.x + 12, y: c.y + 12)
                        .onHover { hovered = $0 ? entry.id : (hovered == entry.id ? nil : hovered) }
                        .onTapGesture { onOpen(entry) }
                }
            }
        }
        .padding(-8)
        .animation(.smooth(duration: 0.4), value: entries.map(\.id))
    }
}

struct BubbleView: View {
    var entry: SpaceLensFlowModel.Entry
    var circle: BubbleLayout.Circle
    var index: Int
    var isHovered: Bool
    @Environment(\.locale) private var locale

    private var title: String {
        switch entry {
        case .node(let n): n.displayName
        case .others: NSLocalizedString("lens.others", comment: "")
        case .purgeable: NSLocalizedString("lens.purgeable", comment: "")
        }
    }

    private var tint: Color {
        switch entry {
        case .node(let n): n.isDirectory ? Color(hex: [0xA98BFF, 0x7FB2FF, 0xF29BD4, 0x8FD6C8, 0xF2C46D][index % 5]) : Color(hex: 0xD8D2F0)
        case .others: Color(hex: 0x9A8FC0)
        case .purgeable: Color(hex: 0x6FD3A8)
        }
    }

    var body: some View {
        let d = circle.r * 2
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(isHovered ? 0.95 : 0.8), tint.opacity(isHovered ? 0.6 : 0.42)],
                                     center: .topLeading, startRadius: 0, endRadius: d))
                .overlay(Circle().strokeBorder(.white.opacity(isHovered ? 0.9 : 0.35), lineWidth: isHovered ? 2 : 1))
            if circle.r > 24 {
                VStack(spacing: 2) {
                    Text(title).font(.system(size: min(15, max(9, circle.r / 4)), weight: .semibold)).lineLimit(1)
                    Text(SizeFormatter.string(entry.size, locale: locale)).font(.system(size: min(13, circle.r / 5)))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, circle.r * 0.25)
                .minimumScaleFactor(0.6)
            }
        }
        .frame(width: d, height: d)
        .help(Text(verbatim: "\(title) — \(SizeFormatter.string(entry.size, locale: locale))"))
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "\(title), \(SizeFormatter.string(entry.size, locale: locale))"))
        .accessibilityAddTraits(.isButton)
    }
}

extension SpaceNode {
    /// Nome que o Finder mostra (pastas do sistema traduzidas, ex.: "Usuários").
    var displayName: String {
        parent == nil && path == "/" ? FileManager.default.displayName(atPath: "/") : FileManager.default.displayName(atPath: path)
    }
}
