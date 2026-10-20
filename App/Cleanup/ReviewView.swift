import SwiftUI
import AppKit
import CleanYourMacCore

/// Gerenciador de Limpeza: categorias | grupos | itens, com seleção e rodapé.
struct ReviewView: View {
    var model: CleanupFlowModel
    @State private var category: CategoryID = .systemJunk
    @State private var group: GroupID?
    @State private var search = ""
    @State private var sort: Sort = .size
    @State private var expanded: Set<String> = []

    enum Sort: CaseIterable { case size, name }

    private var selection: SelectionModel { model.selection }
    private var report: ScanReport? { model.report }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                categoryColumn.frame(width: 220)
                Divider()
                groupColumn.frame(width: 300)
                Divider()
                itemColumn.frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(.primary)
        .tint(Theme.reviewTint)
        .onAppear {
            category = model.reviewCategory ?? .systemJunk
            group = groups(in: category).first
        }
    }

    // MARK: Barra superior

    private var topBar: some View {
        HStack {
            Button(action: model.closeReview) {
                Label("review.back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            Spacer()
            Text("review.title").font(.headline)
            Spacer()
            TextField("review.search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Picker("review.sort", selection: $sort) {
                Text("review.sort.size").tag(Sort.size)
                Text("review.sort.name").tag(Sort.name)
            }
            .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.leading, 64) // espaço dos botões da janela
    }

    // MARK: Colunas

    private var categoryColumn: some View {
        List(CategoryID.allCases, id: \.self, selection: Binding(get: { category }, set: { c in
            if let c { category = c; group = groups(in: c).first; expanded = [] }
        })) { c in
            HStack {
                Text(c.title)
                Spacer()
                Text(SizeFormatter.string(report?.totalSize(of: c) ?? 0, locale: .current))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.vertical, 4)
        }
        .listStyle(.sidebar)
    }

    private var groupColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(category.title).font(.title2.weight(.semibold))
                Text(LocalizedStringKey(stringLiteral: "category.\(category.rawValue).description"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            if groups(in: category).isEmpty {
                emptyState
            } else {
                List(groups(in: category), id: \.self, selection: Binding(get: { group }, set: { g in
                    group = g
                    expanded = []
                })) { g in
                    HStack(spacing: 12) {
                        TriStateCheckbox(state: selection.state(of: g)) { selection.toggle(group: g) }
                        Image(systemName: g.symbol)
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.reviewTint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.title).lineLimit(1)
                            Text(SizeFormatter.string(report?.groups[g]?.totalSize ?? 0, locale: .current))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var itemColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let group {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title).font(.title2.weight(.semibold))
                    Text(LocalizedStringKey(stringLiteral: "group.\(group.rawValue).description"))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Menu {
                        Button("review.select.none") { selection.select(.none, in: group) }
                        Button("review.select.recommended") { selection.select(.smart, in: group) }
                        Button("review.select.all") { selection.select(.all, in: group) }
                    } label: {
                        Text("review.select")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(16)
                let items = visibleItems(group)
                if items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(items) { item in
                            itemRows(item, depth: 0)
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                emptyState
            }
        }
    }

    @ViewBuilder
    private func itemRows(_ item: JunkItem, depth: Int) -> AnyView {
        AnyView(Group {
            ItemRow(item: item, depth: depth, state: selection.state(of: item),
                    isExpanded: expanded.contains(item.id),
                    onToggle: { selection.toggle(item) },
                    onExpand: item.children.isEmpty ? nil : {
                        withAnimation(.snappy(duration: 0.2)) {
                            if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) }
                        }
                    })
            if expanded.contains(item.id) {
                ForEach(sorted(item.children)) { child in itemRows(child, depth: depth + 1) }
            }
        })
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(Theme.reviewTint)
            Text("review.empty").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Rodapé

    private var footer: some View {
        HStack(spacing: 14) {
            Spacer()
            Text("review.selection.count \(selection.selectedCount)")
            Divider().frame(height: 16)
            AnimatedBytes(bytes: selection.selectedBytes).foregroundStyle(.secondary)
            Spacer()
            Button {
                model.clean(items: selection.selectedItems)
            } label: {
                Text("review.action.clean").frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selection.selectedCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Dados

    private func groups(in category: CategoryID) -> [GroupID] {
        GroupID.allCases.filter { $0.category == category && (report?.groups[$0]?.totalSize ?? 0) > 0 }
    }

    private func visibleItems(_ group: GroupID) -> [JunkItem] {
        let items = report?.groups[group]?.items ?? []
        let filtered = search.isEmpty ? items : items.filter { matches($0) }
        return sorted(filtered)
    }

    private func matches(_ item: JunkItem) -> Bool {
        item.name.localizedCaseInsensitiveContains(search) || item.children.contains(where: matches)
    }

    private func sorted(_ items: [JunkItem]) -> [JunkItem] {
        switch sort {
        case .size: items.sorted { $0.totalSize > $1.totalSize }
        case .name: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

/// Uma linha de item: checkbox, ícone, nome, selo de recomendado, tamanho e expansão.
private struct ItemRow: View {
    var item: JunkItem
    var depth: Int
    var state: SelectionModel.State
    var isExpanded: Bool
    var onToggle: () -> Void
    var onExpand: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            TriStateCheckbox(state: state, action: onToggle)
            ItemIcon(source: item.icon).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if let detail = item.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            if item.badge == .latest {
                Text("ios.latest").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.reviewTint.opacity(0.15)))
            }
            Spacer()
            if item.isRecommended {
                Image(systemName: "sparkle")
                    .foregroundStyle(Theme.reviewTint)
                    .help(Text("review.recommended"))
            }
            Text(SizeFormatter.string(item.totalSize, locale: .current))
                .foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            if let onExpand {
                Button(action: onExpand) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.borderless)
                .help(Text("review.showContents"))
            } else {
                Color.clear.frame(width: 16)
            }
        }
        .padding(.leading, CGFloat(depth) * 28)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Checkbox nativo com estado misto.
struct TriStateCheckbox: View {
    var state: SelectionModel.State
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(state == .off ? Color.secondary : Theme.reviewTint)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(verbatim: "\(state)"))
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        case .off: "square"
        }
    }
}

/// Ícone do Finder para arquivos/apps, ou um símbolo.
struct ItemIcon: View {
    var source: IconSource

    var body: some View {
        switch source {
        case .file(let url), .app(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        case .symbol(let name):
            Image(systemName: name).resizable().scaledToFit().padding(4).foregroundStyle(Theme.reviewTint)
        }
    }
}
