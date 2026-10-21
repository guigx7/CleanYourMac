import SwiftUI

struct RootView: View {
    @State private var module: AppModule = RootView.initialModule

    /// Debug: `CYM_MODULE=applications` abre outro módulo (capturas).
    private static var initialModule: AppModule {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["CYM_MODULE"], let m = AppModule(rawValue: raw) { return m }
        #endif
        return .cleanup
    }
    @State private var cleanup = CleanupEnvironment.makeModel()
    @State private var apps = AppsEnvironment.makeModel()

    /// Telas claras em tela cheia: o Gerenciador de Limpeza e o de Aplicativos.
    private var fullScreen: Bool {
        (module == .cleanup && cleanup.phase == .review) || (module == .applications && apps.managerOpen)
    }

    var body: some View {
        ZStack {
            if module == .cleanup && cleanup.phase == .review {
                ReviewView(model: cleanup)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if module == .applications && apps.managerOpen {
                AppsManagerView(model: apps)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                main.transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: fullScreen)
        .task { await HelperManager.shared.checkVersion() }
        .frame(minWidth: 1040, minHeight: 680)
    }

    private var main: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $module, compact: atIntro == false)
                .animation(.smooth(duration: 0.35), value: atIntro)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    FullDiskAccessBanner().padding(.top, 12).padding(.trailing, 20)
                }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.gradient(for: module).ignoresSafeArea())
        .foregroundStyle(.white)
    }

    private var atIntro: Bool {
        module == .applications ? apps.phase == .intro : cleanup.phase == .intro
    }

    @ViewBuilder private var content: some View {
        switch module {
        case .cleanup:
            CleanupModuleView(model: cleanup)
        case .applications:
            AppsModuleView(model: apps)
        default:
            EmptyView()
        }
    }
}
