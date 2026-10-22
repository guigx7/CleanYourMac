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
    }
}
