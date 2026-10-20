import Foundation
@testable import CleanYourMacCore

/// Árvore de diretórios real e descartável para testes. Nunca toca no disco do usuário.
final class FixtureTree {
    let root: URL
    private let fm = FileManager.default

    init() {
        let raw = fm.temporaryDirectory.appendingPathComponent("cym-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: raw, withIntermediateDirectories: true)
        // Caminho real (/private/var/...), para comparações estáveis.
        root = URL(fileURLWithPath: PathPolicy.realPath(raw.path), isDirectory: true)
    }

    deinit {
        // Devolve permissões antes de apagar (testes usam chmod 000).
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in e { chmod(url.path, 0o755) }
        }
        try? fm.removeItem(at: root)
    }

    func url(_ relPath: String) -> URL { root.appendingPathComponent(relPath) }

    @discardableResult
    func dir(_ relPath: String) -> URL {
        let u = url(relPath)
        try! fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    func file(_ relPath: String, bytes: Int, modified: Date? = nil) -> URL {
        let u = url(relPath)
        dir((relPath as NSString).deletingLastPathComponent)
        try! Data(repeating: 0x61, count: bytes).write(to: u)
        if let modified {
            try! fm.setAttributes([.modificationDate: modified], ofItemAtPath: u.path)
        }
        return u
    }

    @discardableResult
    func symlink(_ relPath: String, to destination: URL) -> URL {
        let u = url(relPath)
        dir((relPath as NSString).deletingLastPathComponent)
        try! fm.createSymbolicLink(at: u, withDestinationURL: destination)
        return u
    }

    @discardableResult
    func hardlink(_ relPath: String, to existing: URL) -> URL {
        let u = url(relPath)
        dir((relPath as NSString).deletingLastPathComponent)
        try! fm.linkItem(at: existing, to: u)
        return u
    }

    func chmod(_ relPath: String, _ mode: mode_t) {
        Darwin.chmod(url(relPath).path, mode)
    }

    func context(user: String = "tester", languages: [String] = ["pt-BR", "en"]) -> ScanContext {
        dir("Users/\(user)")
        dir("var/folders/zz/C")
        return ScanContext(root: root, home: url("Users/\(user)"), userName: user,
                           preferredLanguages: languages, now: Date(),
                           darwinUserCacheDir: url("var/folders/zz/C"))
    }

    /// Pasta de app falsa com Info.plist (bundle id) e, opcionalmente, o framework do Electron.
    @discardableResult
    func app(_ relPath: String, bundleID: String, electron: Bool = false) -> URL {
        let u = dir(relPath)
        dir("\(relPath)/Contents/MacOS")
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "app",
                                    "CFBundleName": (u.lastPathComponent as NSString).deletingPathExtension]
        try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: u.appendingPathComponent("Contents/Info.plist"))
        if electron { dir("\(relPath)/Contents/Frameworks/Electron Framework.framework") }
        return u
    }

    /// Tamanho alocado de um arquivo, como o FileSizer deve medir.
    static func allocated(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
    }
}
