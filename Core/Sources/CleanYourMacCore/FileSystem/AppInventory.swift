import Foundation

public struct InstalledApp: Sendable, Hashable {
    public let url: URL
    public let bundleID: String
    /// Nome do bundle sem ".app".
    public let name: String
}

/// Lista os apps instalados que os scanners consideram.
public protocol AppInventory: Sendable {
    func apps(_ context: ScanContext) -> [InstalledApp]
}

/// Procura `.app` em `/Applications` e `~/Applications` (com subpastas), sem entrar em bundles.
public struct FolderAppInventory: AppInventory {
    public var folders: [String]

    public init(folders: [String] = ["/Applications", "~/Applications"]) {
        self.folders = folders
    }

    public func apps(_ context: ScanContext) -> [InstalledApp] {
        var out: [InstalledApp] = []
        for template in folders {
            collect(context.resolve(template), depth: 0, into: &out)
        }
        return out
    }

    private func collect(_ dir: URL, depth: Int, into out: inout [InstalledApp]) {
        guard depth < 4,
              let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else { return }
        for child in children.sorted(by: { $0.path < $1.path }) {
            let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values?.isSymbolicLink != true, values?.isDirectory == true else { continue }
            if child.pathExtension == "app" {
                if let app = Self.read(child) { out.append(app) }
            } else {
                collect(child, depth: depth + 1, into: &out)
            }
        }
    }

    static func read(_ url: URL) -> InstalledApp? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = dict["CFBundleIdentifier"] as? String else { return nil }
        return InstalledApp(url: url, bundleID: id, name: url.deletingPathExtension().lastPathComponent)
    }
}
