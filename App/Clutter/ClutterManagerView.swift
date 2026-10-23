import SwiftUI
import AppKit
import CleanYourMacCore

/// Gerenciador de Acúmulos: categorias | conteúdo da categoria, com busca, ordenação, seleção e rodapé.
struct ClutterManagerView: View {
    var model: ClutterFlowModel
    @State private var search = ""
    @State private var sort = ClutterSort.size
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                List(ClutterFlowModel.Section.allCases, id: \.self,
                     selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) { s in
                    HStack {
                        Label(LocalizedStringKey.dynamic("clutter.section.\(s.rawValue)"),
                              systemImage: ClutterCategory(rawValue: s.rawValue)?.symbol ?? "doc")
                        Spacer()
                        Text(verbatim: SizeFormatter.string(size(of: s), locale: locale)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.sidebar)
                .frame(width: 230)
                Divider()
                switch model.section {
                case .largeOld: LargeOldSectionView(model: model, search: search, sort: sort)
                case .duplicates: DuplicatesSectionView(model: model, search: search, sort: sort)
                case .similar: SimilarSectionView(model: model, search: search, sort: sort)
                case .downloads: DownloadsSectionView(model: model, search: search, sort: sort)
                }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(.primary)
        .tint(Theme.clutterTint)
        .clutterPrompts(model)
    }

    private func size(of section: ClutterFlowModel.Section) -> Int64 {
        guard let r = model.report else { return 0 }
        switch section {
        case .largeOld: return r.largeOld.reduce(0) { $0 + $1.size }
        case .duplicates: return r.duplicates.reduce(0) { $0 + $1.totalSize }
        case .similar: return r.similar.reduce(0) { $0 + $1.totalSize }
        case .downloads: return r.downloads.reduce(0) { $0 + $1.totalSize }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.closeManager() } label: { Label("review.back", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("clutter.manager.title").font(.headline)
            Spacer()
            TextField("review.search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
            Menu {
                ForEach(ClutterSort.allCases, id: \.self) { key in
                    Button { sort = key } label: {
                        if sort == key { Label(key.title, systemImage: "checkmark") } else { Text(key.title) }
                    }
                }
            } label: {
                Text("review.sort") + Text(verbatim: ": ") + Text(sort.title).foregroundColor(Theme.clutterTint)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        let count = model.selectedCount
        return HStack(spacing: 14) {
            Spacer()
            Text(String(format: NSLocalizedString(count == 1 ? "review.selection.one" : "review.selection.other", comment: ""), count))
            Divider().frame(height: 16)
            AnimatedBytes(bytes: model.selectedSize).foregroundStyle(.secondary)
            Spacer()
            Button { model.requestRemoval() } label: { Text("clutter.action.remove").frame(minWidth: 90) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canRemove)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

// MARK: - Peças comuns (as linhas estão em App/Design/ManagerRows.swift)

/// Menu "Selecionar:" de um grupo.
struct ClutterPickMenu: View {
    var options: [ClutterPick]
    var onPick: (ClutterPick) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { p in
                Button(LocalizedStringKey.dynamic("clutter.pick.\(p.rawValue)")) { onPick(p) }
            }
        } label: {
            Text("clutter.pick.label")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Fundo do Baú

struct LargeOldSectionView: View {
    var model: ClutterFlowModel
    var search: String
    var sort: ClutterSort
    @State private var filter = LargeOldFilter.all
    @Environment(\.locale) private var locale

    private var items: [ClutterFile] { model.report?.largeOld ?? [] }
    private var now: Date { Date() }

    var body: some View {
        HStack(spacing: 0) {
            filterColumn.frame(width: 230)
            Divider()
            list.frame(maxWidth: .infinity)
        }
    }

    private var filterColumn: some View {
        let totals = LargeOldFilter.totals(items, selected: model.selection, now: now)
        func rows(_ filters: [LargeOldFilter]) -> [LargeOldFilter] { filters.filter { totals[$0] != nil } }
        return List(selection: Binding(get: { filter }, set: { if let f = $0 { filter = f } })) {
            Section {
                ForEach([LargeOldFilter.all, .selected], id: \.self) { row($0, totals) }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("clutter.section.largeOld").font(.headline)
                    Text("clutter.section.largeOld.description").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 6)
            }
            let kinds = rows(LargeOldFiles.Kind.allCases.map(LargeOldFilter.kind))
            if !kinds.isEmpty { Section("clutter.filter.byKind") { ForEach(kinds, id: \.self) { row($0, totals) } } }
            let sizes = rows(LargeOldFiles.SizeBucket.allCases.reversed().map(LargeOldFilter.size))
            if !sizes.isEmpty { Section("clutter.filter.bySize") { ForEach(sizes, id: \.self) { row($0, totals) } } }
            let ages = rows(LargeOldFiles.AccessAge.allCases.reversed().map(LargeOldFilter.age))
            if !ages.isEmpty { Section("clutter.filter.byAccess") { ForEach(ages, id: \.self) { row($0, totals) } } }
        }
        .listStyle(.sidebar)
    }

    private func row(_ f: LargeOldFilter, _ totals: [LargeOldFilter: Int64]) -> some View {
        HStack {
            Text(verbatim: f.title)
            Spacer()
            Text(verbatim: SizeFormatter.string(totals[f] ?? 0, locale: locale)).foregroundStyle(.secondary).monospacedDigit()
        }
        .tag(f)
    }

    @ViewBuilder private var list: some View {
        let rows = sort.sorted(items.filter { filter.matches($0, selected: model.selection, now: now) && ClutterSearch.matches($0.url.lastPathComponent, search) },
                               name: { $0.url.lastPathComponent }, size: \.size, date: \.accessed)
        if rows.isEmpty {
            ModuleEmptyView(symbol: "archivebox", text: "clutter.empty")
        } else {
            List {
                HStack {
                    let ids = rows.map(\.url.path)
                    let all = ids.allSatisfy(model.selection.contains)
                    TriStateCheckbox(state: all ? .on : ids.contains(where: model.selection.contains) ? .mixed : .off,
                                     tint: Theme.clutterTint, label: NSLocalizedString("clutter.selectAll", comment: "")) {
                        model.setAll(ids, selected: !all)
                    }
                    Text("clutter.selectAll").foregroundStyle(.secondary)
                    Spacer()
                }
                ForEach(rows, id: \.url) { f in
                    ModuleFileRow(url: f.url, size: f.size, date: f.accessed, dateHelp: "clutter.date.accessed",
                                  selected: model.isSelected(f.url.path), tint: Theme.clutterTint) { model.toggle(f.url.path) }
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Duplicatas

struct DuplicatesSectionView: View {
    var model: ClutterFlowModel
    var search: String
    var sort: ClutterSort
    @State private var filter = DuplicateFilter.all
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ModuleSectionHeader(title: "clutter.section.duplicates", description: "clutter.section.duplicates.description") {
                Menu {
                    ForEach(DuplicateFilter.menu, id: \.self) { f in
                        Button { filter = f } label: {
                            if filter == f { Label(f.title, systemImage: "checkmark") } else { Text(f.title) }
                        }
                    }
                } label: {
                    Text("clutter.filter.show") + Text(verbatim: " ") + Text(verbatim: filter.title).foregroundColor(Theme.clutterTint)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Divider()
            list
        }
    }

    @ViewBuilder private var list: some View {
        let groups = sort.sorted((model.report?.duplicates ?? []).filter {
            filter.matches($0, selected: model.selection) && $0.files.contains { ClutterSearch.matches($0.url.lastPathComponent, search) }
        }, name: \.name, size: \.totalSize, date: { $0.files.compactMap(\.created).max() })
        if groups.isEmpty {
            ModuleEmptyView(symbol: "doc.on.doc", text: "clutter.empty")
        } else {
            List {
                ForEach(groups) { g in
                    let ids = g.files.map(\.url.path)
                    ModuleGroupRow(title: g.name, size: g.totalSize, count: g.files.count,
                                   selectedCount: ids.filter(model.selection.contains).count, expanded: expanded.contains(g.id),
                                   tint: Theme.clutterTint,
                                   onExpand: { toggle(g.id) }) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: g.keeper.url.path)).resizable().interpolation(.high)
                    }
                    if expanded.contains(g.id) {
                        HStack {
                            ClutterPickMenu(options: [.none, .keepOldest, .keepNewest, .all]) { p in
                                model.pick(p, group: g.id, items: g.files.map(ClutterPick.Item.init))
                            }
                            Spacer()
                        }
                        .padding(.leading, 34)
                        ForEach(g.files, id: \.url) { f in
                            ModuleFileRow(url: f.url, size: f.size, date: f.created, dateHelp: "clutter.date.created",
                                          selected: model.isSelected(f.url.path), tint: Theme.clutterTint) {
                                model.toggle(f.url.path)
                            }
                            .padding(.leading, 34)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

// MARK: - Imagens Similares

struct SimilarSectionView: View {
    var model: ClutterFlowModel
    var search: String
    var sort: ClutterSort
    @State private var expanded: Set<String> = []
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ModuleSectionHeader(title: "clutter.section.similar", description: "clutter.section.similar.description") { EmptyView() }
            Divider()
            list
        }
    }

    private func title(_ g: SimilarGroup) -> String {
        g.date.map { $0.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)) }
            ?? g.images.first?.url?.lastPathComponent ?? "—"
    }

    @ViewBuilder private var list: some View {
        let groups = sort.sorted((model.report?.similar ?? []).filter { g in
            g.images.contains { ClutterSearch.matches($0.url?.lastPathComponent ?? "", search) } || search.isEmpty
        }, name: title, size: \.totalSize, date: \.date)
        if groups.isEmpty {
            ModuleEmptyView(symbol: "photo.on.rectangle", text: "clutter.empty")
        } else {
            List {
                ForEach(groups) { g in
                    let ids = g.images.map(\.id)
                    ModuleGroupRow(title: title(g), size: g.totalSize, count: g.images.count,
                                   selectedCount: ids.filter(model.selection.contains).count, expanded: expanded.contains(g.id),
                                   tint: Theme.clutterTint,
                                   onExpand: { toggle(g.id) }) {
                        ClutterThumbnail(image: g.images[0], side: 30)
                    }
                    if expanded.contains(g.id) {
                        HStack {
                            ClutterPickMenu(options: [.none, .keepLargest, .keepNewest, .keepOldest, .all]) { p in
                                model.pick(p, group: g.id, items: g.images.map(ClutterPick.Item.init))
                            }
                            Button("clutter.pick.best") {
                                model.setGroup(ids, chosen: Set(g.autoselected.map(\.id)), group: g.id)
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding(.leading, 34)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                            ForEach(g.images) { image in
                                SimilarTile(image: image, selected: model.isSelected(image.id)) {
                                    model.toggle(image.id)
                                }
                            }
                        }
                        .padding(.leading, 34)
                        .padding(.vertical, 6)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

/// Uma imagem da galeria: miniatura, caixa, selo "melhor para manter" e "desfocada".
struct SimilarTile: View {
    var image: SimilarImage
    var selected: Bool
    var onToggle: () -> Void
    @Environment(\.locale) private var locale

    /// Tamanho (fotos da fototeca: "—", sem API pública barata).
    private var details: String { image.size > 0 ? SizeFormatter.string(image.size, locale: locale) : "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ClutterThumbnail(image: image, side: 150)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.clutterTint : .clear, lineWidth: 3))
                TriStateCheckbox(state: selected ? .on : .off, tint: Theme.clutterTint, label: image.url?.lastPathComponent ?? image.id,
                                 action: onToggle)
                    .padding(6)
                    .background(Circle().fill(.background.opacity(0.8)).padding(2))
            }
            .onTapGesture(perform: onToggle)
            HStack(spacing: 4) {
                if image.isBest {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).help(Text("clutter.similar.best"))
                }
                if image.flaws.contains(.blur) {
                    Image(systemName: "drop.halffull").foregroundStyle(.orange).help(Text("clutter.similar.blur"))
                }
                Text(verbatim: image.url?.lastPathComponent ?? NSLocalizedString("clutter.similar.photo", comment: ""))
                    .font(.caption).lineLimit(1).truncationMode(.middle)
            }
            Text(verbatim: details)
                .font(.caption2).foregroundStyle(.secondary)
            if let url = image.url {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help(Text("apps.reveal"))
            }
        }
        .frame(width: 150)
    }
}

/// Miniatura de uma imagem (arquivo pelo ImageIO, foto pelo PhotoKit), carregada fora da linha principal.
struct ClutterThumbnail: View {
    var image: SimilarImage
    var side: CGFloat
    @State private var cg: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side > 40 ? 8 : 4).fill(Color.secondary.opacity(0.12))
            if let cg {
                Image(decorative: cg, scale: 1).resizable().scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side > 40 ? 8 : 4))
        .task(id: image.id) {
            let image = image, px = Int(side * 2)
            cg = await Task.detached(priority: .utility) { ClutterThumbnailCache.load(image, maxPixels: px) }.value
        }
    }
}

enum ClutterThumbnailCache {
    nonisolated(unsafe) private static let cache = NSCache<NSString, CGImageBox>()

    final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    static func load(_ image: SimilarImage, maxPixels: Int) -> CGImage? {
        let key = "\(image.id)#\(maxPixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        let cg: CGImage?
        if let url = image.url {
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            cg = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, opts as CFDictionary) }
        } else {
            cg = PhotoLibrarySource.thumbnail(image.id)
        }
        if let cg { cache.setObject(CGImageBox(cg), forKey: key) }
        return cg
    }
}

// MARK: - Downloads

struct DownloadsSectionView: View {
    var model: ClutterFlowModel
    var search: String
    var sort: ClutterSort
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ModuleSectionHeader(title: "clutter.section.downloads", description: "clutter.section.downloads.description") { EmptyView() }
            Divider()
            list
        }
        .onAppear { expanded.formUnion((model.report?.downloads ?? []).map(\.id)) }
    }

    @ViewBuilder private var list: some View {
        let groups = model.report?.downloads ?? []
        if groups.isEmpty {
            ModuleEmptyView(symbol: "arrow.down.circle", text: "clutter.empty.downloads")
        } else {
            List {
                ForEach(groups) { g in
                    let files = sort.sorted(g.files.filter { ClutterSearch.matches($0.url.lastPathComponent, search) },
                                            name: { $0.url.lastPathComponent }, size: \.size, date: \.downloaded)
                    let ids = g.files.map(\.url.path)
                    ModuleGroupRow(title: g.app.title, size: g.totalSize, count: g.files.count,
                                   selectedCount: ids.filter(model.selection.contains).count, expanded: expanded.contains(g.id),
                                   tint: Theme.clutterTint,
                                   onExpand: { toggle(g.id) }) {
                        AppIconView(app: g.app)
                    }
                    if expanded.contains(g.id) {
                        HStack {
                            Text(String(format: NSLocalizedString("clutter.downloads.groupHint", comment: ""), g.app.title))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                Button("clutter.pick.none") { model.setAll(ids, selected: false) }
                                Button("clutter.pick.older30") {
                                    model.setAll(ids, selected: false)
                                    model.setAll(g.autoselected.map(\.url.path), selected: true)
                                }
                                Button("clutter.pick.allFiles") { model.setAll(ids, selected: true) }
                            } label: {
                                Text("clutter.pick.label")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .padding(.leading, 34)
                        ForEach(files, id: \.url) { item in
                            ModuleFileRow(url: item.url, size: item.size, date: item.downloaded, dateHelp: "clutter.date.downloaded",
                                          selected: model.isSelected(item.url.path), tint: Theme.clutterTint) { model.toggle(item.url.path) }
                                .padding(.leading, 34)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

/// Ícone do app de onde veio o download (pelo identificador; símbolo se não estiver instalado).
struct AppIconView: View {
    var app: DownloadsFinder.App

    private var bundleID: String {
        switch app {
        case .chrome: "com.google.Chrome"
        case .safari: "com.apple.Safari"
        case .slack: "com.tinyspeck.slackmacgap"
        }
    }

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else {
            Image(systemName: "arrow.down.circle.fill").resizable().scaledToFit().foregroundStyle(Theme.clutterTint)
        }
    }
}

// MARK: - Alertas

/// "Selecionar Tudo" num grupo de cópias e a confirmação da remoção.
struct ClutterPrompts: ViewModifier {
    var model: ClutterFlowModel
    @Environment(\.locale) private var locale

    private var selectAll: Binding<Bool> {
        Binding(get: { model.pendingFull != nil }, set: { if !$0 { model.cancelSelectAll() } })
    }

    private var removal: Binding<Bool> {
        Binding(get: { model.confirmingRemoval }, set: { model.confirmingRemoval = $0 })
    }

    func body(content: Content) -> some View {
        content
            .alert("clutter.selectAll.title", isPresented: selectAll) {
                Button("common.cancel", role: .cancel) { model.cancelSelectAll() }
                Button("clutter.selectAll.confirm", role: .destructive) { model.confirmSelectAll() }
            } message: {
                Text("clutter.selectAll.message")
            }
            .alert(removalTitle, isPresented: removal) {
                Button("common.cancel", role: .cancel) {}
                Button("clutter.action.remove", role: .destructive) { model.confirmRemoval() }
            } message: {
                Text(removalMessage)
            }
    }

    private var removalTitle: String {
        let n = model.selectedCount
        return String(format: NSLocalizedString(n == 1 ? "clutter.confirm.title.one" : "clutter.confirm.title.other", comment: ""), n,
                      SizeFormatter.string(model.selectedSize, locale: locale))
    }

    private var removalMessage: String {
        var parts = [NSLocalizedString("clutter.confirm.trash", comment: "")]
        if !model.selectedPhotoIDs.isEmpty { parts.append(NSLocalizedString("clutter.confirm.photos", comment: "")) }
        if model.dryRun { parts.append(NSLocalizedString("clutter.confirm.dryRun", comment: "")) }
        return parts.joined(separator: "\n\n")
    }
}

extension View {
    func clutterPrompts(_ model: ClutterFlowModel) -> some View { modifier(ClutterPrompts(model: model)) }
}
