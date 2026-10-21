import AppKit

/// Sobras de apps já apagados (docs/re/specs/apps/leftovers.md). Na v0.2, só a fonte 2: contêineres de sandbox
/// cujo app (`application_bundle` dos metadados) não existe mais. Os arquivos do fantasma vêm do RelatedFilesFinder.
public struct LeftoversScanner: ScopedScanner {
    public let group = GroupID.appLeftovers
    private let catalog: AppCatalog
    private let finder: RelatedFilesFinder
    private let appExists: @Sendable (String) -> Bool

    public init(catalog: AppCatalog = AppCatalog(), finder: RelatedFilesFinder = RelatedFilesFinder(),
                appExists: @escaping @Sendable (String) -> Bool = LeftoversScanner.registeredAppExists) {
        self.catalog = catalog
        self.finder = finder
        self.appExists = appExists
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        UninstallerScanner().removalScope(context)
    }

    /// O LaunchServices conhece um app com esse bundle ID **e** ele ainda está no disco
    /// (o registro de extensões de apps apagados pode ficar para trás).
    public static func registeredAppExists(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        try items(installed: catalog.apps(context), context: context, report: report)
    }

    /// O que os metadados do contêiner dizem do app dono.
    public enum Owner: Equatable, Sendable {
        /// Caminho do app (`application_bundle`).
        case path(String)
        /// Metadados legíveis, sem caminho (comum em extensões).
        case noPath
        /// Sem metadados legíveis (sem Acesso Total ao Disco, por exemplo): o contêiner não é avaliado.
        case unreadable
    }

    public static func owner(of container: URL) -> Owner {
        var readable = false
        for name in [".com.apple.containermanagerd.metadata.plist", "Container.plist"] {
            guard let data = try? Data(contentsOf: container.appendingPathComponent(name)),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            readable = true
            if let info = dict["MCMMetadataInfo"] as? [String: Any],
               let validation = info["SandboxProfileDataValidationInfo"] as? [String: Any],
               let params = (validation["Parameters"] ?? validation["SandboxProfileDataValidationParametersKey"]) as? [String: Any],
               let path = params["application_bundle"] as? String {
                return .path(path)
            }
        }
        return readable ? .noPath : .unreadable
    }

    /// Dois primeiros componentes do bundle ID ("com.google").
    static func vendor(_ id: String) -> String { id.split(separator: ".").prefix(2).joined(separator: ".") }

    /// Bundle IDs dos pacotes dentro de um app (PlugIns, XPCServices, Library/LoginItems, Library/*).
    static func nestedBundleIDs(_ app: URL) -> Set<String> {
        let fm = FileManager.default
        var out = Set<String>()
        for sub in ["Contents/PlugIns", "Contents/XPCServices", "Contents/Library/LoginItems", "Contents/Library/LaunchServices",
                    "Contents/Library/QuickLook", "Contents/Library/Spotlight", "Contents/Extensions"] {
            for pkg in (try? fm.contentsOfDirectory(at: app.appendingPathComponent(sub), includingPropertiesForKeys: nil)) ?? [] {
                if let id = InfoPlist.read(pkg)["CFBundleIdentifier"] as? String ?? plistID(pkg.appendingPathComponent("Info.plist")) {
                    out.insert(id.lowercased())
                }
            }
        }
        return out
    }

    private static func plistID(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    /// Caminho do app dono, se os metadados o tiverem.
    public static func applicationBundle(of container: URL) -> String? {
        if case .path(let p) = owner(of: container) { return p }
        return nil
    }

    public func items(installed: [AppRecord], context: ScanContext, report: @Sendable (ScanProgress) -> Void = { _ in }) throws -> [JunkItem] {
        // Instalados: os apps, os plug-ins e os pacotes que vêm dentro dos apps (extensões, XPC, itens de início).
        var known = Set(installed.map { $0.bundleID.lowercased() })
        for app in installed where app.kind == .application { known.formUnion(Self.nestedBundleIDs(app.url)) }
        let vendors = Set(installed.filter { $0.kind == .application }.map { Self.vendor($0.bundleID.lowercased()) })
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
            let lower = id.lowercased()
            guard v?.isSymbolicLink != true, v?.isDirectory == true, HelperExecutor.isSafeIdentifier(id),
                  !lower.hasPrefix("com.apple."), !known.contains(lower), seen.insert(lower).inserted, !appExists(id) else { continue }
            let name: String, appPath: String
            switch Self.owner(of: c) {
            case .unreadable:
                continue
            case .path(let p):
                guard !FileManager.default.fileExists(atPath: context.resolve(p).path), !FileManager.default.fileExists(atPath: p) else { continue }
                appPath = p
                name = (p as NSString).lastPathComponent.isEmpty ? id : ((p as NSString).lastPathComponent as NSString).deletingPathExtension
            case .noPath:
                // Extensão sem caminho: é sobra só se nenhum app instalado for "pai" do bundle ID.
                guard !known.contains(where: { lower.hasPrefix($0 + ".") }), !vendors.contains(Self.vendor(lower)) else { continue }
                appPath = ""
                name = id
            }
            let ghost = AppRecord(url: URL(fileURLWithPath: appPath.isEmpty ? "/nonexistent/\(id).app" : appPath),
                                  bundleID: id, name: name, matchName: name)
            let files = finder.files(for: ghost, installed: installed + [ghost], context: context, idOnly: true)
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
