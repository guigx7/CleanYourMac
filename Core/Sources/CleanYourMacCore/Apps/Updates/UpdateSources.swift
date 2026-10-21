import Foundation

// Fontes públicas do Atualizador (docs/re/specs/apps/updater.md §Fontes).

private func osString(_ v: OperatingSystemVersion) -> String {
    v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
}

private func verdict(installed: String?, available: String, homebrew: Bool = false, make: () -> AppUpdate) -> UpdateVerdict {
    guard let installed, let newer = Version.isUpdate(installed: installed, available: available, homebrew: homebrew) else {
        return .unknown
    }
    return newer ? .update(make()) : .current
}

// MARK: - F1: App Store

public struct AppStoreSource: UpdateSource {
    public let kind = UpdateSourceKind.appStore
    private let country: String
    private let systemVersion: OperatingSystemVersion
    private let batch = 50

    public init(country: String = (Locale.current.region?.identifier ?? "us").lowercased(),
                systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) {
        self.country = country
        self.systemVersion = systemVersion
    }

    public func check(_ apps: [AppRecord], fetcher: any HTTPFetcher) async -> [String: UpdateVerdict] {
        let candidates = apps.filter { $0.store == .appStore }
        guard !candidates.isEmpty else { return [:] }
        var found: [String: [String: Any]] = [:]
        var missing = candidates
        for cc in country == "us" ? ["us"] : [country, "us"] where !missing.isEmpty {
            for start in stride(from: 0, to: missing.count, by: batch) {
                let chunk = missing[start..<min(start + batch, missing.count)]
                let ids = chunk.map(\.bundleID).joined(separator: ",")
                guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(ids)&entity=macSoftware&country=\(cc)"),
                      let data = try? await fetcher.get(url, timeout: .seconds(10)),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else { continue }
                for r in results {
                    if let id = (r["bundleId"] as? String)?.lowercased(), found[id] == nil { found[id] = r }
                }
            }
            missing = missing.filter { found[$0.bundleID.lowercased()] == nil }
        }
        var out: [String: UpdateVerdict] = [:]
        for app in candidates {
            guard let r = found[app.bundleID.lowercased()] else { out[app.id] = .unknown; continue }
            out[app.id] = evaluate(app, r)
        }
        return out
    }

    private func evaluate(_ app: AppRecord, _ r: [String: Any]) -> UpdateVerdict {
        // Só apps de Mac: um resultado de iOS (`software`) não é confiável.
        guard (r["kind"] as? String) == "mac-software", let version = r["version"] as? String else { return .unknown }
        if let minOS = r["minimumOsVersion"] as? String,
           Version.compare(osString(systemVersion), minOS) == .orderedAscending { return .current }
        let trackID = (r["trackId"] as? NSNumber)?.int64Value
        let store = trackID.flatMap { URL(string: "macappstore://apps.apple.com/app/id\($0)") }
        let web = (r["trackViewUrl"] as? String).flatMap(URL.init(string:))
        guard let primary = store ?? web else { return .unknown }
        return verdict(installed: app.version, available: version) {
            AppUpdate(id: app.bundleID, appID: app.id, name: app.name, source: .appStore,
                      installedVersion: app.version ?? "", availableVersion: version,
                      releaseDate: (r["currentVersionReleaseDate"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
                      size: (r["fileSizeBytes"] as? String).flatMap { Int64($0) } ?? (r["fileSizeBytes"] as? NSNumber)?.int64Value,
                      notes: (r["releaseNotes"] as? String).map(AppcastParser.plainText),
                      action: .openAppStore(primary, fallback: store == nil ? nil : web))
        }
    }
}

// MARK: - F2: feed do app (Sparkle)

public struct SparkleSource: UpdateSource {
    public let kind = UpdateSourceKind.sparkle
    private let home: URL
    private let systemVersion: OperatingSystemVersion
    private let parallel = 4

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) {
        self.home = home
        self.systemVersion = systemVersion
    }

    /// URL do feed: preferências do app (ou `SUDefaultsDomain`) antes do Info.plist; só http(s).
    func feedURL(_ app: AppRecord) -> URL? {
        let info = InfoPlist.read(app.url)
        let domain = (info["SUDefaultsDomain"] as? String) ?? app.bundleID
        let prefs = home.appendingPathComponent("Library/Preferences/\(domain).plist")
        var candidates: [String] = []
        if let data = try? Data(contentsOf: prefs),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let s = dict["SUFeedURL"] as? String { candidates.append(s) }
        if let s = app.feedURL?.absoluteString { candidates.append(s) }
        if let s = info["SUFeedURL"] as? String { candidates.append(s) }
        return candidates.lazy.compactMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
            .first { $0.scheme == "https" || $0.scheme == "http" }
    }

    public func check(_ apps: [AppRecord], fetcher: any HTTPFetcher) async -> [String: UpdateVerdict] {
        let jobs = apps.filter { $0.store != .appStore }.compactMap { app in feedURL(app).map { (app, $0) } }
        var out: [String: UpdateVerdict] = [:]
        await withTaskGroup(of: (String, UpdateVerdict).self) { group in
            var pending = jobs[...]
            func next() {
                guard let (app, url) = pending.popFirst() else { return }
                group.addTask { (app.id, await self.evaluate(app, feed: url, fetcher: fetcher)) }
            }
            for _ in 0..<parallel { next() }
            for await (id, v) in group {
                out[id] = v
                next()
            }
        }
        return out
    }

    private func evaluate(_ app: AppRecord, feed: URL, fetcher: any HTTPFetcher) async -> UpdateVerdict {
        guard let data = try? await fetcher.get(feed, timeout: .seconds(10)),
              let items = try? AppcastParser.parse(data),
              let best = AppcastParser.best(items, systemVersion: systemVersion, arch: Machine.arch) else { return .unknown }
        let build = app.build ?? (InfoPlist.read(app.url)["CFBundleVersion"] as? String)
        return verdict(installed: build, available: best.version) {
            AppUpdate(id: app.bundleID, appID: app.id, name: app.name, source: .sparkle,
                      installedVersion: app.version ?? build ?? "", availableVersion: best.shortVersion ?? best.version,
                      releaseDate: best.date, size: best.length, notes: best.notes,
                      action: .openApp(app.url, notes: best.notesURL ?? best.link),
                      downloadURL: best.downloadURL, expectedTeamID: app.teamID, isCritical: best.isCritical)
        }
    }
}

// MARK: - F3: Homebrew

public struct HomebrewSource: UpdateSource {
    public let kind = UpdateSourceKind.homebrew
    public static let catalogURL = URL(string: "https://formulae.brew.sh/api/cask.json")!
    public static let defaultCaskrooms = [URL(fileURLWithPath: "/opt/homebrew/Caskroom"), URL(fileURLWithPath: "/usr/local/Caskroom")]
    private let caskrooms: [URL]
    /// Pasta do cache do catálogo (24 h); nil = sem cache.
    private let cacheDir: URL?

    public init(caskrooms: [URL] = HomebrewSource.defaultCaskrooms,
                cacheDir: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("io.github.guigx7.CleanYourMac")) {
        self.caskrooms = caskrooms
        self.cacheDir = cacheDir
    }

    struct Cask {
        let token: String
        let version: String
        let apps: [String]
        let autoUpdates: Bool
        let homepage: URL?
        let unusable: Bool
    }

    /// Versão instalada pelo `brew` (pasta do Caskroom), se o app tiver um cask instalado.
    func caskroomVersion(token: String) -> String? {
        for room in caskrooms {
            let dir = room.appendingPathComponent(token)
            guard let versions = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            let real = versions.filter { !$0.hasPrefix(".") }
            if let best = real.max(by: { Version.compare(Version.homebrewForm($0), Version.homebrewForm($1)) == .orderedAscending }) {
                return best
            }
        }
        return nil
    }

    func catalog(fetcher: any HTTPFetcher) async -> [Cask]? {
        let cache = cacheDir?.appendingPathComponent("cask.json")
        var data: Data?
        if let cache, let attrs = try? FileManager.default.attributesOfItem(atPath: cache.path),
           let modified = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 86_400 {
            data = try? Data(contentsOf: cache)
        }
        if data == nil, let fresh = try? await fetcher.get(Self.catalogURL, timeout: .seconds(20)) {
            data = fresh
            if let cache {
                try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fresh.write(to: cache)
            }
        }
        guard let data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return list.compactMap { c in
            guard let token = c["token"] as? String, let version = c["version"] as? String else { return nil }
            var apps: [String] = []
            for artifact in (c["artifacts"] as? [Any]) ?? [] {
                guard let dict = artifact as? [String: Any], let entries = dict["app"] as? [Any] else { continue }
                for e in entries {
                    if let s = e as? String { apps.append(s) }
                    if let d = e as? [String: Any], let target = d["target"] as? String { apps.append((target as NSString).lastPathComponent) }
                }
            }
            return Cask(token: token, version: version, apps: apps, autoUpdates: (c["auto_updates"] as? Bool) == true,
                        homepage: (c["homepage"] as? String).flatMap(URL.init(string:)),
                        unusable: (c["deprecated"] as? Bool) == true || (c["disabled"] as? Bool) == true || version == "latest")
        }
    }

    public func check(_ apps: [AppRecord], fetcher: any HTTPFetcher) async -> [String: UpdateVerdict] {
        await checkDetailed(apps, fetcher: fetcher).verdicts
    }

    /// Vereditos e os apps instalados pelo `brew` (cask casado com pasta no Caskroom), que têm o Homebrew como fonte principal.
    public func checkDetailed(_ apps: [AppRecord], fetcher: any HTTPFetcher) async -> (verdicts: [String: UpdateVerdict], inCaskroom: Set<String>) {
        let candidates = apps.filter { $0.store != .appStore }
        guard !candidates.isEmpty, let casks = await catalog(fetcher: fetcher) else {
            return (Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, UpdateVerdict.unknown) }), [])
        }
        var inCaskroom = Set<String>()
        var byApp: [String: [Cask]] = [:]
        for c in casks { for a in Set(c.apps) { byApp[a, default: []].append(c) } }
        var out: [String: UpdateVerdict] = [:]
        for app in candidates {
            // Nome ambíguo (dois casks com o mesmo .app) não casa.
            guard let matches = byApp[app.url.lastPathComponent], matches.count == 1, let cask = matches.first,
                  !cask.autoUpdates, !cask.unusable else { continue }
            let roomVersion = caskroomVersion(token: cask.token)
            if roomVersion != nil { inCaskroom.insert(app.id) }
            let shown = String(cask.version.split(separator: ",").first ?? Substring(cask.version))
            out[app.id] = verdict(installed: roomVersion ?? app.version, available: cask.version, homebrew: true) {
                AppUpdate(id: app.bundleID, appID: app.id, name: app.name, source: .homebrew,
                          installedVersion: app.version ?? roomVersion ?? "", availableVersion: shown,
                          action: .copyCommand("brew upgrade --cask \(cask.token)", homepage: cask.homepage))
            }
        }
        return (out, inCaskroom)
    }
}

// MARK: - F4: macOS

public struct MacOSUpdateSource: Sendable {
    public static let systemPlist = URL(fileURLWithPath: "/Library/Preferences/com.apple.SoftwareUpdate.plist")
    private let plist: URL
    private let systemVersion: OperatingSystemVersion
    private let commands: any CommandRunner

    public init(plist: URL = MacOSUpdateSource.systemPlist,
                systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
                commands: any CommandRunner = SystemCommandRunner()) {
        self.plist = plist
        self.systemVersion = systemVersion
        self.commands = commands
    }

    /// Lê o plist do sistema (sem root). Se a última checagem tiver mais de 24 h, roda `softwareupdate --list`.
    public func updates(now: Date) async -> [AppUpdate] {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        let entries = (dict["RecommendedUpdates"] as? [[String: Any]]) ?? []
        var sizes: [String: Int64] = [:]
        let last = dict["LastSuccessfulDate"] as? Date
        if last == nil || now.timeIntervalSince(last!) > 86_400 {
            sizes = Self.parseSizes(commands.run("/usr/sbin/softwareupdate", ["--list"]).output)
        }
        let installed = osString(systemVersion)
        return entries.compactMap { e in
            guard let name = e["Display Name"] as? String, let version = e["Display Version"] as? String else { return nil }
            let key = (e["Product Key"] as? String) ?? (e["Identifier"] as? String) ?? name
            // Só as entradas do sistema comparam com a versão do macOS; as outras (ex.: Safari) não têm versão instalada aqui.
            let isSystem = (e["MobileSoftwareUpdate"] as? Bool) == true
            let major = Int(version.split(separator: ".").first ?? "") ?? systemVersion.majorVersion
            return AppUpdate(id: "macOS:\(key)", appID: nil, name: name, source: .macOS, installedVersion: isSystem ? installed : "",
                             availableVersion: version, size: sizes[version], action: .openSoftwareUpdate,
                             isMajor: isSystem && major != systemVersion.majorVersion)
        }
    }

    /// `Title: …, Version: 26.7.1, Size: 2048KiB, …` → versão → bytes.
    static func parseSizes(_ output: String) -> [String: Int64] {
        var out: [String: Int64] = [:]
        for line in output.split(separator: "\n") where line.contains("Version:") && line.contains("Size:") {
            let fields = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let v = fields.first(where: { $0.hasPrefix("Version:") })?.dropFirst("Version:".count).trimmingCharacters(in: .whitespaces),
                  let s = fields.first(where: { $0.hasPrefix("Size:") })?.dropFirst("Size:".count).trimmingCharacters(in: .whitespaces),
                  s.hasSuffix("KiB"), let kib = Int64(s.dropLast(3)) else { continue }
            out[v] = kib * 1024
        }
        return out
    }
}
