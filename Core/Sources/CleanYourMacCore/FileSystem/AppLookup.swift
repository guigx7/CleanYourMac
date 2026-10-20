import AppKit

/// Resolve um bundle id para o app instalado (nome exibido e caminho).
public protocol AppLookup: Sendable {
    func application(bundleID: String) -> (name: String, url: URL)?
}

public struct WorkspaceAppLookup: AppLookup {
    public init() {}

    public func application(bundleID: String) -> (name: String, url: URL)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return ((name as NSString).deletingPathExtension, url)
    }
}
