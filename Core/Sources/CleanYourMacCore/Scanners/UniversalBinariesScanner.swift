import Foundation

/// Leitura mínima do cabeçalho Mach-O (fat ou thin) — só o necessário para medir fatias.
public struct MachOFile: Sendable {
    public struct Slice: Sendable, Hashable {
        public let arch: String
        public let cputype: UInt32
        public let cpusubtype: UInt32
        public let offset: UInt64
        public let size: Int64
    }

    public let isFat: Bool
    public let slices: [Slice]
    /// Arquitetura de um binário thin (nil se não reconhecida, ex.: script).
    public let thinArch: String?

    static func archName(_ cputype: UInt32, _ cpusubtype: UInt32) -> String? {
        let sub = cpusubtype & 0x00FF_FFFF
        switch (cputype, sub) {
        case (0x0100_000C, 0): return "arm64"
        case (0x0100_000C, 2): return "arm64e"
        case (0x0100_0007, 3): return "x86_64"
        case (0x0100_0007, 8): return "x86_64h"
        default: return nil
        }
    }

    public init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 8), head.count == 8 else { return nil }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        func be32(_ d: Data, _ o: Int) -> UInt32 { d[d.startIndex + o..<d.startIndex + o + 4].reduce(0) { $0 << 8 | UInt32($1) } }
        func be64(_ d: Data, _ o: Int) -> UInt64 { d[d.startIndex + o..<d.startIndex + o + 8].reduce(0) { $0 << 8 | UInt64($1) } }
        let magic = be32(head, 0)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            let is64 = magic == 0xCAFE_BABF
            let count = Int(be32(head, 4))
            let entry = is64 ? 32 : 20
            guard count > 0, count < 64 else { return nil }
            try? handle.seek(toOffset: 8)
            guard let table = try? handle.read(upToCount: count * entry), table.count == count * entry else { return nil }
            var slices: [Slice] = []
            for i in 0..<count {
                let o = i * entry
                let cpu = be32(table, o), sub = be32(table, o + 4)
                let offset = is64 ? be64(table, o + 8) : UInt64(be32(table, o + 8))
                let size = is64 ? be64(table, o + 16) : UInt64(be32(table, o + 12))
                let align = is64 ? be32(table, o + 24) : be32(table, o + 16)
                guard offset + size <= fileSize, align < 16, offset % (UInt64(1) << UInt64(align)) == 0 else { continue }
                slices.append(Slice(arch: Self.archName(cpu, sub) ?? "unknown", cputype: cpu, cpusubtype: sub & 0x00FF_FFFF,
                                    offset: offset, size: Int64(size)))
            }
            isFat = true
            self.slices = slices
            thinArch = nil
        } else {
            // Thin: tipo/subtipo nos bytes 4–11, na ordem nativa (little-endian).
            try? handle.seek(toOffset: 4)
            guard let rest = try? handle.read(upToCount: 8), rest.count == 8 else { return nil }
            let cpu = rest[rest.startIndex..<rest.startIndex + 4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let sub = rest[rest.startIndex + 4..<rest.startIndex + 8].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let name = Self.archName(cpu, sub)
            isFat = false
            slices = []
            thinArch = (name == "arm64" || name == "x86_64") ? name : nil
        }
    }
}

/// Fatias de outras arquiteturas dentro dos apps do usuário (docs/re/specs/universal-binaries.md).
public struct UniversalBinariesScanner: ScopedScanner {
    public let group = GroupID.universalBinaries
    private let inventory: any AppInventory
    private let hostArch: String

    static let ignoredPrefixes = ["com.parallels.winapp", "com.parallels.ApplicationGroupBridge", "com.vmware.proxyApp",
                                  "com.codeweavers.CrossOverHelper", "com.google.Chrome.app.", "com.setapp.teaser", "com.apple."]
    static let ignoredIDs: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev",
                                          "com.google.Chrome.canary", "io.github.guigx7.CleanYourMac"]
    static let skippedNames: Set<String> = ["CodeResources", ".DS_Store", "PkgInfo"]

    public init(inventory: any AppInventory = UserAppsInventory(), hostArch: String = UniversalBinariesScanner.hardwareArch()) {
        self.inventory = inventory
        self.hostArch = hostArch
    }

    public static func hardwareArch() -> String {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1 ? "arm64" : "x86_64"
    }

    private func apps(_ ctx: ScanContext) -> [InstalledApp] {
        inventory.apps(ctx).filter { Self.isInScope($0.url, ctx) && Self.eligible($0, ctx) }
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        RemovalScope(items: apps(context).map(\.url))
    }

    /// Filtro de caminho da lista de apps do usuário.
    static func isInScope(_ url: URL, _ ctx: ScanContext) -> Bool {
        let rootPath = PathPolicy.realPath(ctx.root.path)
        var path = PathPolicy.realPath(url.path)
        if rootPath != "/", path.hasPrefix(rootPath) { path = String(path.dropFirst(rootPath.count)) }
        let homeRel: String = {
            let h = PathPolicy.realPath(ctx.home.path)
            return rootPath != "/" && h.hasPrefix(rootPath) ? String(h.dropFirst(rootPath.count)) : h
        }()
        if path.hasSuffix("/Library/Application Support/Setapp/LaunchAgents/Setapp.app") { return true }
        let banned = ["/net", "/tmp", "/var", "/cores", "/private", "/dev", "/sbin", "/bin", "/etc", "/usr", "/Library",
                      "/System", "/Developer", "/Applications/Developer Tools", "/Volumes", homeRel + "/Library"]
        if banned.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
        if path.hasPrefix("/opt"), !path.hasPrefix("/opt/homebrew-cask/Caskroom") { return false }
        if path.contains(".pvm") || path.contains(".vmwarevm") { return false }
        let parents = path.split(separator: "/").dropLast()
        for p in parents {
            if p.hasSuffix(".app") { return false }
            if let dot = p.firstIndex(of: ".") {
                let after = p[p.index(after: dot)...]
                if after != "localized" && !(after.first?.isNumber ?? false) { return false }
            }
        }
        return true
    }

    static func eligible(_ app: InstalledApp, _ ctx: ScanContext) -> Bool {
        if ignoredIDs.contains(app.bundleID) || ignoredPrefixes.contains(where: { app.bundleID.hasPrefix($0) }) { return false }
        if FileManager.default.fileExists(atPath: app.url.appendingPathComponent("Contents/_MASReceipt").path) { return false }
        var st = stat()
        if lstat(app.url.path, &st) == 0, st.st_flags & UInt32(UF_IMMUTABLE | SF_RESTRICTED) != 0 { return false }
        if lstat(app.url.appendingPathComponent("Contents/Info.plist").path, &st) == 0, st.st_flags & UInt32(SF_RESTRICTED) != 0 { return false }
        let ls = ctx.resolve("~/Library/Preferences/com.apple.LaunchServices/com.apple.LaunchServices.plist")
        if let data = try? Data(contentsOf: ls),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for key in ["Architectures for arm64", "Architectures for x86_64"] {
                if let ids = dict[key] as? [String: Any], ids[app.bundleID] != nil { return false }
            }
        }
        return true
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        var out: [JunkItem] = []
        var found: Int64 = 0
        for app in apps(context) {
            try Task.checkCancellation()
            report(ScanProgress(group: group, currentPath: app.url.path, bytesFound: found))
            guard let item = analyze(app) else { continue }
            found += item.totalSize
            out.append(item)
        }
        return out
    }

    /// Item do app com um filho por binário afinável; `nil` se nada a fazer ou se o app deve ser pulado.
    func analyze(_ app: InstalledApp) -> JunkItem? {
        guard let execName = Self.mainExecutableName(app.url) else { return nil }
        let main = app.url.appendingPathComponent("Contents/MacOS/\(execName)")
        guard let mainFile = MachOFile(url: main) else { return nil }
        let keep: String
        if mainFile.isFat {
            let archs = Set(mainFile.slices.map(\.arch))
            if hostArch == "arm64" {
                guard archs.contains("arm64") else { return nil }   // arm64e + x86_64: pulamos (divergência)
                keep = "arm64"
            } else {
                guard archs.contains("x86_64") else { return nil }
                keep = "x86_64"
            }
        } else {
            guard let arch = mainFile.thinArch else { return nil }
            keep = arch
        }
        let sealed = Self.sealedPaths(app.url)
        var children: [JunkItem] = []
        for file in Self.candidates(app.url) where !sealed.contains(PathPolicy.realPath(file.path)) {
            guard let macho = MachOFile(url: file) else { return nil }
            if macho.isFat {
                guard macho.slices.contains(where: { $0.arch == keep }) else { return nil }
                let extra = macho.slices.filter { $0.arch != keep }.reduce(Int64(0)) { $0 + $1.size }
                guard extra > 0 else { continue }
                let rel = String(file.path.dropFirst(app.url.path.count + 1))
                children.append(JunkItem(id: "universalBinaries:\(file.path)", group: group, name: rel, url: file, size: extra,
                                         icon: .file(file), removal: .thinBinary(executable: file, keepArch: keep, bundle: app.url)))
            } else if macho.thinArch != keep {
                return nil
            }
        }
        guard !children.isEmpty else { return nil }
        return JunkItem(id: "universalBinaries:\(app.url.path)", group: group, name: app.url.lastPathComponent, url: app.url,
                        size: 0, icon: .app(app.url), children: children, displaysChildren: false)
    }

    static func mainExecutableName(_ app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return dict["CFBundleExecutable"] as? String
    }

    /// Arquivos sem extensão, executáveis, não symlink, fora de `.lproj`, entrando em pacotes.
    static func candidates(_ app: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        let e = FileManager.default.enumerator(at: app, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        var out: [URL] = []
        while let u = e?.nextObject() as? URL {
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true, v.isSymbolicLink != true, u.pathExtension == "lproj" { e?.skipDescendants(); continue }
            guard v.isRegularFile == true, v.isSymbolicLink != true, u.pathExtension.isEmpty,
                  !skippedNames.contains(u.lastPathComponent), access(u.path, X_OK) == 0 else { continue }
            out.append(u)
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Caminhos selados (não opcionais) em todos os `CodeResources` do bundle.
    static func sealedPaths(_ app: URL) -> Set<String> {
        let e = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in true })
        var out = Set<String>()
        while let u = e?.nextObject() as? URL {
            guard u.lastPathComponent == "CodeResources",
                  let data = try? Data(contentsOf: u),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            let base = u.deletingLastPathComponent().deletingLastPathComponent()
            for key in ["files", "files2"] {
                for (path, value) in (dict[key] as? [String: Any]) ?? [:] {
                    if let v = value as? [String: Any], v["optional"] as? Bool == true { continue }
                    out.insert(PathPolicy.realPath(base.appendingPathComponent(path).path))
                }
            }
        }
        return out
    }
}

/// Apps do usuário: `/Applications`, `~/Applications` (recursivo) e o que o Spotlight acha na home.
public struct UserAppsInventory: AppInventory {
    public init() {}

    public func apps(_ context: ScanContext) -> [InstalledApp] {
        var seen = Set<String>()
        var out: [InstalledApp] = []
        for app in FolderAppInventory(folders: ["/Applications", "~/Applications"]).apps(context) where seen.insert(app.url.path).inserted {
            out.append(app)
        }
        let r = SystemCommandRunner().run("/usr/bin/mdfind", ["-onlyin", context.home.path, "kMDItemContentType == com.apple.application-bundle"])
        for line in r.output.split(separator: "\n") {
            let url = URL(fileURLWithPath: String(line))
            if seen.insert(url.path).inserted, let app = FolderAppInventory.read(url) { out.append(app) }
        }
        return out
    }
}
