#if DEBUG
import AppKit

/// Em Debug, `CYM_SNAPSHOT=/caminho.png` salva a janela como PNG após `CYM_SNAPSHOT_DELAY` s e encerra o app.
/// Serve para revisar a interface sem permissão de Gravação de Tela.
enum DebugSnapshot {
    static func scheduleIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["CYM_SNAPSHOT"] else { return }
        let delay = Double(env["CYM_SNAPSHOT_DELAY"] ?? "") ?? 2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let view = NSApp.windows.first(where: \.isVisible)?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
#endif
