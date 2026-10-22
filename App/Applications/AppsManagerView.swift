import SwiftUI
import AppKit
import CleanYourMacCore

/// Gerenciador de Aplicativos: seções | conteúdo da seção, com seleção e rodapé.
struct AppsManagerView: View {
    var model: AppsFlowModel
    @State private var search = ""
    @State private var sort = UninstallerSort()
    @State private var confirmAct = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                List(AppsFlowModel.Section.allCases, id: \.self,
                     selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) { s in
                    Label(LocalizedStringKey.dynamic("apps.section.\(s.rawValue)"), systemImage: s.symbol).padding(.vertical, 5)
                }
                .listStyle(.sidebar)
                .frame(width: 190)
                Divider()
                switch model.section {
                case .uninstaller: UninstallerView(model: model, search: search, sort: sort)
                case .updater: UpdaterView(model: model, search: search)
                case .leftovers: LeftoversView(model: model, search: search)
                }
            }
            if model.section != .updater {
                Divider()
                footer
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(.primary)
        .tint(Theme.appsTint)
        .appsPrompts(model, confirmAct: $confirmAct)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.closeManager() } label: { Label("review.back", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("apps.manager.title").font(.headline)
            Spacer()
            TextField("review.search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
            if model.section == .uninstaller {
                Menu {
                    ForEach(UninstallerSort.Key.allCases, id: \.self) { key in
                        Button { sort.choose(key) } label: {
                            if sort.key == key {
                                Label(UninstallerSort(key: key).title, systemImage: sort.ascending ? "chevron.up" : "chevron.down")
                            } else {
                                Text(UninstallerSort(key: key).title)
                            }
                        }
                    }
                } label: {
                    Text("review.sort") + Text(verbatim: ": ") + Text(sort.title).foregroundColor(Theme.appsTint)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Grupos da seção visível: a ação só leva o que é desta seção.
    private var scope: Set<GroupID> {
        model.section == .leftovers ? [.appLeftovers, .appInstallers] : [.appUninstall]
    }

    private var footer: some View {
        let leaves = model.selection.selectedLeaves.filter { scope.contains($0.group) }
        let count = leaves.count
        let allReset = count > 0 && leaves.allSatisfy { AppItemID.mode(of: $0.id) == .reset }
        return HStack(spacing: 14) {
            Spacer()
            Text(String(format: NSLocalizedString(count == 1 ? "review.selection.one" : "review.selection.other", comment: ""), count))
            Divider().frame(height: 16)
            AnimatedBytes(bytes: leaves.reduce(0) { $0 + $1.size }).foregroundStyle(.secondary)
            Spacer()
            Button {
                model.actionScope = scope
                confirmAct = true
            } label: {
                Text(model.section == .leftovers ? "apps.action.remove" : (allReset ? "apps.action.reset" : "apps.action.uninstall"))
                    .frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(count == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

extension AppsFlowModel.Section {
    var symbol: String {
        switch self {
        case .uninstaller: "xmark.bin"
        case .updater: "arrow.triangle.2.circlepath"
        case .leftovers: "puzzlepiece.extension"
        }
    }
}

// MARK: - Linhas em árvore (app → tipo → arquivo)

/// Uma linha com checkbox (ou cadeado), ícone, nome, detalhe e tamanho; abre os filhos.
struct AppsItemRow: View {
    var item: JunkItem
    var selection: AppsSelection
    var depth: Int
    var title: String
    var subtitle: String?
    @Binding var expanded: Set<String>
    @Environment(\.locale) private var locale

    private var selectable: Bool { !AppsSelection.selectable(item).isEmpty }
    private var hasChildren: Bool { item.children.contains { $0.removal != nil || !$0.children.isEmpty || $0.badge == .locked } }

    var body: some View {
        HStack(spacing: 10) {
            if selectable {
                TriStateCheckbox(state: selection.state(of: item), tint: Theme.appsTint, label: title) { selection.toggle(item) }
            } else {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).frame(width: 16)
                    .help(Text(item.badge == .mounted ? "apps.locked.mounted" : "apps.locked.help"))
            }
            if depth != 1 {
                ItemIcon(source: item.icon, tint: Theme.appsTint).frame(width: depth == 0 ? 30 : 22, height: depth == 0 ? 30 : 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1).truncationMode(.middle)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .help(Text(item.url?.path ?? title))
            Spacer()
            Text(SizeFormatter.string(item.totalSize, locale: locale)).foregroundStyle(.secondary).monospacedDigit()
            if depth == 2, let url = item.url, FileManager.default.fileExists(atPath: url.path) {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help(Text("apps.reveal"))
            }
            if !item.children.isEmpty {
                Button {
                    if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) }
                } label: {
                    Image(systemName: expanded.contains(item.id) ? "chevron.down" : "chevron.right").frame(width: 16)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(String(format: NSLocalizedString(expanded.contains(item.id) ? "apps.hide" : "apps.show", comment: ""), title)))
            }
        }
        .padding(.leading, CGFloat(depth) * 26)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

extension ResourceKind {
    var title: String { NSLocalizedString("apps.kind.\(rawValue)", comment: "") }
}

/// Filhos de um item (tipos e arquivos) em ordem alfabética do nome exibido.
func appsChildren(_ item: JunkItem) -> [JunkItem] {
    item.children.sorted { a, b in
        let ta = a.detail.flatMap(ResourceKind.init(rawValue:)).map(\.title) ?? a.name
        let tb = b.detail.flatMap(ResourceKind.init(rawValue:)).map(\.title) ?? b.name
        // Binários sempre primeiro, como referência do app.
        if a.detail == ResourceKind.binaries.rawValue && !a.children.isEmpty { return true }
        if b.detail == ResourceKind.binaries.rawValue && !b.children.isEmpty { return false }
        return ta.localizedCaseInsensitiveCompare(tb) == .orderedAscending
    }
}
