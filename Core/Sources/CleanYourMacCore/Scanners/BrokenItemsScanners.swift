import Foundation

private func listChildren(_ dir: URL) -> [URL] {
    let real = URL(fileURLWithPath: PathPolicy.realPath(dir.path), isDirectory: true)
    return ((try? FileManager.default.contentsOfDirectory(at: real, includingPropertiesForKeys: nil)) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func isRegularFile(_ u: URL) -> Bool {
    (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
}

// MARK: - Itens de início defeituosos

/// Itens de início da sessão sem alvo e plists do launchd sem executável (docs/re/specs/broken-login-items.md).
public struct BrokenLoginItemsScanner: ScopedScanner {
    public let group = GroupID.brokenLoginItems
    private let loginItems: any LoginItemsSource
    private let inventory: any AppInventory
    private let sizer = FileSizer()

    static let folders = ["~/Library/LaunchAgents", "~/Library/LaunchDaemons", "~/Library/PrivilegedHelperTools",
                          "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools"]

    public init(loginItems: any LoginItemsSource = SystemLoginItems(), inventory: any AppInventory = FolderAppInventory()) {
        self.loginItems = loginItems
        self.inventory = inventory
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(roots: Self.folders.map(context.resolve))
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        var out: [JunkItem] = []
        for entry in loginItems.entries(context) {
            if let url = entry.url, FileManager.default.fileExists(atPath: url.path) { continue }
            let name = entry.name ?? entry.url.map { FileManager.default.displayName(atPath: $0.path) }
                ?? entry.url?.deletingPathExtension().lastPathComponent ?? "?"
            out.append(JunkItem(id: "brokenLoginItems:session:\(entry.url?.path ?? name)", group: group, name: name,
                                url: entry.url, size: 0, isRecommended: entry.url != nil, icon: .symbol("app.dashed"),
                                removal: .removeSessionLoginItem(name: entry.name, url: entry.url)))
        }
        let helpers = Set(inventory.apps(context).flatMap(Self.privilegedExecutables))
        var seen = Set<String>()
        for folder in Self.folders {
            let dir = context.resolve(folder)
            report(ScanProgress(group: group, currentPath: dir.path, bytesFound: 0))
            for file in listChildren(dir) where file.pathExtension == "plist" && isRegularFile(file) {
                try Task.checkCancellation()
                guard seen.insert(file.path).inserted,
                      !file.lastPathComponent.hasPrefix("com.apple."),
                      access(file.path, R_OK) == 0,
                      isBroken(file, helpers: helpers, context: context) else { continue }
                let label = file.deletingPathExtension().lastPathComponent
                let helper = context.resolve("/Library/PrivilegedHelperTools/\(label)")
                out.append(JunkItem(group: group, name: file.lastPathComponent, url: file, size: sizer.allocatedSize(of: file),
                                    isRecommended: true, icon: .file(file),
                                    removal: .removeLaunchdItem(plist: file, helper: FileManager.default.fileExists(atPath: helper.path) ? helper : nil)))
            }
        }
        return out
    }

    static func privilegedExecutables(_ app: InstalledApp) -> [String] {
        guard let data = try? Data(contentsOf: app.url.appendingPathComponent("Contents/Info.plist")),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let execs = dict["SMPrivilegedExecutables"] as? [String: Any] else { return [] }
        return Array(execs.keys)
    }

    /// Critério de "quebrado" da spec (passos 1–9).
    func isBroken(_ plist: URL, helpers: Set<String>, context: ScanContext) -> Bool {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return true }
        var exe = dict["Program"] as? String
        if exe == nil, let args = dict["ProgramArguments"] as? [String], let first = args.first { exe = first }
        guard var path = exe, !path.isEmpty else { return true }
        if let wd = dict["WorkingDirectory"] as? String, !path.hasPrefix("/") {
            path = (wd as NSString).appendingPathComponent(path)
        }
        // Nome sem caminho (ex.: "sh", "python3"): o launchd procura no PATH; na dúvida, não está quebrado.
        if !path.contains("/") && !path.hasPrefix("~") { return false }
        if path.hasPrefix("~/") || path == "~" { path = context.resolve(path).path }
        path = (path as NSString).standardizingPath
        // Executável num volume desmontado: o volume pode voltar; não está quebrado.
        let comps = (path as NSString).pathComponents
        if comps.count > 2, comps[1] == "Volumes", !FileManager.default.fileExists(atPath: "/Volumes/" + comps[2]) { return false }
        // Área sem permissão de leitura acima do executável: sem admin, conservador (não quebrado).
        var ancestor = (path as NSString).deletingLastPathComponent
        while !ancestor.isEmpty, ancestor != "/" {
            if FileManager.default.fileExists(atPath: ancestor), access(ancestor, R_OK | X_OK) != 0 { return false }
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        if FileManager.default.fileExists(atPath: path) { return false }
        if helpers.contains((path as NSString).lastPathComponent) { return false }
        return true
    }
}

// MARK: - Preferências defeituosas

/// Plists em `~/Library/Preferences` que não podem ser interpretados (docs/re/specs/broken-preferences.md).
public struct BrokenPreferencesScanner: ScopedScanner {
    public let group = GroupID.brokenPreferences
    private let sizer = FileSizer()

    public init() {}

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(roots: [context.resolve("~/Library/Preferences")])
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        let dir = context.resolve("~/Library/Preferences")
        report(ScanProgress(group: group, currentPath: dir.path, bytesFound: 0))
        return listChildren(dir).compactMap { file in
            guard isBroken(file) else { return nil }
            return JunkItem(group: group, name: file.deletingPathExtension().lastPathComponent, url: file,
                            size: sizer.allocatedSize(of: file), isRecommended: true, icon: .file(file),
                            removal: .removePreference(file))
        }
    }

    func isBroken(_ file: URL) -> Bool {
        let name = file.lastPathComponent
        guard !name.hasPrefix("."), file.pathExtension.lowercased() == "plist", !file.path.contains(".lockfile"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              ((attrs[.size] as? NSNumber)?.int64Value ?? 0) > 0,
              (attrs[.immutable] as? Bool) != true,
              let stream = InputStream(url: file) else { return false }
        stream.open()
        defer { stream.close() }
        guard stream.streamStatus == .open, stream.streamError == nil else { return false }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let data = try? Data(contentsOf: file) else { return false }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: &format) else { return true }
        return !PropertyListSerialization.propertyList(plist, isValidFor: format)
    }
}
