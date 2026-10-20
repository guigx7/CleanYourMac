import Foundation

/// Caches do usuário e do sistema (docs/re/specs/user-cache.md, system-cache.md).
/// Candidatos de várias raízes são agrupados por identificador; cada identificador vira um item.
public struct CacheScanner: ScopedScanner {
    struct Candidate {
        let identifier: String
        let url: URL
        let recommended: Bool
        /// Fontes agrupadas/personalizadas só entram com tamanho > 0.
        let requireNonEmpty: Bool
    }

    /// Uma fonte de candidatos e a área que a limpeza dela pode tocar.
    struct Source: Sendable {
        let candidates: @Sendable (ScanContext, any AppInventory) -> [Candidate]
        let scope: @Sendable (ScanContext, any AppInventory) -> RemovalScope
    }

    public let group: GroupID
    let sources: [Source]
    /// Itens de 0 bytes das raízes simples entram (userCache) ou não (systemCache).
    let includeEmpty: Bool
    let displaysChildren: Bool
    private let apps: any AppLookup
    private let inventory: any AppInventory
    private let exclusions: Exclusions
    private let sizer = FileSizer()

    init(group: GroupID, sources: [Source], includeEmpty: Bool, displaysChildren: Bool,
         apps: any AppLookup, inventory: any AppInventory, exclusions: Exclusions) {
        self.group = group
        self.sources = sources
        self.includeEmpty = includeEmpty
        self.displaysChildren = displaysChildren
        self.apps = apps
        self.inventory = inventory
        self.exclusions = exclusions
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        sources.reduce(into: RemovalScope()) { scope, source in
            let s = source.scope(context, inventory)
            scope.roots += s.roots
            scope.items += s.items
        }
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        var order: [String] = []
        var byID: [String: [JunkItem]] = [:]
        var found: Int64 = 0
        for source in sources {
            for c in source.candidates(context, inventory) {
                try Task.checkCancellation()
                guard c.url.lastPathComponent != ".DS_Store",
                      !RuleBasedScanner.isSymlink(c.url),
                      !exclusions.excludes(c.url, group: group, context: context),
                      group != .userCache || !AICatalog.claims(c.url, context: context) else { continue }
                report(ScanProgress(group: group, currentPath: c.url.path, bytesFound: found))
                let size = sizer.allocatedSize(of: c.url)
                if size == 0, c.requireNonEmpty || !includeEmpty { continue }
                found += size
                let leaf = JunkItem(group: group, name: c.url.lastPathComponent, url: c.url, size: size,
                                    isRecommended: c.recommended, icon: .file(c.url), removal: .delete(c.url))
                if byID[c.identifier] == nil { order.append(c.identifier) }
                byID[c.identifier, default: []].append(leaf)
            }
        }
        return order.map { identifier in
            var name = identifier
            var icon = IconSource.symbol("folder")
            if let app = apps.application(bundleID: identifier) {
                name = app.url.lastPathComponent
                icon = .app(app.url)
            }
            return JunkItem(id: "\(group.rawValue):\(identifier)", group: group, name: name, url: nil, size: 0,
                            icon: icon, children: byID[identifier] ?? [], displaysChildren: displaysChildren)
        }
    }
}

// MARK: - Grupos

extension CacheScanner {
    public static func userCache(apps: any AppLookup = WorkspaceAppLookup(),
                                 inventory: any AppInventory = FolderAppInventory(),
                                 exclusions: Exclusions = .bundled) -> CacheScanner {
        CacheScanner(group: .userCache,
                     sources: [.children("~/Library/Caches"), .children("$DARWIN"), .containerCaches,
                               .electron, .hardcoded, .spotify, .appStore, .gradle],
                     includeEmpty: true, displaysChildren: true, apps: apps, inventory: inventory, exclusions: exclusions)
    }

    public static func systemCache(apps: any AppLookup = WorkspaceAppLookup(),
                                   exclusions: Exclusions = .bundled) -> CacheScanner {
        CacheScanner(group: .systemCache,
                     sources: [.children("/Library/Caches"),
                               .single("/System/Library/Caches/com.apple.coresymbolicationd", recommended: true)],
                     includeEmpty: false, displaysChildren: false, apps: apps, inventory: FolderAppInventory(folders: []),
                     exclusions: exclusions)
    }
}

// MARK: - Fontes

extension CacheScanner.Source {
    typealias Candidate = CacheScanner.Candidate

    /// Filhos diretos, listados a partir do caminho real da pasta (a raiz pode ser um symlink).
    static func listChildren(_ dir: URL) -> [URL] {
        let real = URL(fileURLWithPath: PathPolicy.realPath(dir.path), isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: real, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.path < $1.path }
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Cada filho direto da raiz; o identificador é o nome do filho.
    static func children(_ template: String, recommended: Bool = true) -> Self {
        Self(candidates: { ctx, _ in
            listChildren(ctx.resolve(template)).map {
                Candidate(identifier: $0.lastPathComponent, url: $0, recommended: recommended, requireNonEmpty: false)
            }
        }, scope: { ctx, _ in RemovalScope(roots: [ctx.resolve(template)]) })
    }

    /// Uma pasta inteira como candidato; o identificador é o último componente.
    static func single(_ template: String, recommended: Bool) -> Self {
        Self(candidates: { ctx, _ in
            let u = ctx.resolve(template)
            return exists(u) ? [Candidate(identifier: u.lastPathComponent, url: u, recommended: recommended, requireNonEmpty: false)] : []
        }, scope: { ctx, _ in RemovalScope(items: [ctx.resolve(template)]) })
    }

    private static func containerCachesDirs(_ ctx: ScanContext) -> [(String, URL)] {
        listChildren(ctx.resolve("~/Library/Containers")).map {
            ($0.lastPathComponent, $0.appendingPathComponent("Data/Library/Caches"))
        }
    }

    /// `~/Library/Containers/<c>/Data/Library/Caches/*`, agrupados pelo nome do container.
    static var containerCaches: Self {
        Self(candidates: { ctx, _ in
            containerCachesDirs(ctx).flatMap { id, dir in
                listChildren(dir).map { Candidate(identifier: id, url: $0, recommended: true, requireNonEmpty: false) }
            }
        }, scope: { ctx, _ in RemovalScope(roots: containerCachesDirs(ctx).map(\.1)) })
    }

    private static func electronCaches(_ ctx: ScanContext, _ inventory: any AppInventory) -> [(String, URL)] {
        inventory.apps(ctx).compactMap { app in
            guard exists(app.url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")) else { return nil }
            let candidates = [
                ctx.resolve("~/Library/Application Support/\(app.name)/Cache"),
                ctx.resolve("~/Library/Containers/\(app.bundleID)/Data/Library/Application Support/\(app.name)/Cache"),
            ]
            return candidates.first(where: exists).map { (app.bundleID, $0) }
        }
    }

    /// Apps Electron: `Application Support/<nome>/Cache`, agrupado pelo bundle id.
    static var electron: Self {
        Self(candidates: { ctx, inv in
            electronCaches(ctx, inv).map { Candidate(identifier: $0.0, url: $0.1, recommended: true, requireNonEmpty: true) }
        }, scope: { ctx, inv in RemovalScope(items: electronCaches(ctx, inv).map(\.1)) })
    }

    private static func hardcodedCandidates(_ ctx: ScanContext) -> [Candidate] {
        func fixed(_ id: String, _ urls: [URL], recommended: Bool = false) -> [Candidate] {
            urls.filter(exists).map { Candidate(identifier: id, url: $0, recommended: recommended, requireNonEmpty: true) }
        }
        var out: [Candidate] = []
        // Telegram (Mac App Store): <grupo>/<n>/account-*/postbox/media
        let tg = ctx.resolve("~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram")
        let tgMedia = listChildren(tg).flatMap { level1 in
            listChildren(level1).filter { $0.lastPathComponent.hasPrefix("account-") }
                .map { $0.appendingPathComponent("postbox/media") }
        }
        out += fixed("ru.keepcoder.Telegram", tgMedia)
        for (id, base) in [("org.telegram.desktop", "~/Library/Containers/org.telegram.desktop/Data/Library/Application Support/Telegram Desktop/tdata/user_data"),
                           ("com.tdesktop.Telegram", "~/Library/Application Support/Telegram Desktop/tdata/user_data")] {
            out += fixed(id, ["cache", "media_cache"].map { ctx.resolve(base).appendingPathComponent($0) })
        }
        let wechat = ctx.resolve("~/Library/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat/2.0b4.0.9")
        out += fixed("com.tencent.xinWeChat", listChildren(wechat).map { $0.appendingPathComponent("Message/MessageTemp") })
        out += fixed("com.tencent.tenvideo", [ctx.resolve("~/Library/Containers/com.tencent.tenvideo/Data/Library/Application Support/Download/video")])
        out += fixed("com.tencent.QQMusicMac", [ctx.resolve("~/Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac/iMusic")])
        out += fixed("com.youku.mac", [ctx.resolve("~/Library/Containers/com.youku.mac/Data/Documents/YTCORE_PLAYER_CACHE")])
        out += fixed("Adobe Premier Pro Media Cache", [ctx.resolve("~/Library/Application Support/Adobe/Common/Media Cache Files")])
        if let migration = listChildren(ctx.resolve("/Library/SystemMigration/History"))
            .first(where: { $0.lastPathComponent.hasPrefix("Migration-") }) {
            out += fixed("System Migration Cache", [migration.appendingPathComponent("QuarantineRoot/private/var/db/dyld")])
        }
        // Fotos: todos os filhos menos o acessado mais recentemente.
        let photos = listChildren(ctx.resolve("~/Library/Containers/com.apple.Photos/Data/Library/Application Support/Photos Desktop/0"))
        let accessed = { (u: URL) in (try? u.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast }
        if let newest = photos.max(by: { accessed($0) < accessed($1) }) {
            out += fixed("com.apple.Photos", photos.filter { $0 != newest }, recommended: true)
        }
        return out
    }

    /// Caminhos fixos de apps conhecidos (Telegram, WeChat, Adobe, Fotos, Migração…).
    static var hardcoded: Self {
        Self(candidates: { ctx, _ in hardcodedCandidates(ctx) },
             scope: { ctx, _ in RemovalScope(items: hardcodedCandidates(ctx).map(\.url)) })
    }

    private static func spotifyStorage(_ ctx: ScanContext) -> URL {
        let prefs = ctx.resolve("~/Library/Application Support/Spotify/prefs")
        if let text = try? String(contentsOf: prefs, encoding: .utf8) {
            for key in ["storage.location=", "storage.last-location="] {
                if let line = text.split(separator: "\n").first(where: { $0.hasPrefix(key) }) {
                    var value = String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
                    if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
                    if !value.isEmpty { return URL(fileURLWithPath: value) }
                }
            }
        }
        return ctx.resolve("~/Library/Application Support/Spotify/PersistentCache/Storage")
    }

    static var spotify: Self {
        Self(candidates: { ctx, _ in
            let u = spotifyStorage(ctx)
            return exists(u) ? [Candidate(identifier: "com.spotify.client", url: u, recommended: false, requireNonEmpty: true)] : []
        }, scope: { ctx, _ in RemovalScope(items: [spotifyStorage(ctx)]) })
    }

    private static func appStorePurgeables(_ ctx: ScanContext) -> [URL] {
        let manifest = ctx.resolve("$DARWIN/com.apple.appstore/manifest.plist")
        guard let data = try? Data(contentsOf: manifest),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let paths = dict["purgeables"] as? [String] else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }.filter(exists)
    }

    static var appStore: Self {
        Self(candidates: { ctx, _ in
            appStorePurgeables(ctx).map { Candidate(identifier: "com.apple.appstore", url: $0, recommended: true, requireNonEmpty: true) }
        }, scope: { ctx, _ in RemovalScope(items: appStorePurgeables(ctx)) })
    }

    static var gradle: Self {
        Self(candidates: { ctx, _ in
            listChildren(ctx.resolve("~/.gradle/caches")).map {
                Candidate(identifier: "Gradle", url: $0, recommended: false, requireNonEmpty: true)
            }
        }, scope: { ctx, _ in RemovalScope(roots: [ctx.resolve("~/.gradle/caches")]) })
    }
}
