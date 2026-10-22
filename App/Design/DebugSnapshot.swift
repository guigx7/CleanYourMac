#if DEBUG
import AppKit
import ServiceManagement
import CleanYourMacCore

/// Em Debug, `CYM_SNAPSHOT=/caminho.png` salva a janela como PNG após `CYM_SNAPSHOT_DELAY` s e encerra o app.
/// Serve para revisar a interface sem permissão de Gravação de Tela.
enum DebugSnapshot {
    static func scheduleIfRequested() {
        let env = ProcessInfo.processInfo.environment
        // CYM_HELPER_STATUS=1: imprime o status do helper (SMAppService) e encerra.
        if env["CYM_HELPER_STATUS"] == "1" {
            let service = SMAppService.daemon(plistName: HelperConstants.plistName)
            print("helper status:", service.status.rawValue)
            if env["CYM_HELPER_REGISTER"] == "1" {
                do { try service.register(); print("register ok") } catch { print("register error:", error) }
                print("helper status:", service.status.rawValue)
            }
            exit(0)
        }
        // CYM_GUIDE=fda|apps: abre o guia de permissão (para capturar com CYM_SNAPSHOT_GUIDE=1).
        if let guide = env["CYM_GUIDE"] {
            DispatchQueue.main.async { PermissionGuide.show(guide == "apps" ? .appManagement : .fullDiskAccess) }
        }
        guard let path = env["CYM_SNAPSHOT"] else { return }
        let delay = Double(env["CYM_SNAPSHOT_DELAY"] ?? "") ?? 2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let windows = NSApp.windows.filter(\.isVisible)
            let target = env["CYM_SNAPSHOT_GUIDE"] == "1" ? windows.first { $0 is NSPanel } : windows.first
            guard let view = target?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
#endif
