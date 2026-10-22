import SwiftUI
import AppKit
import QuickLook
import CleanYourMacCore

/// Gerenciador de Limpeza: categorias | grupos | itens, com seleção e rodapé (results-screen §2).
struct ReviewView: View {
    var model: CleanupFlowModel
    @State private var category: CategoryID = .systemJunk
    @State private var group: GroupID?
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var sort = ReviewLogic.SortState()
    @State private var expanded: Set<String> = []
    @State private var confirmBack = false
    @State private var quickLookURL: URL?
    @State private var pendingClean: [JunkItem]?

    private var selection: SelectionModel { model.selection }
    private var report: ScanReport? { model.report }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                categoryColumn.frame(width: 210)
                Divider()
                if ReviewLogic.isEmpty(category, report: report) {
                    categoryEmptyState
                } else {
                    groupColumn.frame(width: 300)
                    Divider()
                    itemColumn.frame(maxWidth: .infinity)
                }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(.primary)
        .tint(Theme.reviewTint)
        .quickLookPreview($quickLookURL)
        .modifier(CleanConfirmation(model: model, pending: $pendingClean))
        .onAppear {
            category = model.reviewCategory ?? .systemJunk
            let groups = ReviewLogic.groups(in: category, report: report)
            group = model.reviewGroup.flatMap { groups.contains($0) ? $0 : nil } ?? groups.first
        }
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(250))
            debouncedSearch = search
        }
        .alert("review.back.confirm.title", isPresented: $confirmBack) {
            Button("common.cancel", role: .cancel) {}
            Button("review.back") { model.closeReview() }
        } message: {
            Text("review.back.confirm.message")
        }
        .alert(alertTitle, isPresented: Binding(get: { selection.pendingAlert != nil },
                                                 set: { if !$0 { selection.cancelPending() } })) {
            Button("common.cancel", role: .cancel) { selection.cancelPending() }
            Button(alertConfirm, role: .destructive) { selection.confirmPending() }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: Barra superior

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                if selection.hasChanges { confirmBack = true } else { model.closeReview() }
            } label: {
                Label("review.back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            Spacer()
            Text("review.title").font(.headline)
            Spacer()
            TextField("review.search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
            Menu {
                ForEach(ReviewLogic.SortKey.allCases, id: \.self) { key in
                    Button { sort.choose(key) } label: {
                        if sort.key == key {
                            Label(sortTitle(key), systemImage: sort.ascending ? "chevron.up" : "chevron.down")
                        } else {
                            Text(sortTitle(key))
                        }
                    }
                }
            } label: {
                Text("review.sort") + Text(verbatim: ": ") + Text(sortTitle(sort.key)).foregroundColor(Theme.reviewTint)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sortTitle(_ key: ReviewLogic.SortKey) -> LocalizedStringKey {
        key == .size ? "review.sort.size" : "review.sort.name"
    }

    // MARK: Colunas

    private var categoryColumn: some View {
        List(CategoryID.cleanupCases, id: \.self, selection: Binding(get: { category }, set: { c in
            guard let c else { return }
            category = c
            group = ReviewLogic.groups(in: c, report: report).first
            expanded = []
        })) { c in
            Text(c.title).padding(.vertical, 5)
        }
        .listStyle(.sidebar)
    }

    private var groupColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: category.title, description: "category.\(category.rawValue).description")
            List(ReviewLogic.groups(in: category, report: report), id: \.self, selection: Binding(get: { group }, set: { g in
                group = g
                expanded = []
            })) { g in
                HStack(spacing: 12) {
                    Image(systemName: g.symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.reviewTint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.title).lineLimit(1)
                        let selected = selection.selectedBytes(in: g)
                        Text(SizeFormatter.string(selected > 0 ? selected : (report?.groups[g]?.totalSize ?? 0), locale: .current))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .help(Text(selected > 0 ? "review.size.selected" : "review.size.total"))
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var itemColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let group {
                header(title: group.title, description: "group.\(group.rawValue).description") {
                    selectMenu(group)
                }
                let items = visibleItems(group)
                if items.isEmpty {
                    emptyState(debouncedSearch.isEmpty ? Text("review.empty")
                               : Text(String(format: NSLocalizedString("review.search.none", comment: ""), debouncedSearch)))
                } else {
                    List {
                        ForEach(items) { item in itemRows(item, depth: 0) }
                    }
                    .listStyle(.inset)
                }
            } else {
                emptyState(Text("review.empty"))
            }
        }
    }

    private func selectMenu(_ group: GroupID) -> some View {
        Menu {
            Button("review.select.smart") { selection.select(.smart, in: group) }
                .disabled(!selection.canSmartSelect(group))
            Button("review.select.all") { selection.select(.all, in: group) }
            Button("review.select.none") { selection.select(.none, in: group) }
        } label: {
            Text("review.select") + Text(verbatim: ": ") + Text(presetTitle(selection.presetState(in: group)))
                .foregroundColor(Theme.reviewTint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func presetTitle(_ state: SelectionModel.PresetState) -> LocalizedStringKey {
        switch state {
        case .none: "review.state.none"
        case .all: "review.state.all"
        case .smart: "review.state.smart"
        case .manual: "review.state.manual"
        }
    }

    private func header<Accessory: View>(title: LocalizedStringKey, description: String,
                                         @ViewBuilder accessory: () -> Accessory = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.weight(.semibold))
            Text(LocalizedStringKey(stringLiteral: description))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            accessory()
        }
        .padding(16)
    }

    private func itemRows(_ item: JunkItem, depth: Int) -> AnyView {
        AnyView(Group {
            ItemRow(item: item, depth: depth, state: selection.state(of: item),
                    isExpanded: expanded.contains(item.id),
                    onToggle: { selection.toggle(item) },
                    onExpand: item.children.isEmpty || !item.displaysChildren ? nil : {
                        withAnimation(.snappy(duration: 0.2)) {
                            if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) }
                        }
                    })
            .contextMenu {
                if let url = item.url {
                    Button("review.context.reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("review.context.quicklook") { quickLookURL = url }
                }
                Button(selection.state(of: item) == .on ? "review.context.deselect" : "review.context.select") {
                    selection.toggle(item)
                }
            }
            if expanded.contains(item.id) {
                ForEach(ReviewLogic.sorted(item.children, by: sort.key, ascending: sort.ascending)) { child in
                    itemRows(child, depth: depth + 1)
                }
            }
        })
    }

    private func emptyState(_ text: Text) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(Theme.reviewTint)
            text.foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var categoryEmptyState: some View {
        if ReviewLogic.emptyNeedsDiskAccess(category, hasFullDiskAccess: PermissionsService.hasFullDiskAccess()) {
            VStack(spacing: 10) {
                Image(systemName: "lock.shield").font(.system(size: 44)).foregroundStyle(.orange)
                Text(category.title).font(.title2.weight(.semibold))
                Text("review.category.needsDiskAccess").foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
                Button("permissions.openSettings") { PermissionsService.openSettings(.fullDiskAccess) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal").font(.system(size: 44)).foregroundStyle(Theme.reviewTint)
                Text(category.title).font(.title2.weight(.semibold))
                Text("review.category.empty").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Rodapé

    private var footer: some View {
        HStack(spacing: 14) {
            Spacer()
            Text(String(format: NSLocalizedString(selection.selectedCount == 1 ? "review.selection.one" : "review.selection.other",
                                                  comment: ""), selection.selectedCount))
            Divider().frame(height: 16)
            AnimatedBytes(bytes: selection.selectedBytes).foregroundStyle(.secondary)
            Spacer()
            Button {
                pendingClean = selection.selectedItems
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

    // MARK: Alertas de seleção

    private var alertTitle: LocalizedStringKey {
        selection.pendingAlert == .iosLatestBackup ? "alert.iosLatest.title" : "alert.localModels.title"
    }
    private var alertMessage: LocalizedStringKey {
        selection.pendingAlert == .iosLatestBackup ? "alert.iosLatest.message" : "alert.localModels.message"
    }
    private var alertConfirm: LocalizedStringKey {
        selection.pendingAlert == .iosLatestBackup ? "alert.iosLatest.confirm" : "alert.localModels.confirm"
    }

    // MARK: Dados

    private func visibleItems(_ group: GroupID) -> [JunkItem] {
        let items = ReviewLogic.filter(report?.groups[group]?.items ?? [], query: debouncedSearch)
        return ReviewLogic.sorted(items, by: sort.key, ascending: sort.ascending)
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
            TriStateCheckbox(state: state, label: item.name, action: onToggle)
            ItemIcon(source: item.icon).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if let key = item.titleKey, key != "xcode.simulators" { Text(LocalizedStringKey(stringLiteral: key)) } else { Text(item.name) }
                }
                .lineLimit(1).truncationMode(.middle)
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
                    .accessibilityLabel(Text("review.recommended"))
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

/// Checkbox com estado misto.
struct TriStateCheckbox: View {
    var state: SelectionModel.State
    var tint: Color = Theme.reviewTint
    /// Nome do item, para o leitor de tela ("Marcar Foo.app").
    var label: String = ""
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(state == .off ? Color.secondary : tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.select", comment: ""), label)))
        .accessibilityValue(Text(LocalizedStringKey(state == .on ? "a11y.on" : state == .mixed ? "a11y.mixed" : "a11y.off")))
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
    var tint: Color = Theme.reviewTint

    var body: some View {
        switch source {
        case .file(let url), .app(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        case .symbol(let name):
            Image(systemName: name).resizable().scaledToFit().padding(4).foregroundStyle(tint)
        }
    }
}
