import Foundation
@preconcurrency import CoreServices

/// Imagens de disco que o Spotlight conhece dentro dos escopos (docs/re/specs/apps/installers.md §Inclusão).
public protocol DiskImageQuery: Sendable {
    func diskImages(in scopes: [URL]) -> [URL]
}

/// `kMDItemContentTypeTree == "com.apple.disk-image-udif"`, síncrono, só nos escopos pedidos.
public struct SpotlightDiskImageQuery: DiskImageQuery {
    public init() {}

    public func diskImages(in scopes: [URL]) -> [URL] {
        let predicate = "kMDItemContentTypeTree == \"com.apple.disk-image-udif\"" as CFString
        guard let query = MDQueryCreate(kCFAllocatorDefault, predicate, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, scopes.map(\.path) as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var out: [URL] = []
        for i in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String { out.append(URL(fileURLWithPath: path)) }
        }
        return out
    }

    /// `kMDItemPhysicalSize` (tamanho alocado segundo o Spotlight).
    static func physicalSize(_ url: URL) -> Int64? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return (MDItemCopyAttribute(item, "kMDItemPhysicalSize" as CFString) as? NSNumber)?.int64Value
    }
}

/// Caminhos das imagens montadas agora (`hdiutil info -plist`, campo `image-path`).
public func systemMountedImages() -> Set<String> {
    let r = SystemCommandRunner().run("/usr/bin/hdiutil", ["info", "-plist"])
    guard r.status == 0, let data = r.output.data(using: .utf8),
          let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let images = dict["images"] as? [[String: Any]] else { return [] }
    return Set(images.compactMap { ($0["image-path"] as? String).map(PathPolicy.realPath) })
}

/// Instaladores (DMG) na pasta do usuário e em /Applications. Nada vem marcado; a remoção apaga na hora.
public struct InstallersScanner: ScopedScanner {
    public let group = GroupID.appInstallers
    private let query: any DiskImageQuery
    private let mountedImages: @Sendable () -> Set<String>
    private let sizer = FileSizer()

    public init(query: any DiskImageQuery = SpotlightDiskImageQuery(),
                mountedImages: @escaping @Sendable () -> Set<String> = systemMountedImages) {
        self.query = query
        self.mountedImages = mountedImages
    }

    func scopes(_ context: ScanContext) -> [URL] {
        [context.home, context.resolve("/Applications")]
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(roots: scopes(context))
    }

    /// Pastas das contas do Dropbox (`~/.dropbox/info.json`).
    static func dropboxFolders(_ context: ScanContext) -> [String] {
        guard let data = try? Data(contentsOf: context.home.appendingPathComponent(".dropbox/info.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return json.values.compactMap { ($0 as? [String: Any])?["path"] as? String }.map(PathPolicy.realPath)
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        let roots = scopes(context)
        report(ScanProgress(group: group, currentPath: context.home.path, bytesFound: 0))
        let dropbox = Self.dropboxFolders(context)
        let mounted = mountedImages()
        var seen = Set<String>()
        var out: [JunkItem] = []
        for url in query.diskImages(in: roots) {
            try Task.checkCancellation()
            let real = PathPolicy.realPath(url.path)
            guard seen.insert(real).inserted,
                  roots.contains(where: { real.hasPrefix(PathPolicy.realPath($0.path) + "/") }),
                  !dropbox.contains(where: { real == $0 || real.hasPrefix($0 + "/") }) else { continue }
            let size = SpotlightDiskImageQuery.physicalSize(url) ?? sizer.allocatedSize(of: url)
            out.append(JunkItem(group: group, name: url.lastPathComponent, url: url, size: size,
                                badge: mounted.contains(real) ? .mounted : nil, icon: .file(url),
                                removal: .deleteDiskImage(url)))
        }
        return out.sorted { $0.size > $1.size }
    }
}
