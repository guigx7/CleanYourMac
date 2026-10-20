import Foundation

/// Scanner genérico guiado por `GroupRules`.
public struct RuleBasedScanner: ScopedScanner {
    public let rules: GroupRules
    private let apps: any AppLookup
    private let sizer = FileSizer()

    public var group: GroupID { rules.group }

    public init(rules: GroupRules, apps: any AppLookup = WorkspaceAppLookup()) {
        self.rules = rules
        self.apps = apps
    }

    public static func hasBundledRules(_ group: GroupID) -> Bool {
        url(for: group) != nil
    }

    /// Carrega `rules/<group>.json` do bundle do pacote.
    public static func bundled(_ group: GroupID, apps: any AppLookup = WorkspaceAppLookup()) throws -> RuleBasedScanner {
        guard let url = url(for: group) else { throw CocoaError(.fileNoSuchFile) }
        let rules = try JSONDecoder().decode(GroupRules.self, from: Data(contentsOf: url))
        return RuleBasedScanner(rules: rules, apps: apps)
    }

    private static func url(for group: GroupID) -> URL? {
        Bundle.module.url(forResource: group.rawValue, withExtension: "json", subdirectory: "rules")
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        var items: [JunkItem] = []
        var found: Int64 = 0
        for rule in rules.rules {
            for template in rule.roots {
                try Task.checkCancellation()
                let root = context.resolve(template)
                report(ScanProgress(group: group, currentPath: root.path, bytesFound: found))
                for candidate in candidates(rule, root: root) {
                    try Task.checkCancellation()
                    report(ScanProgress(group: group, currentPath: candidate.path, bytesFound: found))
                    guard let item = makeItem(rule, url: candidate, root: root, now: context.now) else { continue }
                    found += item.size
                    items.append(item)
                }
            }
        }
        return items
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        var scope = RemovalScope()
        for rule in rules.rules {
            for template in rule.roots {
                let url = context.resolve(template)
                switch rule.itemLevel {
                case .children: scope.roots.append(url)
                case .root: scope.items.append(url)
                }
            }
        }
        return scope
    }

    /// Raízes de onde saem itens filhos (usado em testes e diagnósticos).
    public func allowedRoots(_ context: ScanContext) -> [URL] { removalScope(context).roots }

    private func candidates(_ rule: PathRule, root: URL) -> [URL] {
        guard isRealDirectory(root) else { return [] }
        switch rule.itemLevel {
        case .root:
            return [root]
        case .children:
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            return children.filter { !Self.isSymlink($0) }.sorted { $0.path < $1.path }
        }
    }

    private func makeItem(_ rule: PathRule, url: URL, root: URL, now: Date) -> JunkItem? {
        let name = url.lastPathComponent
        if let include = rule.include, !include.contains(where: { Self.matches($0, name) }) { return nil }
        let relative = rule.itemLevel == .root ? name : String(url.path.dropFirst(root.path.count + 1))
        if rule.exclude.contains(where: { Self.matches($0, relative) }) { return nil }
        if let days = rule.minAgeDays {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) >= Double(days) * 86_400 else { return nil }
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        let size = sizer.allocatedSize(of: url)
        guard size > 0 else { return nil }

        var display = name
        var icon = IconSource.file(url)
        if let app = apps.application(bundleID: name) {
            display = app.name
            icon = .app(app.url)
        }
        let removal: RemovalAction = switch rule.removal {
        case .delete: .delete(url)
        case .moveToTrash: .moveToTrash(url)
        case .deleteContents: .deleteContents(of: url)
        }
        return JunkItem(group: group, name: display, detail: rule.detail, url: url, size: size,
                        isRecommended: rule.recommended, icon: icon, removal: removal)
    }

    private func isRealDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    static func matches(_ pattern: String, _ string: String) -> Bool {
        fnmatch(pattern, string, 0) == 0
    }
}
