import SwiftUI
import AppKit
import CleanYourMacCore

/// Gerenciador de Desempenho: seções | conteúdo da seção, com seleção e rodapé da seção visível.
struct PerformanceManagerView: View {
    var model: PerformanceFlowModel
    @State private var search = ""

    private var sections: [PerformanceFlowModel.Section] {
        PerformanceFlowModel.Section.allCases.filter { $0 != .snapshots || !(model.report?.snapshots.isEmpty ?? true) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                List(sections, id: \.self,
                     selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) { s in
                    Label(LocalizedStringKey.dynamic("perf.section.\(s.rawValue)"), systemImage: s.symbol).padding(.vertical, 5)
                }
                .listStyle(.sidebar)
                .frame(width: 210)
                Divider()
                switch model.section {
                case .maintenance: MaintenanceView(model: model, search: search)
                case .loginItems, .backgroundItems: StartupItemsView(model: model, search: search)
                case .snapshots: SnapshotsView(model: model)
                }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundStyle(.primary)
        .tint(Theme.perfTint)
        .performancePrompts(model)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.closeManager() } label: { Label("review.back", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("perf.manager.title").font(.headline)
            Spacer()
            TextField("review.search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        let count = model.footerCount
        return HStack(spacing: 14) {
            Spacer()
            Text(String(format: NSLocalizedString(count == 1 ? "review.selection.one" : "review.selection.other", comment: ""), count))
            Spacer()
            switch model.section {
            case .maintenance:
                Button { model.runSelectedTasks() } label: { Text("perf.action.run").frame(minWidth: 90) }
                    .buttonStyle(.borderedProminent)
                    .disabled(count == 0)
            case .loginItems, .backgroundItems:
                StartupFooterButtons(model: model)
            case .snapshots:
                Button(role: .destructive) { model.requestDeleteSnapshots() } label: { Text("perf.action.deleteSnapshots").frame(minWidth: 90) }
                    .buttonStyle(.borderedProminent)
                    .disabled(count == 0)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

extension PerformanceFlowModel.Section {
    var symbol: String {
        switch self {
        case .maintenance: "wrench.and.screwdriver"
        case .loginItems: "power"
        case .backgroundItems: "gearshape.2"
        case .snapshots: "clock.arrow.circlepath"
        }
    }
}

/// Cabeçalho de uma seção: título e frase.
struct PerformanceSectionHeader: View {
    var section: PerformanceFlowModel.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey.dynamic("perf.section.\(section.rawValue)")).font(.title2.weight(.semibold))
            Text(LocalizedStringKey.dynamic("perf.section.\(section.rawValue).description"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
