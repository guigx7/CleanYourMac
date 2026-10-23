import SwiftUI
import AppKit
import CleanYourMacCore

/// Troca as telas do módulo Acúmulos conforme a fase do fluxo.
struct ClutterModuleView: View {
    @State var model: ClutterFlowModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro:
                ClutterIntroView(model: model).transition(.stage)
            case .scanning:
                ClutterScanningView(model: model).transition(.stage)
            case .results:
                ClutterResultsView(model: model).transition(.stage)
            case .nothingFound:
                ClutterNothingFoundView(model: model).transition(.stage)
            case .removing:
                ClutterRemovingView().transition(.stage)
            case .done(let outcome):
                ClutterDoneView(model: model, outcome: outcome).transition(.stage)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
        #if DEBUG
        .task { await ClutterDebugAutomation.run(model) }
        #endif
    }
}

/// As quatro partes do módulo, na Intro.
enum ClutterCategory: String, CaseIterable {
    case largeOld, duplicates, similar, downloads

    var symbol: String {
        switch self {
        case .largeOld: "archivebox.fill"
        case .duplicates: "doc.on.doc.fill"
        case .similar: "photo.on.rectangle.angled"
        case .downloads: "arrow.down.circle.fill"
        }
    }
}

struct ClutterIntroView: View {
    var model: ClutterFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .clutter, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 18) {
                Text("clutter.intro.title").font(Theme.display(46))
                Text("clutter.intro.subtitle")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ClutterCategory.allCases, id: \.self) { c in
                        HStack(spacing: 14) {
                            CategoryBadge(symbol: c.symbol, module: .clutter)
                            Text(LocalizedStringKey.dynamic("clutter.category.\(c.rawValue)")).font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                .padding(.top, 10)
                targetPicker.padding(.top, 8)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.scan", module: .clutter, action: model.start)
        }
    }

    /// Pasta pessoal (com Downloads por app e a fototeca) ou uma pasta escolhida.
    private var targetPicker: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill").foregroundStyle(Theme.secondaryText)
            Menu {
                Button("clutter.target.home") { model.choose(folder: nil) }
                Button("clutter.target.choose") { chooseFolder() }
            } label: {
                Text(verbatim: targetName)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.system(size: 14, weight: .medium))
    }

    private var targetName: String {
        switch model.target {
        case .home: NSLocalizedString("clutter.target.home", comment: "")
        case .folder(let url): FileManager.default.displayName(atPath: url.path)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url { model.choose(folder: url) }
    }
}

struct ClutterScanningView: View {
    var model: ClutterFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .clutter, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("clutter.scan.title").font(Theme.display(34))
                Text(LocalizedStringKey.dynamic("clutter.scan.step.\(model.scanStep ?? "files")"))
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: model.scanStep)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.stop", module: .clutter, action: model.stop)
        }
    }
}

struct ClutterNothingFoundView: View {
    var model: ClutterFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .clutter, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text("clutter.nothing.title").font(Theme.display(40))
                Text("clutter.nothing.message").font(.system(size: 17)).foregroundStyle(Theme.secondaryText)
            }
        } action: {
            PrimaryRoundButton(title: "results.restart", module: .clutter, action: model.restart)
        }
    }
}

struct ClutterRemovingView: View {
    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .clutter, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("clutter.removing.title").font(Theme.display(34))
                ProgressView().controlSize(.small).tint(.white)
            }
        } action: {
            EmptyView()
        }
    }
}

/// Fim da remoção: quanto saiu, o que falhou, Revisar Mais Itens.
struct ClutterDoneView: View {
    var model: ClutterFlowModel
    var outcome: ClutterFlowModel.Outcome
    @Environment(\.locale) private var locale

    private var failed: Bool { !outcome.failed.isEmpty }

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .clutter, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text(LocalizedStringKey(failed ? "clutter.done.partial.title" : "clutter.done.title")).font(Theme.display(38))
                Text(summary)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if failed {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(outcome.failed.sorted { $0.key < $1.key }, id: \.key) { name, reason in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: name.hasPrefix("/") ? (name as NSString).abbreviatingWithTildeInPath
                                         : NSLocalizedString("clutter.similar.photo", comment: ""))
                                        .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                    Text(FailureText.describe(reason)).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                HStack(spacing: 10) {
                    if !(model.report?.isEmpty ?? true) {
                        Button("clutter.done.reviewMore") { model.reviewMore() }
                            .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
                    }
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
            PrimaryRoundButton(title: "results.restart", module: .clutter, action: model.restart)
        }
    }

    private var summary: String {
        let size = SizeFormatter.string(outcome.freed, locale: locale)
        let key = model.dryRun ? "clutter.done.dryRun" : (outcome.removed == 1 ? "clutter.done.summary.one" : "clutter.done.summary.other")
        return String(format: NSLocalizedString(key, comment: ""), outcome.removed, size)
    }
}

#if DEBUG
/// `CYM_CLUTTER_AUTO=scan|results|largeOld|duplicates|similar|downloads|done` leva o fluxo até a tela pedida (capturas);
/// `CYM_CLUTTER_FOLDER=<pasta>` analisa essa pasta em vez da pessoal.
@MainActor
enum ClutterDebugAutomation {
    static func run(_ model: ClutterFlowModel) async {
        let env = ProcessInfo.processInfo.environment
        if let folder = env["CYM_CLUTTER_FOLDER"] { model.choose(folder: URL(fileURLWithPath: folder)) }
        guard let target = env["CYM_CLUTTER_AUTO"] else { return }
        model.start()
        guard target != "scan" else { return }
        while model.phase == .scanning { try? await Task.sleep(for: .milliseconds(50)) }
        if let section = ClutterFlowModel.Section(rawValue: target) {
            model.openManager(section, autoselect: env["CYM_CLUTTER_AUTOSELECT"] == "1")
        }
        if target == "done" {
            model.openManager(.duplicates, autoselect: true)
            model.requestRemoval()
            model.confirmRemoval()
        }
    }
}
#endif
