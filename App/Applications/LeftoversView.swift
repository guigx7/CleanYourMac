import SwiftUI
import CleanYourMacCore

/// Sobras: grupos (Arquivos de Sobras, Instaladores) | itens.
struct LeftoversView: View {
    var model: AppsFlowModel
    var search: String
    @State private var group = Group.leftovers
    @State private var expanded: Set<String> = []
    @Environment(\.locale) private var locale

    enum Group: Hashable { case leftovers, installers }

    private func items(_ g: Group) -> [JunkItem] {
        let all = g == .leftovers ? (model.report?.leftovers ?? []) : (model.report?.installers ?? [])
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { group }, set: { if let g = $0 { group = g } })) {
                Section {
                    groupRow(.leftovers, "apps.leftovers.files", "puzzlepiece.extension")
                    groupRow(.installers, "apps.leftovers.installers", "shippingbox")
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("apps.section.leftovers").font(.headline)
                        Text("apps.leftovers.description").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 260)
            Divider()
            let list = items(group)
            if list.isEmpty {
                Text(group == .leftovers ? "apps.leftovers.empty" : "apps.installers.empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(list) { item in
                        AppsItemRow(item: item, selection: model.selection, depth: 0, title: item.name,
                                    subtitle: group == .installers ? item.url.map { ($0.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }
                                        : item.detail,
                                    expanded: $expanded)
                        if expanded.contains(item.id) {
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
                .listStyle(.inset)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func groupRow(_ g: Group, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Theme.appsTint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(SizeFormatter.string(items(g).reduce(0) { $0 + $1.totalSize }, locale: locale)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tag(g)
        .padding(.vertical, 4)
    }
}
