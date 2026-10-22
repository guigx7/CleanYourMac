import SwiftUI
import AppKit
import CleanYourMacCore

/// Troca as telas da Lupa de Espaço conforme a fase do fluxo.
struct SpaceLensModuleView: View {
    @State var model: SpaceLensFlowModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro:
                SpaceLensIntroView(model: model).transition(.stage)
            case .scanning:
                SpaceLensScanningView(model: model).transition(.stage)
            case .results:
                SpaceLensResultsView(model: model).transition(.stage)
            case .reviewing:
                SpaceLensReviewView(model: model).transition(.stage)
            case .removing:
                SpaceLensRemovingView().transition(.stage)
            case .done(let outcome):
                SpaceLensDoneView(model: model, outcome: outcome).transition(.stage)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
        #if DEBUG
        .task { await SpaceLensDebugAutomation.run(model) }
        #endif
    }
}

#if DEBUG
/// `CYM_LENS_AUTO=scan|results|<caminho>` leva o fluxo até a tela pedida (capturas). Com um caminho, analisa a pasta.
@MainActor
enum SpaceLensDebugAutomation {
    static func run(_ model: SpaceLensFlowModel) async {
        guard let target = ProcessInfo.processInfo.environment["CYM_LENS_AUTO"] else { return }
        if target.hasPrefix("/") { model.target = .folder(URL(fileURLWithPath: target)) }
        model.start()
        guard target != "scan" else { return }
        while model.phase == .scanning { try? await Task.sleep(for: .milliseconds(50)) }
        if let path = ProcessInfo.processInfo.environment["CYM_LENS_OPEN"], let root = model.report?.root {
            var node = root
            for part in path.split(separator: "/") {
                guard let next = node.child(String(part)) else { break }
                model.open(next)
                node = next
            }
        }
    }
}
#endif

// MARK: - Intro

struct SpaceLensIntroView: View {
    var model: SpaceLensFlowModel

    private var targetName: String {
        switch model.target {
        case .disk: SystemVolumeInfo().usage(of: URL(fileURLWithPath: "/")).name
        case .folder(let url): FileManager.default.displayName(atPath: url.path)
        }
    }

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .spaceLens, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 18) {
                Text("lens.intro.title").font(Theme.display(46))
                Text("lens.intro.subtitle")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach([("lens.category.map", "circle.hexagongrid.fill"), ("lens.category.hidden", "eye.fill"),
                             ("lens.category.folders", "folder.fill")], id: \.0) { key, symbol in
                        HStack(spacing: 14) {
                            CategoryBadge(symbol: symbol, module: .spaceLens)
                            Text(LocalizedStringKey(key)).font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                .padding(.top, 10)
                Menu {
                    Button {
                        model.target = .disk
                    } label: {
                        Label(SystemVolumeInfo().usage(of: URL(fileURLWithPath: "/")).name, systemImage: "internaldrive")
                    }
                    Button("lens.target.choose") { chooseFolder() }
                } label: {
                    Label(targetName, systemImage: model.target == .disk ? "internaldrive" : "folder")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.top, 8)
                .accessibilityLabel(Text("lens.target.label"))
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.scan", module: .spaceLens, action: model.start)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("lens.target.choosePrompt", comment: "")
        if panel.runModal() == .OK, let url = panel.url { model.target = .folder(url) }
    }
}

struct SpaceLensScanningView: View {
    var model: SpaceLensFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .spaceLens, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("lens.scan.title").font(Theme.display(34))
                Text(String(format: NSLocalizedString("lens.scan.items", comment: ""), model.scanned.formatted()))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.scanned)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.stop", module: .spaceLens, action: model.stop)
        }
    }
}

// MARK: - Revisão, remoção e conclusão

struct SpaceLensReviewView: View {
    var model: SpaceLensFlowModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { model.cancelReview() } label: { Label("review.back", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            Text("lens.review.title").font(Theme.display(30))
            Text("lens.review.subtitle").foregroundStyle(Theme.secondaryText)
            GlassCard {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.selection) { node in
                            HStack(spacing: 12) {
                                SpaceNodeIcon(node: node).frame(width: 26, height: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(node.name).lineLimit(1).truncationMode(.middle)
                                    Text(node.path).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(SizeFormatter.string(node.size, locale: locale)).monospacedDigit()
                                Button { model.deselect(node) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.secondaryText)
                                    .accessibilityLabel(Text(String(format: NSLocalizedString("lens.review.unselect", comment: ""), node.name)))
                            }
                            .padding(.vertical, 8)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
            HStack {
                Text(String(format: NSLocalizedString("lens.review.total", comment: ""), model.selection.count,
                            SizeFormatter.string(model.selectionSize, locale: locale)))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(role: .destructive) { model.confirmRemoval() } label: {
                    Label("lens.action.trash", systemImage: "trash").padding(.horizontal, 8)
                }
                .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
            }
            Text("lens.review.trashNote").font(.callout).foregroundStyle(Theme.secondaryText)
            if model.selectionTouchesCloud {
                Label("lens.review.cloud", systemImage: "icloud.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xFFD9A0))
            }
        }
        .padding(32)
    }
}

struct SpaceLensRemovingView: View {
    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .spaceLens, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("lens.removing.title").font(Theme.display(34))
                ProgressView().controlSize(.small).tint(.white)
            }
        } action: {
            EmptyView()
        }
    }
}

struct SpaceLensDoneView: View {
    var model: SpaceLensFlowModel
    var outcome: SpaceLensFlowModel.Outcome
    @Environment(\.locale) private var locale

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .spaceLens, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text(LocalizedStringKey(outcome.failed.isEmpty ? "lens.done.title" : "lens.done.partial")).font(Theme.display(38))
                Text(String(format: NSLocalizedString("lens.done.message", comment: ""), outcome.removed,
                            SizeFormatter.string(outcome.freed, locale: locale)))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                if model.dryRun {
                    Label("perf.done.dryRun", systemImage: "info.circle").font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                }
                if !outcome.failed.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(outcome.failed.sorted { $0.key < $1.key }, id: \.key) { name, reason in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(FailureText.describe(reason)).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
                HStack(spacing: 10) {
                    Button("lens.done.backToResults") { model.backToResults() }
                        .buttonStyle(GlassButtonStyle(size: .large))
                    Button("apps.done.openTrash") {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                    }
                    .buttonStyle(GlassButtonStyle(size: .large))
                    Button("apps.done.log") { NSWorkspace.shared.open(CleanupLog.standard.directory) }
                        .buttonStyle(GlassButtonStyle(size: .large))
                }
                .padding(.top, 6)
            }
        } action: {
            PrimaryRoundButton(title: "results.restart", module: .spaceLens, action: model.restart)
        }
    }
}

/// Ícone do Finder para o item (pasta, app, documento).
struct SpaceNodeIcon: View {
    var node: SpaceNode

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: node.path)).resizable().interpolation(.high)
    }
}
