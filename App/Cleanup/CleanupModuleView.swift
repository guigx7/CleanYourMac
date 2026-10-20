import SwiftUI
import CleanYourMacCore

/// Troca as telas do módulo conforme a fase do fluxo.
struct CleanupModuleView: View {
    @State var model: CleanupFlowModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro:
                IntroView(onScan: model.startScan).transition(.stage)
            case .scanning:
                ScanningView(model: model).transition(.stage)
            case .results, .review:
                ResultsView(model: model).transition(.stage)
            case .nothingFound:
                NothingFoundView(model: model).transition(.stage)
            case .cleaning:
                CleaningView(model: model).transition(.stage)
            case .done(let report):
                DoneView(model: model, report: report).transition(.stage)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
        #if DEBUG
        .task { await DebugAutomation.run(model) }
        #endif
    }
}

extension AnyTransition {
    static var stage: AnyTransition { .opacity.combined(with: .scale(scale: 0.98)) }
}

/// Monta o fluxo com os scanners e políticas de produção.
/// Em Debug: `CYM_FIXTURE_ROOT` troca o disco real por uma pasta; `CYM_DRY_RUN=0` desliga a simulação.
@MainActor
enum CleanupEnvironment {
    static func makeModel() -> CleanupFlowModel {
        let env = ProcessInfo.processInfo.environment
        var context = ScanContext.current()
        if let root = env["CYM_FIXTURE_ROOT"] {
            let r = URL(fileURLWithPath: root)
            context = ScanContext(root: r, home: r.appendingPathComponent("Users/\(context.userName)"),
                                  userName: context.userName, preferredLanguages: context.preferredLanguages, now: Date())
        }
        #if DEBUG
        let dryRun = env["CYM_DRY_RUN"] != "0"
        #else
        let dryRun = false
        #endif
        var scanners = Registry.productionScanners()
        #if DEBUG
        if env["CYM_DEMO"] == "1" { scanners = DemoData.scanners }
        #endif
        let policyScanners = scanners
        let policyContext = context
        let clean = CleanEngine(policyProvider: { Registry.policies(for: policyScanners, context: policyContext) },
                                privileged: AppleScriptPrivilegedRunner(), dryRun: dryRun, log: .standard)
        return CleanupFlowModel(scanEngine: ScanEngine(scanners: scanners), cleanEngine: clean,
                                context: context, groups: Set(scanners.map(\.group)))
    }
}

#if DEBUG
/// `CYM_AUTO=scan|results|review` leva o fluxo até a tela pedida (para capturas).
@MainActor
enum DebugAutomation {
    static func run(_ model: CleanupFlowModel) async {
        guard let target = ProcessInfo.processInfo.environment["CYM_AUTO"] else { return }
        model.startScan()
        guard target != "scan" else { return }
        while model.phase == .scanning { try? await Task.sleep(for: .milliseconds(50)) }
        if target == "review" { model.openReview() }
        if target == "clean" || target == "done" {
            model.clean(tile: .systemJunk)
        }
    }
}
#endif
