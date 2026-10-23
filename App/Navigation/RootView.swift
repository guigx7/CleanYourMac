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
    @State private var performance = PerformanceEnvironment.makeModel()
    @State private var lens = SpaceLensEnvironment.makeModel()
    @State private var clutter = ClutterEnvironment.makeModel()
    @State private var agents = AgentsEnvironment.makeModel()
    @State private var page: SidebarPage? = RootView.initialPage

    /// Debug: `CYM_PAGE=settings|about` abre a aba direto (capturas).
    private static var initialPage: SidebarPage? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["CYM_PAGE"] { return SidebarPage(rawValue: raw) }
        #endif
        return nil
    }

    /// Telas claras em tela cheia: os Gerenciadores de Limpeza, Aplicativos, Desempenho, Acúmulos e Agentes de IA.
    private var fullScreen: Bool {
        (module == .cleanup && cleanup.phase == .review) || (module == .applications && apps.managerOpen)
            || (module == .performance && performance.managerOpen) || (module == .clutter && clutter.managerOpen)
            || (module == .agents && agents.managerOpen)
    }

    var body: some View {
        ZStack {
            if module == .cleanup && cleanup.phase == .review {
                ReviewView(model: cleanup)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if module == .applications && apps.managerOpen {
                AppsManagerView(model: apps)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if module == .performance && performance.managerOpen {
                PerformanceManagerView(model: performance)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if module == .clutter && clutter.managerOpen {
                ClutterManagerView(model: clutter)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if module == .agents && agents.managerOpen {
                AgentsManagerView(model: agents)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                main.transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: fullScreen)
        .task { await HelperManager.shared.checkVersion() }
        .onAppear {
            // "Abrir no Desinstalador" a partir de um item de início.
            performance.onOpenUninstaller = { _ in
                performance.closeManager()
                module = .applications
                apps.openManager(.uninstaller, filter: .all)
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
    }

    private var main: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $module, page: $page, compact: page == nil && atIntro == false)
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
        switch module {
        case .applications: apps.phase == .intro
        case .performance: performance.phase == .intro
        case .clutter: clutter.phase == .intro
        case .agents: agents.phase == .intro
        case .spaceLens: lens.phase == .intro
        default: cleanup.phase == .intro
        }
    }

    @ViewBuilder private var content: some View {
        if let page {
            switch page {
            case .settings: SettingsView()
            case .about: AboutView()
            }
        } else {
            moduleContent
        }
    }

    @ViewBuilder private var moduleContent: some View {
        switch module {
        case .cleanup:
            CleanupModuleView(model: cleanup)
        case .applications:
            AppsModuleView(model: apps)
        case .performance:
            PerformanceModuleView(model: performance)
        case .clutter:
            ClutterModuleView(model: clutter)
        case .agents:
            AgentsModuleView(model: agents)
        case .spaceLens:
            SpaceLensModuleView(model: lens)
        }
    }
}
