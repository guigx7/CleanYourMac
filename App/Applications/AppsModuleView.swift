import SwiftUI
import CleanYourMacCore

/// Troca as telas do módulo Aplicativos conforme a fase do fluxo.
struct AppsModuleView: View {
    @State var model: AppsFlowModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro:
                AppsIntroView(onScan: model.start).transition(.stage)
            case .scanning:
                AppsScanningView(model: model).transition(.stage)
            case .results:
                AppsResultsView(model: model).transition(.stage)
            case .nothingFound:
                AppsNothingFoundView(model: model).transition(.stage)
            case .acting:
                AppsActingView(model: model).transition(.stage)
            case .done(let report):
                AppsDoneView(model: model, report: report).transition(.stage)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
        #if DEBUG
        .task { await AppsDebugAutomation.run(model) }
        #endif
    }
}

#if DEBUG
/// `CYM_APPS_AUTO=scan|results|uninstaller|updater|leftovers|expanded` leva o fluxo até a tela pedida (capturas).
@MainActor
enum AppsDebugAutomation {
    static func run(_ model: AppsFlowModel) async {
        guard let target = ProcessInfo.processInfo.environment["CYM_APPS_AUTO"] else { return }
        model.start()
        guard target != "scan" else { return }
        while model.phase == .scanning { try? await Task.sleep(for: .milliseconds(50)) }
        switch target {
        case "uninstaller", "expanded": model.openManager(.uninstaller, filter: .all)
        case "updater": model.openManager(.updater)
        case "leftovers": model.openManager(.leftovers)
        default: break
        }
        if target == "expanded", let item = model.report?.uninstaller.first(where: { $0.name == "Claude.app" }) ?? model.report?.uninstaller.first {
            model.selection.toggle(item)
            model.debugExpanded = [item.id] + item.children.map(\.id)
        }
    }
}
#endif
