import SwiftUI
import AppKit

/// Janelinha flutuante que acompanha os Ajustes: "arraste o CleanYourMac para a lista e ligue a chave".
/// O macOS não põe o app sozinho nas listas de Acesso Total ao Disco e Gerenciamento de Apps.
@MainActor
enum PermissionGuide {
    private static var panel: NSPanel?
    private static var timer: Timer?

    static func show(_ pane: PermissionsService.Pane) {
        close()
        let hosting = NSHostingView(rootView: PermissionGuideView(pane: pane, onClose: close))
        hosting.frame.size = hosting.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = NSLocalizedString("guide.title", comment: "")
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = hosting
        // Canto inferior direito da tela, fora do caminho da janela dos Ajustes.
        if let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.maxX - p.frame.width - 24, y: screen.minY + 24))
        }
        p.orderFrontRegardless()
        panel = p
        // Acesso Total ao Disco dá para conferir: fecha sozinho quando for concedido.
        if pane == .fullDiskAccess {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in if PermissionsService.hasFullDiskAccess() { close() } }
            }
        }
    }

    static func close() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
    }

    static var isShown: Bool { panel != nil }
}

struct PermissionGuideView: View {
    var pane: PermissionsService.Pane
    var onClose: () -> Void

    private var appURL: URL { Bundle.main.bundleURL }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .frame(width: 64, height: 64)
                .onDrag { NSItemProvider(contentsOf: appURL) ?? NSItemProvider() }
                .help(Text("guide.drag.help"))
                .accessibilityLabel(Text("guide.drag.help"))
            VStack(alignment: .leading, spacing: 8) {
                Text(pane == .fullDiskAccess ? "guide.fda.title" : "guide.apps.title").font(.headline)
                Text("guide.step.drag").fixedSize(horizontal: false, vertical: true)
                Text("guide.step.toggle").fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("guide.reveal") { NSWorkspace.shared.activateFileViewerSelecting([appURL]) }
                    Spacer()
                    Button("guide.done", action: onClose).keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
