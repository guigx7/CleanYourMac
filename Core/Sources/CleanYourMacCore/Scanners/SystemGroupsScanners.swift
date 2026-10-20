import Foundation
import CoreServices

private func visibleChildren(_ dir: URL) -> [URL] {
    let real = URL(fileURLWithPath: PathPolicy.realPath(dir.path), isDirectory: true)
    return ((try? FileManager.default.contentsOfDirectory(at: real, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

private func readPlist(_ u: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: u) else { return nil }
    return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
}

// MARK: - Usuários apagados

/// Imagens `.dmg` em `/Users/Deleted Users` (docs/re/specs/deleted-users.md). Nada recomendado.
public struct DeletedUsersScanner: ScopedScanner {
    public let group = GroupID.deletedUsers
    private let sizer = FileSizer()

    public init() {}

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(roots: [context.resolve("/Users/Deleted Users")])
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        let root = context.resolve("/Users/Deleted Users")
        report(ScanProgress(group: group, currentPath: root.path, bytesFound: 0))
        return visibleChildren(root).filter { $0.pathExtension == "dmg" }.map { u in
            JunkItem(group: group, name: u.deletingPathExtension().lastPathComponent, url: u, size: sizer.allocatedSize(of: u),
                     icon: .file(u), removal: .delete(u))
        }
    }
}

// MARK: - Backups iOS

/// Backups em `MobileSync/Backup`, agrupados por aparelho (docs/re/specs/ios-backups.md).
public struct IOSBackupsScanner: ScopedScanner {
    public let group = GroupID.iosBackups
    private let sizer = FileSizer()

    public init() {}

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(roots: [context.resolve("~/Library/Application Support/MobileSync/Backup")])
    }

    struct Backup {
        let url: URL
        let device: String?
        let deviceName: String?
        let productType: String?
        let date: Date?
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        let root = context.resolve("~/Library/Application Support/MobileSync/Backup")
        report(ScanProgress(group: group, currentPath: root.path, bytesFound: 0))
        let all = visibleChildren(root).map { dir -> Backup in
            let info = readPlist(dir.appendingPathComponent("Info.plist"))
            let name = (info?["Device Name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let type = info?["Product Type"] as? String
            let device = name.map { n in (type?.isEmpty == false) ? "\(n), \(type!)" : n }
            let date = (readPlist(dir.appendingPathComponent("Status.plist"))?["Date"] as? Date) ?? (info?["Last Backup Date"] as? Date)
            return Backup(url: dir, device: device, deviceName: name, productType: type, date: date)
        }
        var out: [JunkItem] = []
        var order: [String] = []
        var byDevice: [String: [Backup]] = [:]
        for b in all where b.device != nil {
            if byDevice[b.device!] == nil { order.append(b.device!) }
            byDevice[b.device!, default: []].append(b)
        }
        for device in order {
            let sorted = byDevice[device]!.sorted { a, b in
                switch (a.date, b.date) {
                case let (x?, y?): x > y
                case (_?, nil): true
                default: false
                }
            }
            let leaves = sorted.enumerated().map { i, b in
                JunkItem(group: group, name: b.date.map(Self.format) ?? b.url.lastPathComponent, url: b.url,
                         size: sizer.allocatedSize(of: b.url), isRecommended: i > 0, badge: i == 0 ? .latest : nil,
                         icon: .symbol("externaldrive"), removal: .delete(b.url))
            }
            let first = sorted[0]
            out.append(JunkItem(id: "iosBackups:\(device)", group: group, name: first.deviceName ?? device,
                                detail: first.productType.map(Self.modelName), url: nil, size: 0,
                                icon: .symbol(first.productType?.hasPrefix("iPad") == true ? "ipad" : "iphone"), children: leaves))
        }
        let broken = all.filter { $0.device == nil }.map { b in
            JunkItem(group: group, name: b.url.lastPathComponent, url: b.url, size: sizer.allocatedSize(of: b.url),
                     isRecommended: true, icon: .symbol("exclamationmark.triangle"), removal: .delete(b.url))
        }
        if !broken.isEmpty {
            out.append(JunkItem(id: "iosBackups:broken", group: group, name: "Damaged backups", url: nil, size: 0,
                                icon: .symbol("exclamationmark.triangle"), children: broken, titleKey: "ios.broken"))
        }
        return out
    }

    static func format(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .shortened) }

    /// Tabela pública de identificadores de modelo; desconhecido → o identificador cru.
    static func modelName(_ type: String) -> String {
        let names = ["iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
                     "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro",
                     "iPhone13,4": "iPhone 12 Pro Max", "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
                     "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE (3ª geração)",
                     "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
                     "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
                     "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,3": "iPhone 16",
                     "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max"]
        return names[type] ?? type
    }
}

// MARK: - Versões de documentos

public struct DocumentVersion: Sendable, Hashable {
    public let url: URL
    public let modificationDate: Date?
    public let size: Int64

    public init(url: URL, modificationDate: Date?, size: Int64) {
        self.url = url
        self.modificationDate = modificationDate
        self.size = size
    }
}

/// Spotlight + `NSFileVersion`. Injetável nos testes.
public protocol DocumentVersionSource: Sendable {
    func documents(utis: [String]) -> [URL]
    func versions(of document: URL) -> [DocumentVersion]
    func remove(version: URL, of document: URL) -> Bool
}

extension DocumentVersionSource {
    public func remove(version: URL, of document: URL) -> Bool { false }
}

public struct SystemDocumentVersions: DocumentVersionSource {
    public init() {}

    public func documents(utis: [String]) -> [URL] {
        let predicate = utis.map { "kMDItemContentTypeTree == '\($0)'" }.joined(separator: " || ")
        guard let query = MDQueryCreate(kCFAllocatorDefault, predicate as CFString, nil, nil) else { return [] }
        MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
        return (0..<MDQueryGetResultCount(query)).compactMap { i -> URL? in
            guard let raw = MDQueryGetResultAtIndex(query, i) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            return (MDItemCopyAttribute(item, kMDItemPath) as? String).map { URL(fileURLWithPath: $0) }
        }
    }

    public func versions(of document: URL) -> [DocumentVersion] {
        (NSFileVersion.otherVersionsOfItem(at: document) ?? []).map { v in
            DocumentVersion(url: v.url, modificationDate: v.modificationDate, size: FileSizer().allocatedSize(of: v.url))
        }
    }

    public func remove(version: URL, of document: URL) -> Bool {
        guard let v = NSFileVersion.otherVersionsOfItem(at: document)?.first(where: { $0.url == version }) else { return false }
        return (try? v.remove()) != nil
    }
}

/// Versões antigas de documentos do Pages, Keynote, Numbers e Sketch (docs/re/specs/document-versions.md).
public struct DocumentVersionsScanner: ScopedScanner {
    public let group = GroupID.documentVersions
    private let source: any DocumentVersionSource
    private let apps: any AppLookup

    static let catalog: [(name: String, bundleID: String, utis: [String])] = [
        ("Sketch", "com.bohemiancoding.sketch3", ["com.bohemiancoding.sketch.drawing.single", "com.bohemiancoding.sketch.drawing"]),
        ("Pages", "com.apple.iwork.pages", ["com.apple.iwork.pages.sffpages", "com.apple.iwork.pages.pages", "com.apple.iwork.pages.pages-tef"]),
        ("Keynote", "com.apple.iwork.keynote", ["com.apple.iwork.keynote.sffkey", "com.apple.iwork.keynote.key", "com.apple.iwork.keynote.key-tef"]),
        ("Numbers", "com.apple.iwork.numbers", ["com.apple.iwork.numbers.numbers", "com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.numbers.numbers-tef"]),
    ]

    static let thinningInterval: TimeInterval = 14_400

    public init(source: any DocumentVersionSource = SystemDocumentVersions(), apps: any AppLookup = WorkspaceAppLookup()) {
        self.source = source
        self.apps = apps
    }

    /// A remoção passa pela API de versões, não apaga arquivos diretamente.
    public func removalScope(_ context: ScanContext) -> RemovalScope { RemovalScope() }

    static func dropboxFolders(_ ctx: ScanContext) -> [String] {
        guard let data = try? Data(contentsOf: ctx.resolve("~/.dropbox/info.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return json.values.compactMap { ($0 as? [String: Any])?["path"] as? String }
    }

    /// Recomendação por versão: nem a primeira nem a última; as do meio se a vizinha mais nova estiver a < 4 h.
    static func recommendations(_ dates: [Date]) -> [Bool] {
        dates.indices.map { i in
            guard i > 0, i < dates.count - 1 else { return false }
            return abs(dates[i].timeIntervalSince(dates[i - 1])) < thinningInterval
        }
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        let dropbox = Self.dropboxFolders(context)
        return try Self.catalog.compactMap { app in
            try Task.checkCancellation()
            var seen = Set<String>()
            let docs = source.documents(utis: app.utis).filter { doc in
                seen.insert(doc.path).inserted && !dropbox.contains { doc.path.hasPrefix($0 + "/") }
            }
            let documents = docs.compactMap { doc -> JunkItem? in
                report(ScanProgress(group: group, currentPath: doc.path, bytesFound: 0))
                let versions = source.versions(of: doc).filter { $0.modificationDate != nil }
                    .sorted { $0.modificationDate! > $1.modificationDate! }
                let recommended = Self.recommendations(versions.map { $0.modificationDate! })
                let leaves = zip(versions, recommended).filter { $0.0.size > 0 }.map { v, rec in
                    JunkItem(id: "documentVersions:\(v.url.path)", group: group,
                             name: v.modificationDate!.formatted(date: .abbreviated, time: .standard), url: v.url, size: v.size,
                             isRecommended: rec, icon: .file(doc), removal: .removeFileVersion(document: doc, version: v.url))
                }
                guard !leaves.isEmpty else { return nil }
                return JunkItem(id: "documentVersions:doc:\(doc.path)", group: group, name: doc.lastPathComponent, url: doc,
                                size: 0, icon: .file(doc), children: leaves)
            }
            guard !documents.isEmpty else { return nil }
            let icon = apps.application(bundleID: app.bundleID).map { IconSource.app($0.url) } ?? .symbol("app")
            return JunkItem(id: "documentVersions:app:\(app.bundleID)", group: group, name: app.name, url: nil, size: 0,
                            icon: icon, children: documents)
        }
    }
}

// MARK: - Detritos do Xcode

/// Subgrupos de dados do Xcode e do simulador (docs/re/specs/xcode-junk.md).
public struct XcodeJunkScanner: ScopedScanner {
    public let group = GroupID.xcodeJunk
    private let commands: any CommandRunner
    private let simctl: String
    private let sizer = FileSizer()

    public static let defaultSimctl = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl"

    public init(commands: any CommandRunner = SystemCommandRunner(), simctl: String = XcodeJunkScanner.defaultSimctl) {
        self.commands = commands
        self.simctl = simctl
    }

    static let deviceSupport: [(key: String, folder: String)] = [
        ("iosDeviceSupport", "iOS DeviceSupport"), ("tvosDeviceSupport", "tvOS DeviceSupport"),
        ("watchosDeviceSupport", "watchOS DeviceSupport"), ("macosDeviceSupport", "macOS DeviceSupport"),
    ]

    private func x(_ ctx: ScanContext, _ rel: String) -> URL { ctx.resolve("~/Library/Developer/Xcode/\(rel)") }

    private func moduleCaches(_ ctx: ScanContext) -> [(String, URL)] {
        [("org.llvm.clang", ctx.resolve("$DARWIN/org.llvm.clang/ModuleCache")),
         ("org.llvm.clang.\(ctx.userName)", ctx.resolve("$DARWIN/org.llvm.clang.\(ctx.userName)/ModuleCache")),
         ("com.apple.dt.xcode", x(ctx, "DerivedData/ModuleCache"))].filter { exists($0.1) }
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        var scope = RemovalScope(roots: [x(context, "DerivedData"), x(context, "Archives"), x(context, "DocumentationCache")]
                                 + Self.deviceSupport.map { x(context, $0.folder) })
        scope.items = [x(context, "iOS Device Logs"), context.resolve("~/Library/Developer/CoreSimulator/Caches")]
            + moduleCaches(context).map(\.1)
        return scope
    }

    private func leaf(_ name: String, _ url: URL, recommended: Bool, removal: RemovalAction? = nil) -> JunkItem {
        JunkItem(group: group, name: name, url: url, size: sizer.allocatedSize(of: url), isRecommended: recommended,
                 icon: .file(url), removal: removal ?? .delete(url))
    }

    private func subgroup(_ key: String, _ name: String, _ children: [JunkItem], id: String? = nil) -> JunkItem? {
        guard !children.isEmpty else { return nil }
        return JunkItem(id: "xcodeJunk:\(id ?? key)", group: group, name: name, url: nil, size: 0, icon: .symbol("hammer"),
                        children: children, titleKey: "xcode.\(key)")
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        report(ScanProgress(group: group, currentPath: x(context, "").path, bytesFound: 0))
        var out: [JunkItem?] = []
        let dd = visibleChildren(x(context, "DerivedData")).filter { $0.lastPathComponent != "ModuleCache" }.map { u -> JunkItem in
            let name = u.lastPathComponent
            let display = name.range(of: "-", options: .backwards).map { String(name[..<$0.lowerBound]) } ?? name
            return leaf(display, u, recommended: !["ModuleCache.noindex", "SymbolCache.noindex"].contains(name))
        }
        out.append(subgroup("derivedData", "Derived Data", dd))
        let archives = visibleChildren(x(context, "Archives")).flatMap(visibleChildren).compactMap { u -> JunkItem? in
            guard u.pathExtension == "xcarchive", let info = readPlist(u.appendingPathComponent("Info.plist")) else { return nil }
            var name = (info["Name"] as? String) ?? u.deletingPathExtension().lastPathComponent
            let props = info["ApplicationProperties"] as? [String: Any]
            if let v = props?["CFBundleShortVersionString"] as? String { name += " \(v)" }
            if let b = props?["CFBundleVersion"] as? String { name += " (\(b))" }
            if let d = info["CreationDate"] as? Date { name += " - " + d.formatted(date: .abbreviated, time: .shortened) }
            return leaf(name, u, recommended: false)
        }
        out.append(subgroup("archives", "Archives", archives))
        for ds in Self.deviceSupport {
            out.append(subgroup(ds.key, ds.folder, visibleChildren(x(context, ds.folder)).map { leaf($0.lastPathComponent, $0, recommended: false) }))
        }
        let logs = x(context, "iOS Device Logs")
        out.append(subgroup("deviceLogs", "iOS Device Logs", exists(logs) ? [leaf("iOS Device Logs", logs, recommended: true)] : []))
        let simCaches = context.resolve("~/Library/Developer/CoreSimulator/Caches")
        out.append(subgroup("simulatorCaches", "Simulator Caches", exists(simCaches) ? [leaf("Caches", simCaches, recommended: false)] : []))
        out.append(subgroup("moduleCaches", "Module Caches", moduleCaches(context).map { leaf($0.0, $0.1, recommended: false) }))
        out.append(subgroup("documentation", "Documentation Cache",
                            visibleChildren(x(context, "DocumentationCache")).map { leaf("iOS \($0.lastPathComponent)", $0, recommended: false) }))
        out += simulators(context).map { Optional($0) }
        out.append(subgroup("runtimes", "Simulator Runtimes", runtimes(context)))
        // O grupo some quando o total é 0 (xcode-junk.md, "Condição para o grupo aparecer").
        let items = out.compactMap { $0 }
        return items.reduce(0) { $0 + $1.totalSize } > 0 ? items : []
    }

    /// Um subgrupo por runtime (e "Não usados"); só se as ferramentas estiverem atualizadas.
    func simulators(_ ctx: ScanContext) -> [JunkItem] {
        let devicesDir = ctx.resolve("~/Library/Developer/CoreSimulator/Devices")
        guard exists(ctx.resolve("~/Library/Developer/CoreSimulator")), FileManager.default.isExecutableFile(atPath: simctl) || exists(URL(fileURLWithPath: simctl)),
              commands.run("/usr/bin/xcodebuild", ["-checkFirstLaunchStatus"]).status == 0 else { return [] }
        let result = commands.run(simctl, ["list", "devices", "--json"])
        guard result.status == 0, let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return [] }
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        var groups: [(key: String, name: String, items: [JunkItem])] = []
        for runtime in devices.keys.sorted() {
            let isRuntime = runtime.hasPrefix(prefix)
            let name = isRuntime ? Self.runtimeName(String(runtime.dropFirst(prefix.count))) : "Unused"
            let items = devices[runtime]!.compactMap { d -> JunkItem? in
                guard let udid = d["udid"] as? String, let title = d["name"] as? String, d["state"] is String else { return nil }
                let dir = devicesDir.appendingPathComponent(udid)
                guard exists(dir) else { return nil }
                let available = (d["isAvailable"] as? Bool) ?? ((d["availability"] as? String) == "(available)")
                return leaf(title, dir, recommended: !available, removal: .deleteSimulator(udid: udid, simctl: simctl))
            }
            if let i = groups.firstIndex(where: { $0.name == name }) { groups[i].items += items } else { groups.append((runtime, name, items)) }
        }
        return groups.compactMap { subgroup("simulators", $0.name, $0.items, id: "simulators:\($0.key)") }
    }

    /// `iOS-17-2` → `iOS 17.2`.
    static func runtimeName(_ version: String) -> String {
        let parts = version.split(separator: "-")
        guard let platform = parts.first else { return version }
        return parts.count > 1 ? "\(platform) \(parts.dropFirst().joined(separator: "."))" : String(platform)
    }

    func runtimes(_ ctx: ScanContext) -> [JunkItem] {
        guard exists(ctx.resolve("/Library/Developer/CoreSimulator")) else { return [] }
        let result = commands.run(simctl, ["runtime", "list", "-j"])
        guard result.status == 0, let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return json.values.compactMap { r -> JunkItem? in
            guard r["deletable"] as? Bool == true, let id = r["identifier"] as? String,
                  let path = r["runtimeBundlePath"] as? String, exists(URL(fileURLWithPath: path)) else { return nil }
            let u = URL(fileURLWithPath: path)
            return leaf(u.lastPathComponent, u, recommended: false, removal: .deleteRuntime(identifier: id, simctl: simctl))
        }.sorted { $0.name < $1.name }
    }
}
