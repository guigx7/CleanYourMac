import SwiftUI
import CleanYourMacCore

struct ScanningView: View {
    var model: CleanupFlowModel
    @State private var confirmStop = false

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .cleanup, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("cleanup.scan.title")
                    .font(Theme.display(34))
                if let group = model.currentGroup {
                    Label { Text(group.title) } icon: { Image(systemName: group.symbol) }
                        .font(.system(size: 15, weight: .semibold))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: group)
                }
                Text(model.currentPath.isEmpty ? " " : model.currentPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                VStack(alignment: .leading, spacing: 2) {
                    AnimatedBytes(bytes: model.bytesFound)
                        .font(Theme.display(40, weight: .bold))
                    Text("cleanup.scan.found")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 8)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.stop") { confirmStop = true }
        }
        .alert("scan.stop.confirm.title", isPresented: $confirmStop) {
            Button("scan.stop.continue", role: .cancel) {}
            Button("cleanup.action.stop", role: .destructive) { model.stopScan() }
        } message: {
            Text("scan.stop.confirm.message")
        }
    }
}
