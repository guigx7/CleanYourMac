import Foundation

/// Registros do usuário e do sistema (docs/re/specs/user-logs.md, system-logs.md).
/// Arquivo aprovado → item; pasta → item com os arquivos aprovados (recursivo); pasta sem aprovados some.
public struct LogsScanner: ScopedScanner {
    enum Filter: Sendable {
        /// Exclui `.DS_Store` e arquivos com tamanho alocado ≤ 10 240 bytes.
        case standard
        /// Sem limite de tamanho nem filtro de `.DS_Store` (`/var/log/asl`).
        case noLimit
        /// Exclui só arquivos inexistentes ou vazios (banco de quarentena).
        case nonEmpty
    }

    struct Candidate {
        let url: URL
        let filter: Filter
        /// Nome passa pela busca de bundle id.
        let lookupName: Bool
    }

    struct Source: Sendable {
        let candidates: @Sendable (ScanContext) -> [Candidate]
        let scope: @Sendable (ScanContext) -> RemovalScope
    }

    static let sizeThreshold: Int64 = 10_240

    public let group: GroupID
    let sources: [Source]
    private let apps: any AppLookup
    private let exclusions: Exclusions
    private let sizer = FileSizer()

    init(group: GroupID, sources: [Source], apps: any AppLookup, exclusions: Exclusions) {
        self.group = group
        self.sources = sources
        self.apps = apps
        self.exclusions = exclusions
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        sources.reduce(into: RemovalScope()) { scope, source in
            let s = source.scope(context)
            scope.roots += s.roots
            scope.items += s.items
        }
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        var items: [JunkItem] = []
        var found: Int64 = 0
        for source in sources {
            for c in source.candidates(context) {
                try Task.checkCancellation()
                guard !RuleBasedScanner.isSymlink(c.url), !exclusions.excludes(c.url, group: group, context: context) else { continue }
                report(ScanProgress(group: group, currentPath: c.url.path, bytesFound: found))
                guard let item = makeItem(c) else { continue }
                found += item.totalSize
                items.append(item)
            }
        }
        return items
    }

    private func makeItem(_ c: Candidate) -> JunkItem? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: c.url.path, isDirectory: &isDir) else { return nil }
        let size = sizer.allocatedSize(of: c.url)
        guard passes(c.url, size: size, filter: c.filter) else { return nil }
        let raw = isDir.boolValue ? c.url.lastPathComponent : c.url.deletingPathExtension().lastPathComponent
        let name = c.lookupName ? (apps.application(bundleID: raw)?.name ?? raw) : raw
        let id = "\(group.rawValue):\(c.url.path)"
        if !isDir.boolValue {
            return JunkItem(id: id, group: group, name: name, url: c.url, size: size, isRecommended: true,
                            icon: .symbol("doc.text"), removal: .delete(c.url))
        }
        let children = files(in: c.url).compactMap { file -> JunkItem? in
            let s = sizer.allocatedSize(of: file)
            guard passes(file, size: s, filter: c.filter) else { return nil }
            return JunkItem(group: group, name: file.lastPathComponent, url: file, size: s, isRecommended: true,
                            icon: .symbol("doc.text"), removal: .delete(file))
        }
        guard !children.isEmpty else { return nil }
        return JunkItem(id: id, group: group, name: name, url: c.url, size: 0, icon: .symbol("folder"),
                        children: children, displaysChildren: false)
    }

    private func passes(_ url: URL, size: Int64, filter: Filter) -> Bool {
        switch filter {
        case .standard: url.lastPathComponent != ".DS_Store" && size > Self.sizeThreshold
        case .noLimit: true
        case .nonEmpty: size > 0
        }
    }

    /// Arquivos (não pastas, não symlinks) em todas as profundidades.
    private func files(in dir: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        var out: [URL] = []
        while let u = e?.nextObject() as? URL {
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isRegularFile == true, v?.isSymbolicLink != true { out.append(u) }
        }
        return out.sorted { $0.path < $1.path }
    }
}

// MARK: - Grupos

extension LogsScanner {
    public static func userLogs(apps: any AppLookup = WorkspaceAppLookup(), exclusions: Exclusions = .bundled) -> LogsScanner {
        LogsScanner(group: .userLogs, sources: [.children("~/Library/Logs", lookupName: true), .containerLogs, .quarantine],
                    apps: apps, exclusions: exclusions)
    }

    public static func systemLogs(apps: any AppLookup = WorkspaceAppLookup(), exclusions: Exclusions = .bundled) -> LogsScanner {
        LogsScanner(group: .systemLogs, sources: [.children("/Library/Logs", lookupName: false), .asl, .privateLogs(apps: apps)],
                    apps: apps, exclusions: exclusions)
    }
}

// MARK: - Fontes

extension LogsScanner.Source {
    typealias Candidate = LogsScanner.Candidate

    /// Filhos diretos, listados a partir do caminho real da pasta (a raiz pode ser um symlink).
    static func listChildren(_ dir: URL) -> [URL] {
        let real = URL(fileURLWithPath: PathPolicy.realPath(dir.path), isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: real, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.path < $1.path }
    }

    static func children(_ template: String, lookupName: Bool) -> Self {
        Self(candidates: { ctx in
            listChildren(ctx.resolve(template)).map { Candidate(url: $0, filter: .standard, lookupName: lookupName) }
        }, scope: { ctx in RemovalScope(roots: [ctx.resolve(template)]) })
    }

    private static func containerLogDirs(_ ctx: ScanContext) -> [URL] {
        listChildren(ctx.resolve("~/Library/Containers")).map { $0.appendingPathComponent("Data/Library/Logs") }
    }

    static var containerLogs: Self {
        Self(candidates: { ctx in
            containerLogDirs(ctx).flatMap(listChildren).map { Candidate(url: $0, filter: .standard, lookupName: true) }
        }, scope: { ctx in RemovalScope(roots: containerLogDirs(ctx)) })
    }

    private static let quarantineFiles = ["~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2",
                                          "~/Library/Preferences/com.apple.LaunchServices.QuarantineEvents"]

    static var quarantine: Self {
        Self(candidates: { ctx in
            quarantineFiles.map { Candidate(url: ctx.resolve($0), filter: .nonEmpty, lookupName: true) }
        }, scope: { ctx in RemovalScope(items: quarantineFiles.map(ctx.resolve)) })
    }

    static var asl: Self {
        Self(candidates: { ctx in [Candidate(url: ctx.resolve("/private/var/log/asl"), filter: .noLimit, lookupName: false)] },
             scope: { ctx in RemovalScope(roots: [ctx.resolve("/private/var/log/asl")]) })
    }

    private static let privateNames = ["DiagnosticMessages", "cups", "daily.out", "weekly.out", "monthly.out", "system.log",
                                       "install.log", "wifi.log", "sck_hfs.log", "fsck_hfs.log", "fsck_apfs.log"]
    private static let privatePatterns = [#"^system\.log\.\d\.gz$"#, #"^wifi\.log\.\d\.bz2$"#]

    static func privateLogs(apps: any AppLookup) -> Self {
        Self(candidates: { ctx in
            let dir = ctx.resolve("/private/var/log")
            var urls = privateNames.map { dir.appendingPathComponent($0) }
            urls += listChildren(dir).filter { u in
                privatePatterns.contains { u.lastPathComponent.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
            }
            return urls.map { Candidate(url: $0, filter: .standard, lookupName: true) }
        }, scope: { ctx in RemovalScope(roots: [ctx.resolve("/private/var/log")]) })
    }
}
