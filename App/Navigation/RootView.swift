import SwiftUI

struct RootView: View {
    @State private var module: AppModule = .cleanup
    @State private var cleanup = CleanupEnvironment.makeModel()

    var body: some View {
        ZStack {
            if cleanup.phase == .review {
                ReviewView(model: cleanup)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                main.transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: cleanup.phase == .review)
        .frame(minWidth: 1040, minHeight: 680)
    }

    private var main: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $module, compact: cleanup.phase != .intro)
                .animation(.smooth(duration: 0.35), value: cleanup.phase == .intro)
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

    @ViewBuilder private var content: some View {
        switch module {
        case .cleanup:
            CleanupModuleView(model: cleanup)
        default:
            EmptyView()
        }
    }
}
