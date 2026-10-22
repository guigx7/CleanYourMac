import SwiftUI
import CleanYourMacCore

/// Troca as telas do módulo Desempenho conforme a fase do fluxo.
struct PerformanceModuleView: View {
    @State var model: PerformanceFlowModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro:
                PerformanceIntroView(onScan: model.start).transition(.stage)
            case .scanning:
                PerformanceScanningView(model: model).transition(.stage)
            case .results:
                PerformanceResultsView(model: model).transition(.stage)
            case .nothingFound:
                PerformanceNothingFoundView(model: model).transition(.stage)
            case .acting:
                PerformanceActingView(model: model).transition(.stage)
            case .done(let outcome):
                PerformanceDoneView(model: model, outcome: outcome).transition(.stage)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
        #if DEBUG
        .task { await PerformanceDebugAutomation.run(model) }
        #endif
    }
}

#if DEBUG
/// `CYM_PERF_AUTO=scan|results|maintenance|loginItems|backgroundItems|snapshots` leva o fluxo até a tela pedida (capturas).
@MainActor
enum PerformanceDebugAutomation {
    static func run(_ model: PerformanceFlowModel) async {
        guard let target = ProcessInfo.processInfo.environment["CYM_PERF_AUTO"] else { return }
        model.start()
        guard target != "scan" else { return }
        while model.phase == .scanning { try? await Task.sleep(for: .milliseconds(50)) }
        if let section = PerformanceFlowModel.Section(rawValue: target) { model.openManager(section) }
    }
}
#endif
