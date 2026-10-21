import Foundation

/// Recibos de pacote instalados (`pkgutil`).
public protocol ReceiptSource: Sendable {
    func packages() -> [String]
    func info(_ id: String) -> (volume: String, location: String)?
    /// Caminhos relativos ao `location` do recibo.
    func files(_ id: String) -> [String]
}

public struct PkgutilReceipts: ReceiptSource {
    private let commands: any CommandRunner

    public init(commands: any CommandRunner = SystemCommandRunner()) {
        self.commands = commands
    }

    public func packages() -> [String] {
        commands.run("/usr/sbin/pkgutil", ["--pkgs"]).output.split(separator: "\n").map(String.init)
    }

    public func info(_ id: String) -> (volume: String, location: String)? {
        let r = commands.run("/usr/sbin/pkgutil", ["--pkg-info", id])
        guard r.status == 0 else { return nil }
        var volume = "", location = ""
        for line in r.output.split(separator: "\n") {
            if line.hasPrefix("volume:") { volume = line.dropFirst(7).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("location:") { location = line.dropFirst(9).trimmingCharacters(in: .whitespaces) }
        }
        return (volume, location)
    }

    public func files(_ id: String) -> [String] {
        commands.run("/usr/sbin/pkgutil", ["--files", id]).output.split(separator: "\n").map(String.init)
    }
}

/// Arquivos de um app fora do bundle, por `ResourceKind` (docs/re/specs/apps/related-files.md, regra forte).
/// O bundle e as cópias (`binaries`) ficam com o `UninstallerScanner`.
public struct RelatedFilesFinder: Sendable {
    private let loginItems: any LoginItemsSource
    private let receipts: any ReceiptSource
    /// O ajudante está aprovado: itens fora da pasta do usuário (e recibos) já vêm marcados.
    private let privilegedAvailable: Bool
    private let rootForReceipts: URL?
    private let sizer = FileSizer()

    public init(loginItems: any LoginItemsSource = SystemLoginItems(), receipts: any ReceiptSource = PkgutilReceipts(),
                privilegedAvailable: Bool = false, rootForReceipts: URL? = nil) {
        self.loginItems = loginItems
        self.receipts = receipts
        self.privilegedAvailable = privilegedAvailable
        self.rootForReceipts = rootForReceipts
    }

    // MARK: - Casamento

    enum Match { case exactID, prefixID, name }

    /// `id(x)` e `nome(x)` da spec. `isFile`: compara o nome sem a extensão.
    static func match(_ child: String, isFile: Bool, app: AppRecord, idOnly: Bool = false) -> Match? {
        let base = (isFile ? (child as NSString).deletingPathExtension : child).lowercased()
        let id = app.bundleID.lowercased()
        if base == id { return .exactID }
        if base.hasPrefix(id + "."), !base.dropFirst(id.count + 1).contains(where: \.isNumber) { return .prefixID }
        let name = app.matchName.lowercased()
        if !idOnly, name.count >= 3, base == name { return .name }
        return nil
    }

    /// O item pertence a `app` se só ele casa, ou se ele é o único casamento exato por bundle ID.
    static func belongs(_ child: String, isFile: Bool, to app: AppRecord, installed: [AppRecord], idOnly: Bool = false) -> Bool {
        guard let mine = match(child, isFile: isFile, app: app, idOnly: idOnly) else { return false }
        if child.lowercased().hasPrefix("com.apple."), !app.bundleID.lowercased().hasPrefix("com.apple.") { return false }
        let others = installed.filter { $0.id != app.id && $0.kind == .application }.compactMap { match(child, isFile: isFile, app: $0) }
        if others.isEmpty { return true }
        return mine == .exactID && !others.contains(.exactID)
    }

    // MARK: - Busca

    private struct Candidate {
        let url: URL
        let kind: ResourceKind
        let removal: RemovalAction
        var size: Int64?
        var selected: Bool?
        var standalone = false
    }

    /// `idOnly`: só casamento por bundle ID (apps fantasmas das sobras: o nome deles não é confiável).
    public func files(for app: AppRecord, installed: [AppRecord], context: ScanContext, idOnly: Bool = false) -> [RelatedFile] {
        let fm = FileManager.default
        let home = PathPolicy.realPath(context.home.path)
        var out: [Candidate] = []

        func children(_ template: String) -> [(URL, Bool)] { children(at: context.resolve(template)) }
        func children(at dir: URL) -> [(URL, Bool)] {
            let real = URL(fileURLWithPath: PathPolicy.realPath(dir.path))
            return ((try? fm.contentsOfDirectory(at: real, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])) ?? [])
                .compactMap { u in
                    let v = try? u.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                    guard v?.isSymbolicLink != true else { return nil }
                    return (u, v?.isDirectory != true)
                }
                .sorted { $0.0.lastPathComponent < $1.0.lastPathComponent }
        }
        func add(_ dirs: [String], _ kind: ResourceKind, filter: (String, Bool) -> Bool = { _, _ in true }) {
            add(dirs.map(context.resolve), kind, filter: filter)
        }
        func add(_ dirs: [URL], _ kind: ResourceKind, filter: (String, Bool) -> Bool = { _, _ in true }) {
            for d in dirs {
                for (u, isFile) in children(at: d) where filter(u.lastPathComponent, isFile)
                    && Self.belongs(u.lastPathComponent, isFile: isFile, to: app, installed: installed, idOnly: idOnly) {
                    out.append(Candidate(url: u, kind: kind, removal: .moveToTrash(u)))
                }
            }
        }

        // Contêiner: só o do bundle ID exato, pasta real.
        let container = context.resolve("~/Library/Containers/\(app.bundleID)")
        if (try? container.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])).map({ $0.isSymbolicLink != true && $0.isDirectory == true }) == true {
            out.append(Candidate(url: URL(fileURLWithPath: PathPolicy.realPath(container.path)), kind: .container,
                                 removal: .moveToTrash(container)))
        }

        out += launchdItems(app, context: context)
        for entry in loginItems.entries(context) where entry.url.map({ PathPolicy.realPath($0.path) }) == PathPolicy.realPath(app.url.path) {
            out.append(Candidate(url: app.url, kind: .loginItems, removal: .removeSessionLoginItem(name: entry.name, url: entry.url),
                                 size: 0, standalone: true))
        }

        add(["~/Library/Preferences", "/Library/Preferences"], .preferences) { name, isFile in
            isFile ? name.lowercased().hasSuffix(".plist") && Self.match(name, isFile: true, app: app) != .name
                : Self.match(name, isFile: false, app: app) == .name
        }

        add(["~/Library/Logs", "/Library/Logs"], .logs)
        // Nome de casamento exato (com maiúsculas): "Chrome_" não pega "chrome_crashpad_handler_…".
        let prefix = app.matchName + "_"
        for (dir, exts) in [("~/Library/Logs/DiagnosticReports", ["crash", "diag", "hang", "spin"]),
                            ("/Library/Logs/DiagnosticReports", ["crash", "diag", "hang", "spin"]),
                            ("~/Library/Application Support/CrashReporter", ["plist"])] {
            for (u, isFile) in children(dir) where isFile && u.lastPathComponent.hasPrefix(prefix)
                && exts.contains(u.pathExtension.lowercased()) {
                out.append(Candidate(url: u, kind: .logs, removal: .moveToTrash(u)))
            }
        }

        let temp = context.darwinUserCacheDir.deletingLastPathComponent().appendingPathComponent("T")
        add(["~/Library/Application Support", "/Library/Application Support", "~/Library/Caches"].map(context.resolve)
            + [context.darwinUserCacheDir, temp], .supportingFiles)

        add(["~/Library", "/Library"], .userData) { name, _ in !Self.standardLibraryFolders.contains(name.lowercased()) }

        out += plugins(app, context: context)

        for help in [context.resolve("/Library/Documentation/Applications/\(app.matchName)"),
                     context.resolve("~/Library/Preferences/SDMHelpData/Other/\(app.bundleID).help")]
        where fm.fileExists(atPath: help.path) && (try? help.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true {
            out.append(Candidate(url: help, kind: .help, removal: .moveToTrash(help)))
        }

        let dmg = context.resolve("~/Downloads/\(app.matchName).dmg")
        var st = stat()
        if lstat(dmg.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG {
            let real = URL(fileURLWithPath: PathPolicy.realPath(dmg.path))
            out.append(Candidate(url: real, kind: .installers, removal: .deleteDiskImage(real), selected: false))
        }

        out += receiptItems(app, context: context)

        // O item de fora absorve o de dentro; um caminho fica com o primeiro tipo que o pegou.
        var kept: [Candidate] = []
        for c in out {
            if c.standalone { kept.append(c); continue }
            let p = PathPolicy.realPath(c.url.path)
            if kept.contains(where: { !$0.standalone && (PathPolicy.realPath($0.url.path) == p || p.hasPrefix(PathPolicy.realPath($0.url.path) + "/")) }) { continue }
            kept.removeAll { !$0.standalone && PathPolicy.realPath($0.url.path).hasPrefix(p + "/") }
            kept.append(c)
        }
        // Pastas do usuário: a home e as do Darwin (C e T, em /var/folders).
        let darwin = PathPolicy.realPath(context.darwinUserCacheDir.deletingLastPathComponent().path)
        return kept.map { c in
            let real = PathPolicy.realPath(c.url.path)
            let inHome = real.hasPrefix(home + "/") || real.hasPrefix(darwin + "/")
            let selected = c.selected ?? (inHome || privilegedAvailable)
            return RelatedFile(url: c.url, kind: c.kind, size: c.size ?? sizer.allocatedSize(of: c.url), isSelected: selected,
                               removal: c.removal)
        }
    }

    /// Plists do launchd com vínculo exato (nome e Label, AssociatedBundleIdentifiers ou SMPrivilegedExecutables).
    private func launchdItems(_ app: AppRecord, context: ScanContext) -> [Candidate] {
        let info = InfoPlist.read(app.url)
        let privileged = Set(((info["SMPrivilegedExecutables"] as? [String: Any]) ?? [:]).keys)
        var out: [Candidate] = []
        for (template, domain) in [("~/Library/LaunchAgents", LaunchdDomain.user), ("/Library/LaunchAgents", .system),
                                   ("/Library/LaunchDaemons", .system)] {
            let dir = URL(fileURLWithPath: PathPolicy.realPath(context.resolve(template).path))
            for u in ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .sorted(by: { $0.path < $1.path }) where u.pathExtension == "plist" {
                guard (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true,
                      let data = try? Data(contentsOf: u),
                      let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                let name = u.deletingPathExtension().lastPathComponent
                let label = dict["Label"] as? String ?? ""
                guard !name.hasPrefix("com.apple."), !label.hasPrefix("com.apple.") else { continue }
                let associated = (dict["AssociatedBundleIdentifiers"] as? [String]) ?? ((dict["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? [])
                let byName = name == app.bundleID && label == app.bundleID
                let byHelper = privileged.contains(name) && label == name
                guard byName || associated.contains(app.bundleID) || byHelper else { continue }
                out.append(Candidate(url: u, kind: .loginItems, removal: .unloadAndTrash(plist: u, domain: domain)))
                if byHelper {
                    let tool = context.resolve("/Library/PrivilegedHelperTools/\(name)")
                    if Self.isRealItem(tool) {
                        out.append(Candidate(url: tool, kind: .loginItems, removal: .moveToTrash(tool)))
                    }
                }
            }
        }
        return out
    }

    /// Plug-ins instalados fora do app com o mesmo nome e bundle ID de um que vem dentro dele.
    private func plugins(_ app: AppRecord, context: ScanContext) -> [Candidate] {
        let fm = FileManager.default
        var out: [Candidate] = []
        for folder in ["QuickLook", "Spotlight", "PreferencePanes", "Internet Plug-Ins", "Services", "Screen Savers"] {
            let inside = app.url.appendingPathComponent("Contents/Library/\(folder)")
            for pkg in (try? fm.contentsOfDirectory(at: inside, includingPropertiesForKeys: nil)) ?? [] {
                let id = InfoPlist.read(pkg)["CFBundleIdentifier"] as? String
                for base in ["~/Library/\(folder)", "/Library/\(folder)"] {
                    let installed = context.resolve(base).appendingPathComponent(pkg.lastPathComponent)
                    guard let id, (try? installed.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false,
                          InfoPlist.read(installed)["CFBundleIdentifier"] as? String == id else { continue }
                    out.append(Candidate(url: installed, kind: .plugins, removal: .moveToTrash(installed)))
                }
            }
        }
        let pdf = context.resolve("~/Library/PDF Services/\(app.matchName)")
        if Self.isRealItem(pdf) { out.append(Candidate(url: pdf, kind: .plugins, removal: .moveToTrash(pdf))) }
        return out
    }

    /// Recibo do próprio app: id = bundle ID (ou com sufixo "."), volume "/", e a lista de arquivos inclui o bundle.
    private func receiptItems(_ app: AppRecord, context: ScanContext) -> [Candidate] {
        let id = app.bundleID.lowercased()
        let root = PathPolicy.realPath((rootForReceipts ?? context.root).path)
        let appPath = PathPolicy.realPath(app.url.path)
        var out: [Candidate] = []
        for pkg in receipts.packages().sorted() {
            let p = pkg.lowercased()
            guard p == id || p.hasPrefix(id + "."), !p.hasPrefix("com.apple."), HelperExecutor.isSafeIdentifier(pkg),
                  let info = receipts.info(pkg), info.volume == "/" else { continue }
            let location = (root as NSString).appendingPathComponent(info.location)
            let relative = appPath.hasPrefix(PathPolicy.realPath(location) + "/")
                ? String(appPath.dropFirst(PathPolicy.realPath(location).count + 1)) : nil
            guard let relative, receipts.files(pkg).contains(relative) else { continue }
            out.append(Candidate(url: app.url.appendingPathComponent("receipt:\(pkg)"), kind: .other, removal: .forgetReceipt(pkg),
                                 size: 0, selected: privilegedAvailable, standalone: true))
        }
        return out
    }

    /// Existe e não é symlink (o link nunca vira item: a remoção levaria o destino ao helper).
    static func isRealItem(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0 && (st.st_mode & S_IFMT) != S_IFLNK
    }

    /// Pastas padrão de `~/Library` e `/Library` (instalação limpa do macOS): nunca viram "Dados do Usuário".
    static let standardLibraryFolders: Set<String> = Set([
        "Accessibility", "Accounts", "Address Book Plug-Ins", "Apple", "Application Scripts", "Application Support", "Assistants",
        "Audio", "Autosave Information", "Biome", "Bundles", "Caches", "Calendars", "CallServices", "CloudStorage", "ColorPickers",
        "ColorSync", "Colors", "Components", "Compositions", "ContainerManager", "Containers", "Contextual Menu Items", "Contacts",
        "Cookies", "CoreAnalytics", "CoreData", "CoreFollowUp", "CoreMediaIO", "Daemon Containers", "DataAccess",
        "DataDeliveryServices", "DES", "Desktop Pictures", "Developer", "DirectoryServices", "Documentation", "DoNotDisturb",
        "DriverExtensions", "DuetExpertCenter", "Extensions", "Favorites", "FileProvider", "Filesystems", "Finance",
        "FontCollections", "Fonts", "Frameworks", "FrontBoard", "GameKit", "GPUBundles", "Graphics", "Group Containers", "HomeKit",
        "HTTPStorages", "IdentityServices", "Image Capture", "Input Methods", "Intents", "Internet Plug-Ins", "Java", "Keyboard",
        "Keyboard Layouts", "KeyboardServices", "Keychains", "LanguageModeling", "LaunchAgents", "LaunchDaemons", "Logs", "Mail",
        "Messages", "Metadata", "Mobile Documents", "Modem Scripts", "News", "OpenDirectory", "Passes", "PDF Services", "Perl",
        "Personas", "Photos", "PreferencePanes", "Preferences", "Printers", "PrivateCloudCompute", "PrivilegedHelperTools",
        "Python", "QuickLook", "Receipts", "Reminders", "ResponseKit", "Safari", "SafariSafeBrowsing", "Saved Application State",
        "Screen Savers", "Scripts", "Security", "Services", "Sharing", "Shortcuts", "Sounds", "Spelling", "Spotlight",
        "StartupItems", "StatusKit", "Suggestions", "SyncedPreferences", "SystemExtensions", "SystemMigration", "SystemProfiler",
        "Translation", "Trial", "UnifiedAssetFramework", "Updates", "User Pictures", "User Template", "Video", "Weather", "WebKit",
        "Workflows",
    ].map { $0.lowercased() })
}
