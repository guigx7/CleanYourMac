import Foundation

/// Um item de início desativado por nós (login-items.md §7.3): guardado para recolocar na lista de sessão.
public struct DisabledLoginItem: Codable, Hashable, Sendable {
    public let name: String
    public let path: String
    public let bundleIdentifier: String?
    public let disabledAt: Date

    public init(name: String, path: String, bundleIdentifier: String?, disabledAt: Date) {
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.disabledAt = disabledAt
    }
}

/// `~/Library/Application Support/CleanYourMac/disabled-login-items.json`.
public struct DisabledLoginItemsStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: DisabledLoginItemsStore {
        DisabledLoginItemsStore(url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CleanYourMac/disabled-login-items.json"))
    }

    public func load() -> [DisabledLoginItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode([DisabledLoginItem].self, from: data)) ?? []
    }

    public func save(_ items: [DisabledLoginItem]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        try e.encode(items).write(to: url, options: .atomic)
    }
}

/// Itens de início (lista de sessão) e em segundo plano (plists do launchd), como em login-items.md e
/// background-items.md §7.1.
public struct StartupItemsScanner: Sendable {
    private let loginItems: any LoginItemsSource
    private let commands: any CommandRunner
    private let disabledRecord: DisabledLoginItemsStore
    private let displayName: @Sendable (URL) -> String

    public init(loginItems: any LoginItemsSource = SystemLoginItems(), commands: any CommandRunner = SystemCommandRunner(),
                disabledRecord: DisabledLoginItemsStore = .standard,
                displayName: @escaping @Sendable (URL) -> String = { FileManager.default.displayName(atPath: $0.path) }) {
        self.loginItems = loginItems
        self.commands = commands
        self.disabledRecord = disabledRecord
        self.displayName = displayName
    }

    public func items(_ context: ScanContext) -> [StartupItem] {
        (sessionItems(context) + launchdItems(context))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Lista de sessão

    private func sessionItems(_ context: ScanContext) -> [StartupItem] {
        var seen = Set<String>()
        var out: [StartupItem] = []
        for entry in loginItems.entries(context) {
            guard let url = entry.url, let item = sessionItem(url, state: .enabled), seen.insert(url.path).inserted else { continue }
            out.append(item)
        }
        for record in disabledRecord.load() where !seen.contains(record.path) {
            guard let item = sessionItem(URL(fileURLWithPath: record.path), state: .disabled) else { continue }
            seen.insert(record.path)
            out.append(item)
        }
        return out
    }

    /// Só apps que existem; nunca da Apple nem o próprio CleanYourMac.
    private func sessionItem(_ app: URL, state: StartupItemState) -> StartupItem? {
        var isDir: ObjCBool = false
        guard app.pathExtension == "app", FileManager.default.fileExists(atPath: app.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let bundleID = Self.bundleID(of: app)
        guard !Self.isExcluded(bundleID ?? "") else { return nil }
        return StartupItem(kind: .sessionLoginItem, name: displayName(app), program: app, ownerApp: app,
                           ownerBundleID: bundleID, state: state)
    }

    // MARK: - launchd

    private func launchdItems(_ context: ScanContext) -> [StartupItem] {
        let folders: [(URL, StartupItemKind)] = [
            (context.home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (context.root.appendingPathComponent("Library/LaunchAgents"), .systemAgent),
            (context.root.appendingPathComponent("Library/LaunchDaemons"), .systemDaemon),
        ]
        let gui = Self.parseDisabled(commands.run("/bin/launchctl", ["print-disabled", "gui/\(context.uid)"]).output)
        let system = Self.parseDisabled(commands.run("/bin/launchctl", ["print-disabled", "system"]).output)
        var out: [StartupItem] = []
        for (folder, kind) in folders {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
            for file in names where (file as NSString).pathExtension == "plist" {
                let url = folder.appendingPathComponent(file)
                var st = stat()
                guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
                let dict = (NSDictionary(contentsOf: url) as? [String: Any]) ?? [:]
                let label = dict["Label"] as? String
                guard !Self.isExcluded((file as NSString).deletingPathExtension), !Self.isExcluded(label ?? "") else { continue }
                let program = Self.program(dict)
                let owner = Self.ownerApp(dict)
                let overrides = kind == .systemDaemon ? system : gui
                let disabled = label.flatMap { overrides[$0] } ?? (dict["Disabled"] as? Bool ?? false)
                out.append(StartupItem(kind: kind, name: displayName(owner ?? url), label: label, plist: url,
                                       program: program.map { URL(fileURLWithPath: $0) }, ownerApp: owner,
                                       ownerBundleID: owner.flatMap(Self.bundleID), state: disabled ? .disabled : .enabled))
            }
        }
        return out
    }

    /// `com.apple.*`, o próprio CleanYourMac e os ajudantes da MacPaw (background-items.md §7.1).
    static func isExcluded(_ id: String) -> Bool {
        let l = id.lowercased()
        return l.hasPrefix("com.apple.") || l.hasPrefix("io.github.guigx7.cleanyourmac") || l.hasPrefix("com.macpaw.")
    }

    static func program(_ dict: [String: Any]) -> String? {
        (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
    }

    /// Primeiro `.app` em `ProgramArguments`, depois em `Program`, cortado logo após o primeiro ".app".
    static func ownerApp(_ dict: [String: Any]) -> URL? {
        let candidates = ((dict["ProgramArguments"] as? [String]) ?? []) + [(dict["Program"] as? String)].compactMap { $0 }
        for c in candidates {
            guard let r = c.range(of: ".app") else { continue }
            let path = String(c[..<r.upperBound])
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    static func bundleID(of app: URL) -> String? {
        (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleIdentifier"] as? String
    }

    /// `launchctl print-disabled`: `"<label>" => disabled|enabled` (ou true/false); rótulo → desativado.
    static func parseDisabled(_ output: String) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("\""), let arrow = s.range(of: "\" => ") else { continue }
            let label = String(s[s.index(after: s.startIndex)..<arrow.lowerBound])
            switch s[arrow.upperBound...].trimmingCharacters(in: .whitespaces) {
            case "disabled", "true": out[label] = true
            case "enabled", "false": out[label] = false
            default: break
            }
        }
        return out
    }
}
