import SwiftUI
import CleanYourMacCore

/// As três partes do módulo, na Intro.
enum PerformanceCategory: String, CaseIterable {
    case maintenance, loginItems, backgroundItems

    var symbol: String {
        switch self {
        case .maintenance: "wrench.and.screwdriver.fill"
        case .loginItems: "power"
        case .backgroundItems: "gearshape.2.fill"
        }
    }
}

struct PerformanceIntroView: View {
    var onScan: () -> Void

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .performance, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 18) {
                Text("perf.intro.title").font(Theme.display(46))
                Text("perf.intro.subtitle")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(PerformanceCategory.allCases, id: \.self) { c in
                        HStack(spacing: 14) {
                            CategoryBadge(symbol: c.symbol, module: .performance)
                            Text(LocalizedStringKey.dynamic("perf.category.\(c.rawValue)")).font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                .padding(.top, 10)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.scan", module: .performance, action: onScan)
        }
    }
}

struct PerformanceScanningView: View {
    var model: PerformanceFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .performance, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("perf.scan.title").font(Theme.display(34))
                if let phase = model.scanPhase {
                    Text(LocalizedStringKey.dynamic("perf.scan.phase.\(phase.rawValue)"))
                        .font(.system(size: 15, weight: .semibold))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: phase)
                }
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.stop", module: .performance, action: model.stop)
        }
    }
}

struct PerformanceNothingFoundView: View {
    var model: PerformanceFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .performance, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text("perf.nothing.title").font(Theme.display(40))
                Text("perf.nothing.message").font(.system(size: 17)).foregroundStyle(Theme.secondaryText)
            }
        } action: {
            PrimaryRoundButton(title: "results.restart", module: .performance, action: model.restart)
        }
    }
}
