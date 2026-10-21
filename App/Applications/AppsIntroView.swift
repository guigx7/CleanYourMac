import SwiftUI
import CleanYourMacCore

/// As três partes do módulo, na Intro.
enum AppsCategory: CaseIterable {
    case uninstaller, updater, leftovers

    var title: LocalizedStringKey {
        switch self {
        case .uninstaller: "apps.category.uninstaller"
        case .updater: "apps.category.updater"
        case .leftovers: "apps.category.leftovers"
        }
    }

    var symbol: String {
        switch self {
        case .uninstaller: "xmark.bin.fill"
        case .updater: "arrow.triangle.2.circlepath"
        case .leftovers: "puzzlepiece.extension.fill"
        }
    }
}

struct AppsIntroView: View {
    var onScan: () -> Void

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .applications, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 18) {
                Text("apps.intro.title").font(Theme.display(46))
                Text("apps.intro.subtitle")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(AppsCategory.allCases, id: \.self) { c in
                        HStack(spacing: 14) {
                            CategoryBadge(symbol: c.symbol, module: .applications)
                            Text(c.title).font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                .padding(.top, 10)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.scan", module: .applications, action: onScan)
        }
    }
}

struct AppsScanningView: View {
    var model: AppsFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .applications, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("apps.scan.title").font(Theme.display(34))
                if let phase = model.scanPhase {
                    Text(LocalizedStringKey.dynamic("apps.scan.phase.\(phase.rawValue)"))
                        .font(.system(size: 15, weight: .semibold))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: phase)
                }
                Text(model.currentPath.isEmpty ? " " : model.currentPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.stop", module: .applications, action: model.stop)
        }
    }
}

struct AppsNothingFoundView: View {
    var model: AppsFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .applications, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text("apps.nothing.title").font(Theme.display(40))
                Text("apps.nothing.message").font(.system(size: 17)).foregroundStyle(Theme.secondaryText)
            }
        } action: {
            PrimaryRoundButton(title: "results.restart", module: .applications, action: model.restart)
        }
    }
}
