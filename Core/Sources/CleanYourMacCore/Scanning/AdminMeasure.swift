import Foundation

/// Medição com privilégio dos grupos que só root consegue ler (docs/re/specs/system-cache.md §Cálculo de tamanho).
public enum AdminMeasure {
    /// Refaz o Cache do Sistema medindo pelo lote privilegiado os candidatos ilegíveis.
    public static func systemCache(context: ScanContext, runner: any PrivilegedRunner,
                                   exclusions: Exclusions = .bundled, apps: any AppLookup = WorkspaceAppLookup()) async throws(PrivilegedError) -> GroupResult {
        let fm = FileManager.default
        let root = context.resolve("/Library/Caches")
        let real = URL(fileURLWithPath: PathPolicy.realPath(root.path), isDirectory: true)
        var candidates = ((try? fm.contentsOfDirectory(at: real, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path }
        let core = context.resolve("/System/Library/Caches/com.apple.coresymbolicationd")
        if fm.fileExists(atPath: core.path) { candidates.append(core) }
        candidates = candidates.filter {
            $0.lastPathComponent != ".DS_Store" && !RuleBasedScanner.isSymlink($0) && !exclusions.excludes($0, group: .systemCache, context: context)
        }
        let sizer = FileSizer()
        var sizes = candidates.map { u -> Int64? in
            access(u.path, R_OK | X_OK) == 0 ? sizer.allocatedSize(of: u) : nil
        }
        let unreadable = candidates.indices.filter { sizes[$0] == nil || sizes[$0] == 0 }
        if !unreadable.isEmpty {
            let measured = try await runner.measure(unreadable.map { candidates[$0] })
            for (i, size) in zip(unreadable, measured) where size != nil { sizes[i] = size }
        }
        let items = zip(candidates, sizes).compactMap { url, size -> JunkItem? in
            guard let size, size > 0 else { return nil }
            let id = url.lastPathComponent
            let leaf = JunkItem(group: .systemCache, name: id, url: url, size: size, isRecommended: true,
                                icon: .file(url), removal: .delete(url))
            let app = apps.application(bundleID: id)
            return JunkItem(id: "systemCache:\(id)", group: .systemCache, name: app?.url.lastPathComponent ?? id, url: nil, size: 0,
                            icon: app.map { .app($0.url) } ?? .symbol("folder"), children: [leaf], displaysChildren: false)
        }
        return GroupResult(group: .systemCache, items: items)
    }
}
