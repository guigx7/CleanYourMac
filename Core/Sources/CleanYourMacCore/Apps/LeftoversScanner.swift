import AppKit

/// Sobras de apps já apagados (docs/re/specs/apps/leftovers.md). Na v0.2, só a fonte 2: contêineres de sandbox
/// cujo app (`application_bundle` dos metadados) não existe mais. Os arquivos do fantasma vêm do RelatedFilesFinder.
public struct LeftoversScanner: ScopedScanner {
    public let group = GroupID.appLeftovers
    private let catalog: AppCatalog
    private let finder: RelatedFilesFinder
    private let appExists: @Sendable (String) -> Bool

    public init(catalog: AppCatalog = AppCatalog(), finder: RelatedFilesFinder = RelatedFilesFinder(),
                appExists: @escaping @Sendable (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) {
        self.catalog = catalog
        self.finder = finder
        self.appExists = appExists
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        UninstallerScanner().removalScope(context)
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        try items(installed: catalog.apps(context), context: context, report: report)
    }

    /// Caminho do app dono, pelos metadados do contêiner (atual ou legado).
    static func applicationBundle(of container: URL) -> String? {
        for name in [".com.apple.containermanagerd.metadata.plist", "Container.plist"] {
            guard let data = try? Data(contentsOf: container.appendingPathComponent(name)),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let info = dict["MCMMetadataInfo"] as? [String: Any],
                  let validation = info["SandboxProfileDataValidationInfo"] as? [String: Any],
                  let params = validation["SandboxProfileDataValidationParametersKey"] as? [String: Any],
                  let path = params["application_bundle"] as? String else { continue }
            return path
        }
        return nil
    }

    public func items(installed: [AppRecord], context: ScanContext, report: @Sendable (ScanProgress) -> Void = { _ in }) throws -> [JunkItem] {
        let known = Set(installed.map { $0.bundleID.lowercased() })
        let dir = URL(fileURLWithPath: PathPolicy.realPath(context.resolve("~/Library/Containers").path))
        report(ScanProgress(group: group, currentPath: dir.path, bytesFound: 0))
        let containers = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var seen = Set<String>()
        var out: [JunkItem] = []
        for c in containers {
            try Task.checkCancellation()
            let v = try? c.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            let id = c.lastPathComponent
            guard v?.isSymbolicLink != true, v?.isDirectory == true, HelperExecutor.isSafeIdentifier(id),
                  !id.lowercased().hasPrefix("com.apple."), !known.contains(id.lowercased()),
                  seen.insert(id.lowercased()).inserted,
                  let appPath = Self.applicationBundle(of: c),
                  !FileManager.default.fileExists(atPath: context.resolve(appPath).path),
                  !FileManager.default.fileExists(atPath: appPath), !appExists(id) else { continue }
            let name = (appPath as NSString).lastPathComponent.isEmpty ? id
                : ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
            let ghost = AppRecord(url: URL(fileURLWithPath: appPath), bundleID: id, name: name, matchName: name)
            let files = finder.files(for: ghost, installed: installed + [ghost], context: context)
            guard !files.isEmpty else { continue }
            var groups: [ResourceKind: [JunkItem]] = [:]
            for f in files {
                groups[f.kind, default: []].append(JunkItem(id: AppItemID.leftover(bundleID: id, path: f.url.path), group: group,
                                                            name: f.url.lastPathComponent, detail: f.kind.rawValue, url: f.url,
                                                            size: f.size, isRecommended: f.isSelected, icon: .file(f.url),
                                                            removal: f.removal))
            }
            let children = ResourceKind.allCases.compactMap { kind in
                groups[kind].map {
                    JunkItem(id: "\(AppItemID.Mode.leftovers.rawValue):\(id)\(AppItemID.sep)kind:\(kind.rawValue)", group: group,
                             name: kind.rawValue, detail: kind.rawValue, url: nil, size: 0, children: $0)
                }
            }
            out.append(JunkItem(id: "\(AppItemID.Mode.leftovers.rawValue):\(id)", group: group, name: name, detail: id,
                                url: c, size: 0, icon: .symbol("app.dashed"), children: children))
        }
        return out
    }
}
