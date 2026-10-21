import SwiftUI
import CleanYourMacCore

/// Desinstalador: filtros | lista de apps (com os arquivos de cada um ao abrir a linha).
struct UninstallerView: View {
    var model: AppsFlowModel
    var search: String
    var sort: UninstallerSort
    @State private var expanded: Set<String> = []
    @Environment(\.locale) private var locale

    private var report: AppsReport? { model.report }
    private var now: Date { report?.date ?? Date() }

    var body: some View {
        HStack(spacing: 0) {
            filterColumn.frame(width: 230)
            Divider()
            list.frame(maxWidth: .infinity)
        }
        #if DEBUG
        .onAppear { expanded.formUnion(model.debugExpanded) }
        #endif
    }

    // MARK: Filtros

    private var filterColumn: some View {
        let counts = AppFilter.counts(apps: report?.apps ?? [], selected: model.selection.selectedAppIDs, now: now)
        let stores = AppStore.allCases.map(AppFilter.store).filter { counts[$0] != nil }
        let vendors = AppVendor.allCases.map(AppFilter.vendor).filter { counts[$0] != nil }
        return List(selection: Binding(get: { model.filter }, set: { if let f = $0 { model.filter = f } })) {
            Section {
                ForEach([AppFilter.all, .unused, .selected], id: \.self) { row($0, counts) }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("apps.section.uninstaller").font(.headline)
                    Text("apps.uninstaller.description").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)
            }
            if !stores.isEmpty {
                Section("apps.filter.stores") { ForEach(stores, id: \.self) { row($0, counts) } }
            }
            if !vendors.isEmpty {
                Section("apps.filter.vendors") { ForEach(vendors, id: \.self) { row($0, counts) } }
            }
            if counts[.audioPlugins] != nil {
                Section("apps.filter.plugins") { row(.audioPlugins, counts) }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ f: AppFilter, _ counts: [AppFilter: Int]) -> some View {
        HStack {
            Text(f.title)
            Spacer()
            Text("\(counts[f] ?? 0)").foregroundStyle(.secondary).monospacedDigit()
        }
        .tag(f)
    }

    // MARK: Lista

    private var visible: [(AppRecord, JunkItem)] {
        guard let report else { return [] }
        let items = Dictionary(report.uninstaller.compactMap { i in AppsTile.appID(of: i).map { ($0, i) } }, uniquingKeysWith: { a, _ in a })
        let apps = UninstallerSort.search(AppFilter.apply(model.filter, to: report.apps, selected: model.selection.selectedAppIDs, now: now), search)
        let sizes = items.mapValues(\.totalSize)
        return sort.sort(apps, sizes: sizes).compactMap { app in items[app.id].map { (app, $0) } }
    }

    @ViewBuilder private var list: some View {
        let rows = visible
        if rows.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2").font(.system(size: 36)).foregroundStyle(.secondary)
                Text(LocalizedStringKey(model.filter == .unused ? "apps.empty.unused" : model.filter == .selected ? "apps.empty.selected" : "apps.empty.all"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(rows, id: \.0.id) { app, item in
                    appRows(app, model.displayedItem(for: item), original: item)
                }
            }
            .listStyle(.inset)
        }
    }

    private func appRows(_ app: AppRecord, _ item: JunkItem, original: JunkItem) -> some View {
        let opened = app.lastOpened.map { $0.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)) }
        return Group {
            AppsItemRow(item: item, selection: model.selection, depth: 0, title: app.name,
                        subtitle: opened.map { String(format: NSLocalizedString("apps.lastOpened", comment: ""), $0) },
                        expanded: $expanded)
            if expanded.contains(item.id) {
                if app.kind == .application {
                    modePicker(app, original)
                }
                ForEach(appsChildren(item)) { kind in
                    AppsItemRow(item: kind, selection: model.selection, depth: 1,
                                title: kind.detail.flatMap(ResourceKind.init(rawValue:))?.title ?? kind.name, subtitle: nil,
                                expanded: $expanded)
                    if expanded.contains(kind.id) {
                        ForEach(kind.children) { leaf in
                            AppsItemRow(item: leaf, selection: model.selection, depth: 2, title: leaf.name,
                                        subtitle: leaf.url.map { ($0.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath },
                                        expanded: $expanded)
                        }
                    }
                }
            }
        }
    }

    /// Desinstalar (app e arquivos) ou Redefinir (só os arquivos; o app fica).
    private func modePicker(_ app: AppRecord, _ item: JunkItem) -> some View {
        let isReset = model.resetApps.contains(app.id)
        return HStack {
            Picker("", selection: Binding(get: { isReset }, set: { on in
                // A linha muda de id ao trocar de modo; mantém aberta.
                let before = model.displayedItem(for: item).id
                model.setReset(on, for: item)
                let after = model.displayedItem(for: item).id
                if expanded.contains(before) { expanded.insert(after) }
            })) {
                Text("apps.mode.uninstall").tag(false)
                Text("apps.mode.reset").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(app.isSelf)
            Text(LocalizedStringKey(app.isSelf ? "apps.mode.self" : app.isProtected ? "apps.mode.protected" : isReset ? "apps.mode.reset.hint" : "apps.mode.uninstall.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, 26)
        .padding(.vertical, 4)
    }
}
