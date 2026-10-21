import SwiftUI
import CleanYourMacCore

/// Atualizador (etapa 1): lista | detalhe. "Atualizar" abre o lugar certo; nada é instalado pelo app.
struct UpdaterView: View {
    var model: AppsFlowModel
    var search: String
    @State private var selected: String?
    @State private var copied = false
    @Environment(\.locale) private var locale

    private var updates: [AppUpdate] {
        let all = model.report?.updates.updates ?? []
        let q = search.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
        // Ordem: última abertura do app (mais recente primeiro); macOS no fim.
        let opened = Dictionary((model.report?.apps ?? []).map { ($0.id, $0.lastOpened ?? .distantPast) }, uniquingKeysWith: { a, _ in a })
        return filtered.sorted { a, b in
            (a.appID.flatMap { opened[$0] } ?? .distantPast) > (b.appID.flatMap { opened[$0] } ?? .distantPast)
        }
    }

    var body: some View {
        let list = updates
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("apps.section.updater").font(.headline)
                    Text("apps.updater.description").font(.caption).foregroundStyle(.secondary)
                    if model.report?.updates.offline == true {
                        Label("apps.updates.offline", systemImage: "wifi.slash").font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(14)
                if list.isEmpty {
                    Text("apps.updater.empty").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(list, selection: $selected) { u in
                        HStack(spacing: 10) {
                            icon(u).frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(displayName(u)).lineLimit(1)
                                Text(String(format: NSLocalizedString("apps.updater.version", comment: ""),
                                            u.installedVersion.isEmpty ? "—" : u.installedVersion))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(u.id)
                        .padding(.vertical, 3)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(width: 320)
            Divider()
            detail(list.first { $0.id == selected } ?? list.first)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func displayName(_ u: AppUpdate) -> String { u.name.hasSuffix(".app") ? String(u.name.dropLast(4)) : u.name }

    @ViewBuilder private func icon(_ u: AppUpdate) -> some View {
        if let id = u.appID, let app = model.report?.apps.first(where: { $0.id == id }) {
            ItemIcon(source: .app(app.url))
        } else {
            ItemIcon(source: .symbol("gearshape.fill"), tint: Theme.appsTint)
        }
    }

    @ViewBuilder private func detail(_ u: AppUpdate?) -> some View {
        if let u {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        icon(u).frame(width: 56, height: 56)
                        Text(displayName(u)).font(.title2.weight(.semibold))
                    }
                    grid(u)
                    if let notes = u.notes, !notes.isEmpty {
                        Text("apps.updater.notes").font(.headline)
                        Text(notes).textSelection(.enabled)
                    }
                    actionButtons(u)
                }
                .padding(24)
            }
        } else {
            Text("apps.updater.empty").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func grid(_ u: AppUpdate) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow { Text("apps.updater.source").foregroundStyle(.secondary); Text(LocalizedStringKey.dynamic("apps.source.\(u.source.rawValue)")) }
            GridRow {
                Text("apps.updater.versions").foregroundStyle(.secondary)
                Text(verbatim: "\(u.installedVersion.isEmpty ? "—" : u.installedVersion) → \(u.availableVersion)")
            }
            if let date = u.releaseDate {
                GridRow { Text("apps.updater.date").foregroundStyle(.secondary); Text(date.formatted(date: .long, time: .omitted)) }
            }
            if let size = u.size {
                GridRow { Text("apps.updater.size").foregroundStyle(.secondary); Text(SizeFormatter.string(size, locale: locale)) }
            }
        }
    }

    @ViewBuilder private func actionButtons(_ u: AppUpdate) -> some View {
        HStack(spacing: 10) {
            switch u.action {
            case .openAppStore:
                Button("apps.updater.open.appStore") { model.perform(u.action) }.buttonStyle(.borderedProminent)
            case .openSoftwareUpdate:
                Button("apps.updater.open.settings") { model.perform(u.action) }.buttonStyle(.borderedProminent)
            case .openApp(_, let notes):
                Button("apps.updater.open.app") { model.perform(u.action) }.buttonStyle(.borderedProminent)
                if let notes { Link("apps.updater.notes.link", destination: notes) }
            case .copyCommand(let command, let homepage):
                Text(verbatim: command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Button(copied ? "apps.updater.copied" : "apps.updater.copy") {
                    model.perform(u.action)
                    copied = true
                }
                .buttonStyle(.borderedProminent)
                if let homepage { Link("apps.updater.homepage", destination: homepage) }
            }
        }
        .controlSize(.large)
        .padding(.top, 6)
        Text("apps.updater.stage1.hint").font(.caption).foregroundStyle(.secondary)
    }
}
