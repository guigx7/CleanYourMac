import Foundation

/// Desinstalador: um item por app, com o bundle e os arquivos relacionados agrupados por tipo
/// (docs/re/specs/apps/inventory.md, related-files.md, reset.md).
public struct UninstallerScanner: ScopedScanner {
    public let group = GroupID.appUninstall
    private let catalog: AppCatalog
    private let finder: RelatedFilesFinder

    public init(catalog: AppCatalog = AppCatalog(), finder: RelatedFilesFinder = RelatedFilesFinder()) {
        self.catalog = catalog
        self.finder = finder
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        let temp = context.darwinUserCacheDir.deletingLastPathComponent().appendingPathComponent("T")
        return RemovalScope(roots: ["/Applications", "~/Applications", "~/Library", "/Library", "~/Downloads"].map(context.resolve)
            + [context.darwinUserCacheDir, temp])
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        let apps = catalog.apps(context)
        return try items(for: apps, context: context, report: report)
    }

    /// Itens a partir de um inventário já feito (o AppsScan reaproveita a mesma lista).
    public func items(for apps: [AppRecord], context: ScanContext, report: @Sendable (ScanProgress) -> Void = { _ in }) throws -> [JunkItem] {
        var out: [JunkItem] = []
        for app in apps {
            try Task.checkCancellation()
            report(ScanProgress(group: group, currentPath: app.url.path, bytesFound: 0))
            out.append(item(for: app, installed: apps, context: context))
        }
        return out
    }

    func item(for app: AppRecord, installed: [AppRecord], context: ScanContext) -> JunkItem {
        let sizer = FileSizer()
        let locked = app.isProtected || app.isSelf
        // Plug-ins de áudio: a própria pasta é o "binário".
        let bundleSize = app.kind == .audioPlugin ? app.bundleSize : sizer.allocatedSize(of: app.url)
        var binaries = [JunkItem(id: AppItemID.bundle(mode: .uninstall, appID: app.id), group: group, name: app.url.lastPathComponent,
                                 detail: ResourceKind.binaries.rawValue, url: app.url, size: bundleSize, isRecommended: !locked,
                                 badge: locked ? .locked : nil, icon: .app(app.url),
                                 removal: locked ? nil : (app.kind == .audioPlugin ? .moveToTrash(app.url) : .trashAppBundle(app.url)))]
        for copy in app.copies {
            binaries.append(JunkItem(id: AppItemID.leaf(mode: .uninstall, appID: app.id, path: copy.path), group: group,
                                     name: copy.lastPathComponent, detail: ResourceKind.binaries.rawValue, url: copy,
                                     size: sizer.allocatedSize(of: copy), isRecommended: false, icon: .app(copy),
                                     removal: .trashAppBundle(copy)))
        }
        var groups: [ResourceKind: [JunkItem]] = [.binaries: binaries]
        let related = app.kind == .application ? finder.files(for: app, installed: installed, context: context) : []
        for f in related {
            groups[f.kind, default: []].append(JunkItem(id: AppItemID.leaf(mode: .uninstall, appID: app.id, path: f.url.path), group: group,
                                                        name: f.url.lastPathComponent, detail: f.kind.rawValue, url: f.url,
                                                        size: f.size, isRecommended: f.isSelected && !app.isSelf,
                                                        icon: .file(f.url), removal: f.removal))
        }
        // Binários primeiro; os outros tipos pela ordem do enum (a UI ordena pelo nome localizado).
        let kinds = [ResourceKind.binaries] + ResourceKind.allCases.filter { $0 != .binaries && groups[$0] != nil }
        let children = kinds.map { kind in
            JunkItem(id: "\(AppItemID.Mode.uninstall.rawValue):\(app.id)\(AppItemID.sep)kind:\(kind.rawValue)", group: group,
                     name: kind.rawValue, detail: kind.rawValue, url: nil, size: 0,
                     children: (groups[kind] ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
        return JunkItem(id: "\(AppItemID.Mode.uninstall.rawValue):\(app.id)", group: group, name: app.name, url: app.url, size: 0,
                        icon: .app(app.url), children: children)
    }

    /// O mesmo app no modo Redefinir: sem bundle (fica como referência), sem recibos e instaladores, marcação de reset.md.
    /// `nil` para o próprio CleanYourMac (redefinir a si mesmo é bloqueado).
    public static func resetItem(from appItem: JunkItem, context: ScanContext) -> JunkItem? {
        guard let bundle = appItem.leaves.first(where: { AppItemID.isBundle($0.id) }),
              let appID = AppItemID.appID(of: bundle.id) else { return nil }
        let owner = AppItemID.owner(of: bundle.id) ?? ""
        if owner == AppCatalog.selfBundleID { return nil }
        let isApple = owner.lowercased().hasPrefix("com.apple.")
        let home = PathPolicy.realPath(context.home.path)
        let darwin = PathPolicy.realPath(context.darwinUserCacheDir.deletingLastPathComponent().path)
        let excluded: Set<String> = [ResourceKind.other.rawValue, ResourceKind.installers.rawValue, ResourceKind.applications.rawValue]
        let marked: Set<String> = [ResourceKind.preferences.rawValue, ResourceKind.supportingFiles.rawValue, ResourceKind.logs.rawValue]
        let mode = AppItemID.Mode.reset.rawValue
        let children: [JunkItem] = appItem.children.compactMap { kind in
            guard let k = kind.detail, !excluded.contains(k) else { return nil }
            let leaves = kind.children.map { leaf -> JunkItem in
                let path = leaf.url.map { PathPolicy.realPath($0.path) } ?? ""
                let inHome = path.hasPrefix(home + "/") || path.hasPrefix(darwin + "/")
                let isBinary = k == ResourceKind.binaries.rawValue
                let lock = isBinary || (isApple && !inHome)
                let id = isBinary && AppItemID.isBundle(leaf.id) ? AppItemID.bundle(mode: .reset, appID: appID)
                    : AppItemID.leaf(mode: .reset, appID: appID, path: leaf.url?.path ?? leaf.name)
                return JunkItem(id: id, group: leaf.group, name: leaf.name, detail: leaf.detail, url: leaf.url, size: leaf.size,
                                isRecommended: !lock && marked.contains(k) && inHome, badge: lock ? .locked : leaf.badge,
                                icon: leaf.icon, removal: lock ? nil : leaf.removal)
            }
            return JunkItem(id: kind.id.replacingOccurrences(of: AppItemID.Mode.uninstall.rawValue + ":", with: mode + ":"),
                            group: kind.group, name: kind.name, detail: k, url: nil, size: 0, children: leaves)
        }
        return JunkItem(id: "\(mode):\(appID)", group: appItem.group, name: appItem.name, url: appItem.url, size: 0,
                        icon: appItem.icon, children: children)
    }

    /// Redefinir com contêiner ou dados do usuário marcados pede uma confirmação a mais.
    public static func needsResetConfirmation(_ selectedLeaves: [JunkItem]) -> Bool {
        selectedLeaves.contains { $0.detail == ResourceKind.container.rawValue || $0.detail == ResourceKind.userData.rawValue }
    }
}
