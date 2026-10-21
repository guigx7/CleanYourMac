import Foundation
import Security

/// Inventário do Desinstalador (docs/re/specs/apps/inventory.md): apps do usuário e plug-ins de áudio.
public struct AppCatalog: Sendable {
    public static let selfBundleID = "io.github.guigx7.CleanYourMac"

    private let query: any AppQuery
    private let usage: any UsageDates
    private let sizer = FileSizer()

    public init(query: any AppQuery = SpotlightAppQuery(), usage: any UsageDates = SpotlightUsageDates()) {
        self.query = query
        self.usage = usage
    }

    public func apps(_ context: ScanContext) -> [AppRecord] {
        let applications = context.resolve("/Applications"), userApps = context.resolve("~/Applications")
        var paths: [URL] = []
        collect(applications, depth: 0, into: &paths)
        collect(userApps, depth: 0, into: &paths)
        paths += query.applications(in: [context.home, applications])

        var seen = Set<String>()
        var candidates: [(url: URL, info: [String: Any], id: String)] = []
        for url in paths {
            let real = PathPolicy.realPath(url.path)
            guard seen.insert(real).inserted, !Self.excludedByPath(real, context: context),
                  let info = Self.validBundle(url), let id = info["CFBundleIdentifier"] as? String,
                  !Self.ignoredPrefixes.contains(where: { id.hasPrefix($0) }) else { continue }
            candidates.append((URL(fileURLWithPath: real), info, id))
        }

        // Uma linha por bundle ID; a principal é a de /Applications, depois ~/Applications, depois a mais recente.
        var groups: [String: [(url: URL, info: [String: Any], id: String)]] = [:]
        for c in candidates { groups[c.id.lowercased(), default: []].append(c) }
        let appsRoot = PathPolicy.realPath(applications.path), userRoot = PathPolicy.realPath(userApps.path)
        var out: [AppRecord] = []
        for (_, copies) in groups {
            func rank(_ u: URL) -> Int { u.path.hasPrefix(appsRoot + "/") ? 0 : u.path.hasPrefix(userRoot + "/") ? 1 : 2 }
            let sorted = copies.sorted { a, b in
                if rank(a.url) != rank(b.url) { return rank(a.url) < rank(b.url) }
                let da = lastOpened(a.url) ?? .distantPast, db = lastOpened(b.url) ?? .distantPast
                return da != db ? da > db : a.url.path < b.url.path
            }
            let main = sorted[0]
            out.append(record(main.url, info: main.info, bundleID: main.id, copies: sorted.dropFirst().map(\.url), context: context))
        }
        out += audioPlugins(context)
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func lastOpened(_ url: URL) -> Date? {
        let d = usage.dates(url)
        return d.lastUsed ?? d.contentModified ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func record(_ url: URL, info: [String: Any], bundleID: String, copies: [URL], context: ScanContext) -> AppRecord {
        let dates = usage.dates(url)
        let plistDate = (try? url.appendingPathComponent("Contents/Info.plist").resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        var name = FileManager.default.displayName(atPath: url.path)
        if !name.hasSuffix(".app") { name += ".app" }
        let size = ([url] + copies).reduce(Int64(0)) { $0 + sizer.allocatedSize(of: $1) }
        return AppRecord(url: url, bundleID: bundleID, name: name,
                         version: info["CFBundleShortVersionString"] as? String, build: info["CFBundleVersion"] as? String,
                         teamID: Self.teamID(url), store: Self.store(url, bundleID: bundleID, context: context),
                         vendor: Self.vendor(for: bundleID), kind: .application, lastOpened: lastOpened(url),
                         lastUpdated: dates.contentModified ?? plistDate,
                         isProtected: Self.isProtected(url, bundleID: bundleID, context: context),
                         isSelf: bundleID == Self.selfBundleID, is32Bit: Self.is32Bit(url, info: info), bundleSize: size,
                         feedURL: (info["SUFeedURL"] as? String).flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) },
                         copies: copies,
                         matchName: (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                             ?? url.deletingPathExtension().lastPathComponent)
    }

    // MARK: - Varredura

    /// Varredura profunda sem descer em `.app` e sem seguir links.
    private func collect(_ dir: URL, depth: Int, into out: inout [URL]) {
        guard depth < 8, let children = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else { return }
        for child in children.sorted(by: { $0.path < $1.path }) {
            let v = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard v?.isSymbolicLink != true, v?.isDirectory == true else { continue }
            if child.pathExtension == "app" { out.append(child) } else { collect(child, depth: depth + 1, into: &out) }
        }
    }

    static let ignoredPrefixes = ["com.parallels.winapp", "com.parallels.ApplicationGroupBridge", "com.vmware.proxyApp",
                                  "com.codeweavers.CrossOverHelper", "com.google.Chrome.app.", "com.setapp.teaser"]

    private static let systemPrefixes = ["/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/dev", "/tmp", "/var", "/private",
                                         "/cores", "/net", "/Developer", "/Applications/Developer Tools", "/Volumes"]

    /// Só "apps do usuário": fora pastas do sistema, ~/Library, volumes, apps dentro de apps e pastas com ponto.
    static func excludedByPath(_ real: String, context: ScanContext) -> Bool {
        let root = PathPolicy.realPath(context.root.path), home = PathPolicy.realPath(context.home.path)
        if real.hasPrefix(home + "/Library/") { return true }
        let rel = root == "/" ? real : (real.hasPrefix(root + "/") ? String(real.dropFirst(root.count)) : real)
        func under(_ p: String) -> Bool { rel == p || rel.hasPrefix(p + "/") }
        if systemPrefixes.contains(where: under) { return true }
        if under("/opt") && !under("/opt/homebrew-cask/Caskroom") { return true }
        let homeRel = real.hasPrefix(home + "/") ? String(real.dropFirst(home.count)) : rel
        let parts = homeRel.split(separator: "/").map(String.init)
        for part in parts.dropLast() {
            if part.hasSuffix(".app") || part.hasPrefix(".") { return true }
            let ext = (part as NSString).pathExtension
            if !ext.isEmpty, ext != "localized", Int(ext) == nil { return true }
        }
        return [".pvm", ".vmwarevm", ".backupdb"].contains { rel.contains($0) }
    }

    /// Diretório real com Info.plist legível, bundle ID e o executável presente.
    static func validBundle(_ url: URL) -> [String: Any]? {
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true,
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
              let exe = info["CFBundleExecutable"] as? String,
              FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/MacOS/\(exe)").path) else { return nil }
        return info
    }

    // MARK: - Lojas e fornecedores

    static func store(_ url: URL, bundleID: String, context: ScanContext) -> AppStore {
        if bundleID.hasSuffix("-setapp") { return .setapp }
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path) { return .appStore }
        if isSteam(url, context: context) { return .steam }
        if isBattleNet(url, context: context) { return .battleNet }
        return .other
    }

    /// Jogo dentro de `<biblioteca>/steamapps/common/` de uma biblioteca do `libraryfolders.vdf`.
    static func isSteam(_ url: URL, context: ScanContext) -> Bool {
        let vdf = context.home.appendingPathComponent("Library/Application Support/Steam/steamapps/libraryfolders.vdf")
        guard let text = try? String(contentsOf: vdf, encoding: .utf8) else { return false }
        let real = PathPolicy.realPath(url.path)
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\"").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard fields.count == 2, fields[0] == "path" else { continue }
            if real.hasPrefix(PathPolicy.realPath(fields[1]) + "/steamapps/common/") { return true }
        }
        return false
    }

    static func isBattleNet(_ url: URL, context: ScanContext) -> Bool {
        let config = context.home.appendingPathComponent("Library/Application Support/Battle.net/Battle.net.config")
        guard let data = try? Data(contentsOf: config),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let install = ((json["Client"] as? [String: Any])?["Install"] as? [String: Any])?["DefaultInstallPath"] as? String
        else { return false }
        return PathPolicy.realPath(url.path).hasPrefix(PathPolicy.realPath(install) + "/")
    }

    private static let vendorTable: [(AppVendor, [String])] = [
        (.apple, ["com.apple", "developer.apple."]),
        (.google, ["com.google."]),
        (.macPaw, ["com.macpaw", "com.setapp", "cx.c3.xee3", "cx.c3.theunarchiver", "cx.c3.thearchivebrowser"]),
        (.jetBrains, ["com.jetbrains", "org.jetbrains", "com.kotlinconf.iosapp"]),
        (.microsoft, ["com.microsoft.", "com.skype.", "com.followanalytics.adventureworks.msdc365"]),
        (.adobe, ["com.adobe", "adobe."]),
    ]

    /// Tabela de prefixos; prefixos sem ponto final só casam com fronteira (`.` ou `-`).
    public static func vendor(for bundleID: String) -> AppVendor {
        for (vendor, prefixes) in vendorTable {
            for p in prefixes {
                guard bundleID.hasPrefix(p) else { continue }
                if p.hasSuffix(".") || bundleID.count == p.count { return vendor }
                let next = bundleID[bundleID.index(bundleID.startIndex, offsetBy: p.count)]
                if next == "." || next == "-" { return vendor }
            }
        }
        return .other
    }

    // MARK: - Metadados

    static let reinstalledBySystem: Set<String> = ["com.apple.Safari"]

    static func isProtected(_ url: URL, bundleID: String, context: ScanContext) -> Bool {
        var st = stat()
        if lstat(url.appendingPathComponent("Contents/Info.plist").path, &st) == 0, st.st_flags & UInt32(SF_RESTRICTED) != 0 { return true }
        let root = PathPolicy.realPath(context.root.path)
        let real = PathPolicy.realPath(url.path)
        let rel = root == "/" ? real : String(real.dropFirst(root.count))
        return rel.hasPrefix("/System/") || reinstalledBySystem.contains(bundleID)
    }

    /// Executável principal só com fatias de 32 bits (i386/ppc), nenhuma de 64.
    static func is32Bit(_ url: URL, info: [String: Any]) -> Bool {
        guard let exe = info["CFBundleExecutable"] as? String,
              let handle = try? FileHandle(forReadingFrom: url.appendingPathComponent("Contents/MacOS/\(exe)")),
              let head = try? handle.read(upToCount: 4096), head.count >= 8 else { return false }
        let bytes = [UInt8](head)
        func be(_ o: Int) -> UInt32 { bytes[o..<o + 4].reduce(0) { $0 << 8 | UInt32($1) } }
        switch be(0) {
        case 0xCEFA_EDFE, 0xFEED_FACE: return true
        case 0xCAFE_BABE:
            let count = Int(be(4))
            guard count > 0, 8 + count * 20 <= bytes.count else { return false }
            let cpus = (0..<count).map { be(8 + $0 * 20) }
            return cpus.allSatisfy { $0 & 0x0100_0000 == 0 }
        default:
            return false
        }
    }

    static func teamID(_ url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: - Plug-ins de áudio

    static let pluginExtensions: Set<String> = ["vst", "vst3", "component", "driver", "clap", "aaxplugin", "dpm"]

    func audioPlugins(_ context: ScanContext) -> [AppRecord] {
        let fm = FileManager.default
        var folders: [URL] = []
        for base in ["~/Library/Audio/Plug-Ins", "/Library/Audio/Plug-Ins"] {
            let dir = context.resolve(base)
            for sub in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { folders.append(sub) }
        }
        folders.append(context.resolve("/Library/Application Support/Avid/Audio/Plug-Ins"))
        var out: [AppRecord] = []
        for folder in folders {
            for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            where Self.pluginExtensions.contains(item.pathExtension.lowercased())
                && (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true {
                let info = (try? Data(contentsOf: item.appendingPathComponent("Contents/Info.plist")))
                    .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
                let id = (info["CFBundleIdentifier"] as? String) ?? item.lastPathComponent
                out.append(AppRecord(url: item, bundleID: id, name: item.lastPathComponent,
                                     version: info["CFBundleShortVersionString"] as? String, vendor: Self.vendor(for: id),
                                     kind: .audioPlugin, lastOpened: nil, isProtected: id.lowercased().hasPrefix("com.apple."),
                                     bundleSize: sizer.allocatedSize(of: item),
                                     matchName: item.deletingPathExtension().lastPathComponent))
            }
        }
        return out
    }
}
