import SwiftUI
import AppKit
import CleanYourMacCore

/// Resultados, no arranjo do CleanMyMac: barra de navegação com o caminho; à esquerda a pasta atual (cabeçalho,
/// "Selecionar:" e a lista); à direita o mapa de bolhas; embaixo o uso do disco e a seleção.
struct SpaceLensResultsView: View {
    var model: SpaceLensFlowModel
    @Environment(\.locale) private var locale
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 14) {
            topBar
            navigationBar.padding(.horizontal, 28)
            HStack(alignment: .top, spacing: 24) {
                folderPanel.frame(width: 360)
                BubbleMap(model: model, hovered: $hovered)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 28)
            bottomBar.padding(.horizontal, 28).padding(.bottom, 16)
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

    // MARK: - Barra de navegação

    private var navigationBar: some View {
        ZStack {
            HStack(spacing: 6) {
                NavButton(symbol: "chevron.left", enabled: model.canGoBack, label: "lens.nav.back") { model.goBack() }
                NavButton(symbol: "chevron.right", enabled: model.canGoForward, label: "lens.nav.forward") { model.goForward() }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(Array((model.current?.ancestry ?? []).enumerated()), id: \.offset) { i, node in
                    if i > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(Theme.secondaryText) }
                    Button { model.jump(to: node) } label: {
                        HStack(spacing: 6) {
                            if node === model.current { SpaceNodeIcon(node: node).frame(width: 18, height: 18) }
                            Text(node.displayName).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: node === model.current ? .semibold : .regular))
                    .foregroundStyle(node === model.current ? .white : Theme.secondaryText)
                }
            }
            .padding(.horizontal, 90)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
    }

    // MARK: - Pasta atual

    private var folderPanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                if let current = model.current {
                    HStack(spacing: 14) {
                        SpaceNodeIcon(node: current).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(current.displayName).font(.system(size: 19, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                            HStack(spacing: 8) {
                                Text(SizeFormatter.string(model.displayedSize(current), locale: locale))
                                Divider().frame(height: 12)
                                Text(String(format: NSLocalizedString("lens.items", comment: ""),
                                            current.items.formatted(.number.notation(.compactName).locale(locale))))
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                Menu {
                    Button("perf.select.none") { model.clearSelection() }
                    Button("perf.select.all") { model.selectAllVisible() }
                } label: {
                    Text(verbatim: NSLocalizedString("perf.select", comment: "") + ": "
                         + NSLocalizedString(model.allVisibleSelected ? "perf.select.all" : "perf.select.none", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.entries) { entry in
                            SpaceEntryRow(entry: entry, model: model, isHovered: hovered == entry.id)
                                .onHover { hovered = $0 ? entry.id : (hovered == entry.id ? nil : hovered) }
                        }
                        if model.othersExpanded {
                            Button { model.collapseOthers() } label: { Label("lens.others.collapse", systemImage: "chevron.up") }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.top, 8)
                        }
                        if model.current?.isUnreadable == true {
                            Label("lens.unreadable", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.top, 8)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    // MARK: - Rodapé

    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 24) {
            if let report = model.report {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(report.volumeName).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(String(format: NSLocalizedString("lens.volume.used", comment: ""), SizeFormatter.string(report.used, locale: locale),
                                    SizeFormatter.string(report.capacity, locale: locale)))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    UsageBar(used: report.used, selected: model.selectionSize, capacity: report.capacity)
                }
                .frame(width: 360)
            }
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "info.circle").foregroundStyle(Theme.secondaryText)
                Text(String(format: NSLocalizedString(model.selection.count == 1 ? "review.selection.one" : "review.selection.other", comment: ""),
                            model.selection.count))
                Divider().frame(height: 16)
                Text(SizeFormatter.string(model.selectionSize, locale: locale)).monospacedDigit()
            }
            .font(.system(size: 15, weight: .medium))
            Spacer()
            Button("lens.action.review") { model.review() }
                .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
                .disabled(model.selection.isEmpty)
        }
    }
}

/// Caixa de seleção clara para o fundo roxo (quadrado com contorno; marcado = preenchido).
struct LensCheckboxStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(configuration.isOn ? Color.white : .clear)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(isEnabled ? 0.85 : 0.4), lineWidth: 1.5))
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x4A1FA0))
                    }
                }
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

/// Botão quadrado de voltar/avançar.
struct NavButton: View {
    var symbol: String
    var enabled: Bool
    var label: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(enabled ? 0.16 : 0.05)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .white : Theme.secondaryText.opacity(0.5))
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }
}

/// Uso do disco: usados, com o que está marcado destacado no fim.
struct UsageBar: View {
    var used: Int64
    var selected: Int64
    var capacity: Int64

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, cap = Double(max(capacity, 1))
            let u = w * CGFloat(Double(used) / cap), s = w * CGFloat(Double(min(selected, used)) / cap)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(.white.opacity(0.85)).frame(width: max(u - s, 0))
                Capsule().fill(Theme.accent(for: .spaceLens)).frame(width: s).offset(x: max(u - s, 0))
            }
        }
        .frame(height: 6)
    }
}

/// Linha da lista: caixa (ou "i" nos protegidos), ícone do Finder, nome e tamanho. Clique duplo entra na pasta.
struct SpaceEntryRow: View {
    var entry: SpaceLensFlowModel.Entry
    var model: SpaceLensFlowModel
    var isHovered: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            switch entry {
            case .node(let node):
                if model.isProtected(node) {
                    Image(systemName: "info.square.fill")
                        .font(.system(size: 16))
                        .frame(width: 18)
                        .foregroundStyle(.white.opacity(0.7))
                        .help(Text("lens.protected"))
                        .accessibilityLabel(Text("lens.protected"))
                } else {
                    let on = Binding(get: { model.isSelected(node) }, set: { _ in model.toggle(node) })
                    Toggle(isOn: on) { EmptyView() }
                        .toggleStyle(LensCheckboxStyle())
                        .disabled(!model.canToggle(node))
                        .accessibilityLabel(Text(node.displayName))
                }
                SpaceNodeIcon(node: node).frame(width: 30, height: 30)
                Text(node.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(node.name.hasPrefix(".") ? Theme.secondaryText : .white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if node.hasUnreadable { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.secondaryText) }
                Spacer()
                Text(SizeFormatter.string(node.size, locale: locale)).font(.system(size: 14)).monospacedDigit()
            case .others(let size, _):
                Button { model.expandOthers() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).frame(width: 18)
                        Text("lens.others").font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text(SizeFormatter.string(size, locale: locale)).font(.system(size: 14)).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("lens.others.expand"))
            case .purgeable(let size):
                Image(systemName: "sparkles").frame(width: 18)
                Image(systemName: "internaldrive").font(.system(size: 20)).frame(width: 30, height: 30)
                Text("lens.purgeable").font(.system(size: 15, weight: .medium))
                Spacer()
                Text(SizeFormatter.string(size, locale: locale)).font(.system(size: 14)).monospacedDigit()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(isHovered ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if case .node(let n) = entry { model.open(n) } }
    }
}

/// Mapa de bolhas da pasta atual: raio por potência do tamanho (como o CleanMyMac), clique duplo entra; clique duplo
/// no fundo sobe um nível.
struct BubbleMap: View {
    var model: SpaceLensFlowModel
    @Binding var hovered: String?

    var body: some View {
        GeometryReader { geo in
            let entries = model.entries
            let area = CGSize(width: max(geo.size.width - 20, 1), height: max(geo.size.height - 20, 1))
            let layout = BubbleLayout.packAdaptive(entries.map { Double($0.size) }, in: area, minDiameter: 70, padding: 10)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if let parent = model.current?.parent { model.jump(to: parent) } }
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    if !layout.hidden.contains(i) {
                        let c = layout.circles[i]
                        BubbleView(entry: entry, circle: c, isHovered: hovered == entry.id, isSelected: isSelected(entry))
                            .position(x: c.x + 10, y: c.y + 10)
                            .onHover { hovered = $0 ? entry.id : (hovered == entry.id ? nil : hovered) }
                            .onTapGesture(count: 2) { open(entry) }
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.4), value: model.entries.map(\.id))
    }

    private func isSelected(_ entry: SpaceLensFlowModel.Entry) -> Bool {
        if case .node(let n) = entry { return model.isSelected(n) }
        return false
    }

    private func open(_ entry: SpaceLensFlowModel.Entry) {
        switch entry {
        case .node(let node): model.open(node)
        case .others: model.expandOthers()
        case .purgeable: break
        }
    }
}

/// Bolha de vidro roxo com o ícone do item, o nome e o tamanho.
struct BubbleView: View {
    var entry: SpaceLensFlowModel.Entry
    var circle: BubbleLayout.Circle
    var isHovered: Bool
    var isSelected: Bool
    @Environment(\.locale) private var locale

    private var title: String {
        switch entry {
        case .node(let n): n.displayName
        case .others: NSLocalizedString("lens.others", comment: "")
        case .purgeable: NSLocalizedString("lens.purgeable", comment: "")
        }
    }

    var body: some View {
        let d = circle.r * 2
        let iconSize = min(d * 0.36, 130)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x6A3FD8).opacity(0.55), Color(hex: 0x8F6BF2).opacity(isHovered ? 0.85 : 0.65)],
                                     center: .center, startRadius: d * 0.1, endRadius: d * 0.55))
                .overlay(Circle().strokeBorder(isSelected ? Theme.accent(for: .spaceLens) : .white.opacity(isHovered ? 0.6 : 0.28),
                                               lineWidth: isSelected ? 3 : 1.2))
                .shadow(color: Color(hex: 0x2A0E6E).opacity(0.5), radius: 10, y: 4)
            VStack(spacing: d * 0.03) {
                icon.frame(width: iconSize, height: iconSize)
                if d > 110 {
                    Text(title).font(.system(size: min(20, max(11, d / 14)), weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(SizeFormatter.string(entry.size, locale: locale)).font(.system(size: min(18, max(10, d / 16)), weight: .medium))
                } else {
                    Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, d * 0.14)
        }
        .frame(width: d, height: d)
        .help(Text(verbatim: "\(title) — \(SizeFormatter.string(entry.size, locale: locale))"))
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "\(title), \(SizeFormatter.string(entry.size, locale: locale))"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var icon: some View {
        switch entry {
        case .node(let node): SpaceNodeIcon(node: node)
        case .others:
            Image(systemName: "circle.grid.cross.fill").resizable().scaledToFit().padding(6).foregroundStyle(.white.opacity(0.75))
        case .purgeable:
            Image(systemName: "sparkles").resizable().scaledToFit().padding(6).foregroundStyle(.white.opacity(0.8))
        }
    }
}

extension SpaceNode {
    /// Nome que o Finder mostra (pastas do sistema traduzidas, ex.: "Usuários").
    var displayName: String {
        parent == nil && path == "/" ? FileManager.default.displayName(atPath: "/") : FileManager.default.displayName(atPath: path)
    }
}
