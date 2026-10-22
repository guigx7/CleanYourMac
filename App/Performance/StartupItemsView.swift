import SwiftUI
import AppKit
import CleanYourMacCore

/// Itens de Início ou em Segundo Plano: ativos e o grupo "Desativados", com menu Selecionar.
struct StartupItemsView: View {
    var model: PerformanceFlowModel
    var search: String

    private func filtered(_ items: [StartupItem]) -> [StartupItem] {
        guard !search.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.label ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                PerformanceSectionHeader(section: model.section)
                Menu {
                    Button("perf.select.all") { model.selectedItems = Set(model.visibleItems.map(\.id)) }
                    Button("perf.select.none") { model.selectedItems = [] }
                } label: {
                    Text("perf.select")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.trailing, 20)
                .padding(.bottom, 10)
            }
            if model.visibleItems.isEmpty {
                Spacer()
                Text("perf.items.empty").foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    let on = filtered(model.enabledVisibleItems), off = filtered(model.disabledVisibleItems)
                    if !on.isEmpty {
                        Section { ForEach(on) { StartupItemRow(item: $0, model: model) } }
                    }
                    if !off.isEmpty {
                        Section("perf.items.disabled") { ForEach(off) { StartupItemRow(item: $0, model: model) } }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct StartupItemRow: View {
    var item: StartupItem
    var model: PerformanceFlowModel

    private var icon: NSImage {
        if let app = item.ownerApp, FileManager.default.fileExists(atPath: app.path) { return NSWorkspace.shared.icon(forFile: app.path) }
        return NSWorkspace.shared.icon(for: .propertyList)
    }

    var body: some View {
        let on = Binding(get: { model.selectedItems.contains(item.id) },
                         set: { if $0 { model.selectedItems.insert(item.id) } else { model.selectedItems.remove(item.id) } })
        HStack(spacing: 12) {
            Toggle(isOn: on) { EmptyView() }
                .toggleStyle(.checkbox)
                .accessibilityLabel(Text(item.name))
            Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(LocalizedStringKey.dynamic("perf.kind.\(item.kind.rawValue)")).font(.caption).foregroundStyle(.secondary)
            }
            .help(Text(item.plist?.path ?? item.program?.path ?? item.name))
            Spacer()
            if item.state == .disabled {
                Text("perf.items.state.disabled").font(.caption).foregroundStyle(.secondary)
            }
            if let path = item.plist ?? item.program, FileManager.default.fileExists(atPath: path.path) {
                Button { NSWorkspace.shared.activateFileViewerSelecting([path]) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help(Text("apps.reveal"))
            }
        }
        .padding(.vertical, 3)
    }
}

/// Rodapé das seções de itens: Desativar, Reativar (se houver desativados marcados) e Remover.
struct StartupFooterButtons: View {
    var model: PerformanceFlowModel

    var body: some View {
        let none = model.footerCount == 0
        HStack(spacing: 10) {
            ForEach(model.footerActions, id: \.self) { action in
                switch action {
                case .remove:
                    Button(role: .destructive) { model.requestStartup(.remove) } label: { Text("perf.action.remove").frame(minWidth: 80) }
                        .buttonStyle(.borderedProminent)
                        .disabled(none)
                case .disable, .enable:
                    Button { model.requestStartup(action) } label: {
                        Text(LocalizedStringKey.dynamic("perf.action.\(PerformancePrompts.key(action))")).frame(minWidth: 80)
                    }
                    .disabled(none)
                }
            }
        }
    }
}
