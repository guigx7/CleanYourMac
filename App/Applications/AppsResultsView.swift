import SwiftUI
import CleanYourMacCore

struct AppsResultsView: View {
    var model: AppsFlowModel
    @State private var confirmRestart = false
    @State private var confirmAct = false
    @State private var appeared = false
    @Environment(\.locale) private var locale

    private var tiles: [AppsTile] { model.report.map(AppsTile.tiles(for:)) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            header.padding(.top, 28).padding(.bottom, 32)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { i, tile in
                        tileView(tile)
                            .frame(height: 230)
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
        .appsPrompts(model, confirmAct: $confirmAct)
        .alert("results.restart.confirm.title", isPresented: $confirmRestart) {
            Button("common.cancel", role: .cancel) {}
            Button("results.restart", role: .destructive) { model.restart() }
        } message: {
            Text("apps.restart.confirm.message")
        }
    }

    private var topBar: some View {
        ZStack {
            Text("module.applications")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack {
                Button { confirmRestart = true } label: {
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
        let count = model.report?.apps.filter { $0.kind == .application }.count ?? 0
        return VStack(spacing: 16) {
            Text(String(format: NSLocalizedString(count == 1 ? "apps.results.header.one" : "apps.results.header.other", comment: ""), count))
                .font(.system(size: 32, weight: .semibold))
            if model.report?.updates.offline == true {
                Label("apps.updates.offline", systemImage: "wifi.slash")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 10) {
                Button("apps.results.manage") { model.openManager(.uninstaller, filter: .all) }
                    .buttonStyle(GlassButtonStyle(size: .large))
                HelperButton()
            }
        }
    }

    private func tileView(_ tile: AppsTile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title(tile))
                            .font(.system(size: 19, weight: .medium))
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                        Text(LocalizedStringKey.dynamic("apps.tile.\(tile.kind.rawValue).description"))
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(3)
                    }
                    Spacer(minLength: 0)
                    CategoryBadge(symbol: tile.symbol, size: 40, module: .applications)
                }
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    Spacer()
                    ForEach(tile.actions, id: \.self) { action in
                        button(action, tile: tile)
                    }
                }
            }
        }
    }

    @ViewBuilder private func button(_ action: AppsTile.Action, tile: AppsTile) -> some View {
        switch action {
        case .review(let section):
            Button("results.action.review") { model.openManager(section, filter: .all) }
                .buttonStyle(GlassButtonStyle(size: .large))
        case .openSoftwareUpdate:
            Button("apps.tile.macOSUpdates.open") { model.perform(.openSoftwareUpdate) }
                .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
        case .removeRecommended:
            Button(tile.kind == .bit32 ? "apps.action.uninstall" : "apps.action.remove") {
                guard let report = model.report else { return }
                model.prepare(AppsTile.recommendedItems(for: tile.kind, in: report))
                confirmAct = true
            }
            .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
        }
    }

    private func title(_ tile: AppsTile) -> String {
        let plural = (tile.kind == .macOSUpdates || tile.kind == .appUpdates) && tile.count == 1 ? ".one" : ""
        let format = NSLocalizedString("apps.tile.\(tile.kind.rawValue).title\(plural)", comment: "")
        switch tile.kind {
        case .leftovers, .installers, .bit32: return String(format: format, SizeFormatter.string(tile.size, locale: locale))
        case .macOSUpdates, .appUpdates: return String(format: format, tile.count)
        case .uninstaller: return format
        }
    }
}


extension AppsFlowModel {
    /// Marca os recomendados dos itens (cartões com ação direta).
    func prepare(_ items: [JunkItem]) {
        selection.clear()
        for item in items { selection.set(AppsSelection.selectable(item).filter(\.isRecommended), on: true) }
    }
}

/// Confirmação geral, pedido para fechar apps e confirmação extra do Redefinir (removal.md, reset.md).
struct AppsPrompts: ViewModifier {
    var model: AppsFlowModel
    @Binding var confirmAct: Bool
    @State private var confirmForce = false
    @Environment(\.locale) private var locale

    private var requirements: Set<CleanupFlowModel.CleanRequirement> { model.requirements(model.selection.selectedLeaves) }

    private var confirmMessage: String {
        let leaves = model.selection.selectedLeaves
        var text = String(format: NSLocalizedString(leaves.contains { $0.removal.isDelete } ? "apps.confirm.message.mixed" : "apps.confirm.message",
                                                    comment: ""), SizeFormatter.string(model.selection.selectedBytes, locale: locale))
        if requirements.contains(.appManagement) { text += "\n\n" + NSLocalizedString("permissions.apps.message", comment: "") }
        if requirements.contains(.admin) { text += "\n\n" + NSLocalizedString("permissions.admin.message", comment: "") }
        return text
    }

    func body(content: Content) -> some View {
        content
            .alert(Text(String(format: NSLocalizedString("apps.confirm.title", comment: ""), model.selection.selectedLeaves.count)),
                   isPresented: $confirmAct) {
                Button("common.cancel", role: .cancel) {}
                if requirements.contains(.appManagement) {
                    Button("permissions.openSettings") { PermissionsService.openSettings(.appManagement) }
                }
                Button("apps.confirm.action") { model.act() }
            } message: {
                Text(confirmMessage)
            }
            .sheet(isPresented: Binding(get: { model.quitPrompt != nil }, set: { if !$0 { model.cancelQuit() } })) {
                QuitAppsSheet(model: model, confirmForce: $confirmForce)
            }
            .alert("apps.reset.confirm.title", isPresented: Binding(get: { model.resetConfirmation != nil },
                                                                     set: { if !$0 && model.resetConfirmation != nil { model.cancelReset() } })) {
                Button("common.cancel", role: .cancel) { model.cancelReset() }
                Button("apps.reset.confirm.action", role: .destructive) { model.confirmReset() }
            } message: {
                let list = (model.resetConfirmation?.leaves ?? []).map {
                    "• \($0.url?.path ?? $0.name) (\(SizeFormatter.string($0.size, locale: locale)))"
                }.joined(separator: "\n")
                Text(NSLocalizedString("apps.reset.confirm.message", comment: "") + "\n\n" + list)
            }
    }
}

extension View {
    func appsPrompts(_ model: AppsFlowModel, confirmAct: Binding<Bool>) -> some View {
        modifier(AppsPrompts(model: model, confirmAct: confirmAct))
    }
}

extension Optional where Wrapped == RemovalAction {
    /// Apaga na hora em vez de mandar para o Lixo (instaladores).
    var isDelete: Bool {
        if case .deleteDiskImage = self { return true }
        return false
    }
}

/// Lista os apps abertos e pede para fechá-los antes de desinstalar.
struct QuitAppsSheet: View {
    var model: AppsFlowModel
    @Binding var confirmForce: Bool
    @State private var quitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("apps.quit.title").font(.title3.weight(.semibold))
            Text("apps.quit.message").foregroundStyle(.secondary)
            ForEach(model.quitPrompt?.apps ?? [], id: \.self) { app in
                Label(app.name, systemImage: "app.fill")
            }
            if model.quitPrompt?.offerForce == true {
                Text("apps.quit.notResponding").foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("common.cancel", role: .cancel) { model.cancelQuit() }
                    .keyboardShortcut(.cancelAction)
                if model.quitPrompt?.offerForce == true {
                    Button("apps.quit.force", role: .destructive) { confirmForce = true }
                }
                Button {
                    quitting = true
                    Task {
                        await model.quitAndContinue(force: false)
                        quitting = false
                    }
                } label: {
                    if quitting { ProgressView().controlSize(.small) } else { Text("apps.quit.action") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(quitting)
            }
        }
        .padding(24)
        .frame(width: 420)
        .alert("apps.quit.force.confirm.title", isPresented: $confirmForce) {
            Button("common.cancel", role: .cancel) {}
            Button("apps.quit.force", role: .destructive) { Task { await model.quitAndContinue(force: true) } }
        } message: {
            Text("apps.quit.force.confirm.message")
        }
    }
}
