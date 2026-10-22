import AppKit

/// Permissões de privacidade de que a Limpeza precisa.
enum PermissionsService {
    /// Acesso Total ao Disco: arquivos protegidos pelo TCC ficam legíveis.
    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes = ["Library/Safari/Bookmarks.plist", "Library/Safari/CloudTabs.db",
                      "Library/Application Support/com.apple.TCC/TCC.db", "Library/Mail"]
        for rel in probes {
            let path = home.appendingPathComponent(rel).path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            return FileManager.default.isReadableFile(atPath: path) && (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
                || (FileHandle(forReadingAtPath: path) != nil)
        }
        return true
    }

    enum Pane { case fullDiskAccess, appManagement }

    /// Abre a lista certa dos Ajustes e, junto, o guia de arrastar o app para ela.
    @MainActor static func openSettings(_ pane: Pane) {
        let anchor = pane == .fullDiskAccess ? "Privacy_AllFiles" : "Privacy_AppBundles"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
        PermissionGuide.show(pane)
    }
}
