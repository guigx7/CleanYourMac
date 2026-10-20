import Foundation

/// Como um item é removido pelo CleanEngine.
public enum RemovalAction: Hashable, Sendable {
    /// Apagar definitivamente.
    case delete(URL)
    case moveToTrash(URL)
    /// Esvaziar a pasta, mantendo a pasta em si.
    case deleteContents(of: URL)
    case thinBinary(executable: URL, keepArch: String, bundle: URL)
    case removeLocalizations(bundle: URL, lprojs: [URL])
    /// Plist de um LaunchAgent/LoginItem quebrado.
    case removeLoginItem(URL)
    case deleteDocumentVersions(volume: URL, fileID: String)
}
