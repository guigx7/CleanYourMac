import SwiftUI

struct RootView: View {
    @State private var module: AppModule = .cleanup

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $module)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.gradient(for: module).ignoresSafeArea())
        .foregroundStyle(.white)
        .frame(minWidth: 1040, minHeight: 680)
    }

    @ViewBuilder private var content: some View {
        switch module {
        case .cleanup:
            ModuleArtwork(module: .cleanup, isAnimating: false)
        default:
            EmptyView()
        }
    }
}
