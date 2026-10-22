import SwiftUI
import AppKit
import CleanYourMacCore

struct PerformanceResultsView: View {
    var model: PerformanceFlowModel
    @State private var appeared = false

    private var tiles: [PerformanceTile] { model.report.map(PerformanceTile.tiles(for:)) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            header.padding(.top, 28).padding(.bottom, 32)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { i, tile in
                        tileView(tile)
                            .frame(height: 260)
                            .opacity(appeared ? 1 : 0)
                            .animation(.smooth(duration: 0.45).delay(Double(i) * 0.05), value: appeared)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.never)
        }
        .onAppear { withAnimation(.smooth(duration: 0.5)) { appeared = true } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            HelperManager.shared.refresh()
            Task { await HelperManager.shared.checkVersion() }
        }
        .performancePrompts(model)
    }

    private var topBar: some View {
        ZStack {
            Text("module.performance")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack {
                Button { model.restart() } label: {
                    Label("results.restart", systemImage: "arrow.counterclockwise").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(height: 40)
    }

    private var header: some View {
        VStack(spacing: 16) {
            Text("perf.results.header")
                .font(.system(size: 30, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
            HStack(spacing: 10) {
                Button("perf.results.viewAll") { model.openManager(.maintenance) }
                    .buttonStyle(GlassButtonStyle(size: .large))
                HelperButton()
            }
        }
    }

    private func tileView(_ tile: PerformanceTile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: -10) {
                        ForEach(tile.icons, id: \.self) { CategoryBadge(symbol: $0, size: 36, module: .performance) }
                    }
                    .accessibilityHidden(true)
                    .padding(.bottom, 4)
                    Text(String(format: NSLocalizedString(titleKey(tile), comment: ""), tile.count))
                        .font(.system(size: 19, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LocalizedStringKey.dynamic("perf.tile.\(tile.kind.rawValue).description"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    Spacer()
                    ForEach(tile.actions, id: \.self) { action in
                        switch action {
                        case .review(let section):
                            Button("results.action.review") { model.openManager(section) }
                                .buttonStyle(GlassButtonStyle(size: .large))
                                .fixedSize()
                        case .run(let ids):
                            Button(LocalizedStringKey(tile.kind == .freeUpRAM ? "perf.action.freeUp" : "perf.action.runTasks")) {
                                model.runTasks(ids)
                            }
                            .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
                            .fixedSize()
                        }
                    }
                }
            }
        }
    }

    private func titleKey(_ tile: PerformanceTile) -> String {
        let base = "perf.tile.\(tile.kind.rawValue).title"
        switch tile.kind {
        case .maintenance, .loginItems, .backgroundItems: return base + (tile.count == 1 ? ".one" : ".other")
        case .freeUpRAM, .thinSnapshots: return base
        }
    }
}

/// Confirmações do módulo (tarefas demoradas, itens, capturas) e o guia dos itens que só os Ajustes desligam.
struct PerformancePrompts: ViewModifier {
    var model: PerformanceFlowModel

    private var showConfirmation: Binding<Bool> {
        Binding(get: { model.confirmation != nil }, set: { if !$0 { model.cancelConfirmation() } })
    }

    private var showHint: Binding<Bool> {
        Binding(get: { model.settingsHint != nil }, set: { if !$0 { model.dismissSettingsHint() } })
    }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: showConfirmation) {
                Button("common.cancel", role: .cancel) { model.cancelConfirmation() }
                if case .startup(_, _, let owners) = model.confirmation, owners.count == 1 {
                    Button("perf.confirm.openUninstaller") { model.openUninstaller(owners[0]) }
                }
                Button(confirmButton, role: destructive ? .destructive : nil) { model.confirm() }
            } message: {
                Text(message)
            }
            .alert("perf.modern.title", isPresented: showHint) {
                Button("common.ok") { model.dismissSettingsHint() }
            } message: {
                Text(String(format: NSLocalizedString("perf.modern.message", comment: ""),
                            (model.settingsHint ?? []).joined(separator: ", ")))
            }
    }

    private var destructive: Bool {
        switch model.confirmation {
        case .startup(.remove, _, _), .snapshots: true
        default: false
        }
    }

    private var title: String {
        switch model.confirmation {
        case .heavyTasks: NSLocalizedString("perf.confirm.heavy.title", comment: "")
        case .startup(let action, let items, _):
            String(format: NSLocalizedString("perf.confirm.\(Self.key(action)).title", comment: ""), items.count)
        case .snapshots(let list): String(format: NSLocalizedString("perf.confirm.snapshots.title", comment: ""), list.count)
        case nil: ""
        }
    }

    private var confirmButton: LocalizedStringKey {
        switch model.confirmation {
        case .heavyTasks: "perf.action.run"
        case .startup(let action, _, _): .dynamic("perf.action.\(Self.key(action))")
        case .snapshots: "perf.action.deleteSnapshots"
        case nil: "common.ok"
        }
    }

    private var message: String {
        switch model.confirmation {
        case .heavyTasks(let ids):
            return ids.map { NSLocalizedString("perf.confirm.heavy.\($0.rawValue)", comment: "") }.joined(separator: "\n\n")
        case .startup(let action, let items, let owners):
            var parts = [items.map(\.name).joined(separator: ", "), NSLocalizedString("perf.confirm.\(Self.key(action)).message", comment: "")]
            if !owners.isEmpty {
                let names = owners.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: ", ")
                parts.append(String(format: NSLocalizedString("perf.confirm.owner", comment: ""), names))
            }
            return parts.joined(separator: "\n\n")
        case .snapshots: return NSLocalizedString("perf.confirm.snapshots.message", comment: "")
        case nil: return ""
        }
    }

    static func key(_ action: StartupAction) -> String {
        switch action {
        case .disable: "disable"
        case .enable: "enable"
        case .remove: "remove"
        }
    }
}

extension View {
    func performancePrompts(_ model: PerformanceFlowModel) -> some View { modifier(PerformancePrompts(model: model)) }
}
