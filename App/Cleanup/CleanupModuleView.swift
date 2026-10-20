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
            default:
                IntroView(onScan: model.startScan).transition(.stage)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
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
        let scanners = Registry.productionScanners()
        let clean = CleanEngine(policies: Registry.policies(for: scanners, context: context),
                                privileged: AppleScriptPrivilegedRunner(), dryRun: dryRun, log: .standard)
        return CleanupFlowModel(scanEngine: ScanEngine(scanners: scanners), cleanEngine: clean,
                                context: context, groups: Set(scanners.map(\.group)))
    }
}
