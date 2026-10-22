import Foundation

/// Executa, como root, os comandos pedidos pelo app — revalidando cada caminho por conta própria:
/// só filhos (estritos) de áreas permitidas, nunca locais vitais, nunca através de symlinks.
public struct HelperExecutor: Sendable {
    /// Áreas onde a Limpeza pode precisar de root (caches/registros do sistema, launchd, usuários apagados,
    /// apps e pastas de usuários como plano B de permissão).
    public static let productionPrefixes = [
        "/Library/Caches", "/Library/Logs", "/private/var/log", "/System/Library/Caches/com.apple.coresymbolicationd",
        "/System/Library/Caches", "/Users/Deleted Users", "/Library/LaunchAgents", "/Library/LaunchDaemons",
        "/Library/PrivilegedHelperTools", "/Applications", "/Users", "/Library/Developer/CoreSimulator",
    ]

    /// Onde `trash` pode buscar itens: apps e arquivos de apps (docs/re/specs/apps/removal.md §trash).
    /// "/Users" só vale dentro da pasta do usuário que pediu.
    public static let productionTrashPrefixes = [
        "/Applications", "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/Logs",
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Audio/Plug-Ins",
        "/Library/Internet Plug-Ins", "/Library/PreferencePanes", "/Users",
    ]
    public static let productionLaunchdFolders = ["/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools"]

    private let prefixes: [String]
    private let trashPrefixes: [String]
    private let launchdFolders: [String]
    private let commands: any CommandRunner
    private let homeOf: @Sendable (uid_t) -> String?
    /// Onde procurar o app dono (para casar pelo nome e ler `SMPrivilegedExecutables`).
    private let appRoots: [String]

    public init(allowedPrefixes: [String] = HelperExecutor.productionPrefixes,
                trashPrefixes: [String] = HelperExecutor.productionTrashPrefixes,
                launchdFolders: [String] = HelperExecutor.productionLaunchdFolders,
                commands: any CommandRunner = SystemCommandRunner(),
                homeOf: @escaping @Sendable (uid_t) -> String? = HelperExecutor.home(of:),
                appRoots: [String] = ["/Applications"]) {
        self.appRoots = appRoots.map { PathPolicy.realPath($0) }
        prefixes = allowedPrefixes.map { PathPolicy.realPath($0) }
        self.trashPrefixes = trashPrefixes.map { PathPolicy.realPath($0) }
        self.launchdFolders = launchdFolders.map { PathPolicy.realPath($0) }
        self.commands = commands
        self.homeOf = { uid in homeOf(uid).map(PathPolicy.realPath) }
    }

    /// Pasta do usuário pelo banco de contas (nunca pela mensagem).
    public static func home(of uid: uid_t) -> String? {
        guard let pw = getpwuid(uid), let dir = pw.pointee.pw_dir else { return nil }
        return String(cString: dir)
    }

    /// `requester`: uid de quem pediu, tirado da conexão XPC pelo daemon.
    public func handle(_ request: HelperRequest, requester: uid_t = getuid()) -> HelperResponse {
        switch request {
        case .ping: HelperResponse()
        case .run(let commands): HelperResponse(results: run(commands, requester: requester))
        case .measure(let urls): HelperResponse(sizes: measure(urls))
        }
    }

    public func run(_ commands: [PrivilegedCommand], requester: uid_t = getuid()) -> [HelperResult] {
        commands.map { cmd in
            switch cmd {
            case .remove(let u):
                guard let path = validated(u) else { return .refused }
                return remove(path)
            case .removeContents(let u):
                guard let path = validated(u), !isSymlink(path) else { return .refused }
                let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                for c in children {
                    if case .failed(let e) = remove((path as NSString).appendingPathComponent(c)) { return .failed(e) }
                }
                return .ok
            case .lipoThin(let u, let arch):
                guard let path = validated(u), !isSymlink(path), ["arm64", "x86_64"].contains(arch) else { return .refused }
                return thin(path, keep: arch)
            case .codesignAdhoc:
                return .refused
            case .trash(let u, let owner):
                guard Self.isSafeOwner(owner), let path = validatedForTrash(u, requester: requester, owner: owner) else { return .refused }
                return trash(path, requester: requester)
            case .launchdBootout(let plist, let owner):
                guard Self.isSafeOwner(owner) else { return .refused }
                return bootout(plist, owner: owner, requester: requester)
            case .forgetPackage(let id, let owner):
                guard Self.isSafeOwner(owner) else { return .refused }
                return forget(id, owner: owner)
            case .maintenance:
                return .refused
            }
        }
    }

    public func measure(_ urls: [URL]) -> [Int64?] {
        let sizer = FileSizer()
        return urls.map { u in
            let real = PathPolicy.realPath(u.path)
            guard FileManager.default.fileExists(atPath: real), within(real, allowEqual: true) else { return nil }
            return sizer.allocatedSize(of: URL(fileURLWithPath: real))
        }
    }

    // MARK: - Validação

    /// Caminho com o pai resolvido (o último componente não é seguido), ou nil se não for permitido.
    func validated(_ u: URL) -> String? {
        let lexical = PathPolicy.lexicalPath(u.path)
        guard lexical.hasPrefix("/"), !lexical.contains("\n") else { return nil }
        let parent = PathPolicy.realPath((lexical as NSString).deletingLastPathComponent)
        let path = (parent as NSString).appendingPathComponent((lexical as NSString).lastPathComponent)
        guard within(path, allowEqual: false), !PathPolicy.isVital(path) else { return nil }
        return path
    }

    /// Identificador de bundle/pacote: só `[A-Za-z0-9._-]`, sem "..", sem começar com ponto.
    public static func isSafeIdentifier(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 255 && !s.contains("..") && !s.hasPrefix(".")
            && s.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }
    }

    static func isSafeOwner(_ owner: String) -> Bool {
        isSafeIdentifier(owner) && !owner.lowercased().hasPrefix("com.apple.")
    }

    /// Pastas da home de quem pediu que nunca vão para o Lixo inteiras (a lista vital do PathPolicy usa a home do root).
    static let homeVitals = ["", "Documents", "Desktop", "Downloads", "Library", "Pictures", "Movies", "Music", "Applications",
                             "Library/Application Support", "Library/Caches", "Library/Preferences", "Library/Containers",
                             "Library/Group Containers", "Library/Logs", "Library/LaunchAgents", "Library/Mail", ".Trash"]

    /// `trash`: filho estrito de um prefixo de `trash` (não dos de `remove`), sem symlink no último componente, nunca
    /// vital, nunca `com.apple.*`, em /Users só na home de quem pediu, e ligado ao app dono (removal.md §Travas comuns).
    func validatedForTrash(_ u: URL, requester: uid_t, owner: String) -> String? {
        let lexical = PathPolicy.lexicalPath(u.path)
        guard lexical.hasPrefix("/"), !lexical.contains("\n") else { return nil }
        let parent = PathPolicy.realPath((lexical as NSString).deletingLastPathComponent)
        let path = (parent as NSString).appendingPathComponent((lexical as NSString).lastPathComponent)
        guard let prefix = trashPrefixes.first(where: { path.hasPrefix($0 + "/") }), !PathPolicy.isVital(path), !isSymlink(path) else { return nil }
        if (prefix as NSString).lastPathComponent == "Users" {
            guard let home = homeOf(requester), path.hasPrefix(home + "/"),
                  !Self.homeVitals.contains(where: { path == ($0.isEmpty ? home : home + "/" + $0) }) else { return nil }
        }
        let parts = String(path.dropFirst(prefix.count + 1)).split(separator: "/").map(String.init)
        guard !parts.contains(where: { $0.lowercased().hasPrefix("com.apple.") }), isLinked(path, parts: parts, owner: owner) else { return nil }
        return path
    }

    /// Algum componente é do dono (bundle ID com fronteira, nome do app, relatório "<Nome>_"), ou o item é o bundle do
    /// app, ou um plist do launchd / helper privilegiado ligado a ele.
    private func isLinked(_ path: String, parts: [String], owner: String) -> Bool {
        let id = owner.lowercased()
        let names = ownerApps(owner).compactMap { Self.appName($0) }.filter { $0.count >= 3 }.map { $0.lowercased() }
        for part in parts {
            let base = part.lowercased(), bare = (base as NSString).deletingPathExtension
            if [base, bare].contains(where: { $0 == id || $0.hasPrefix(id + ".") }) { return true }
            if names.contains(where: { base == $0 || bare == $0 || part.hasPrefix(Self.capitalized($0, in: part) + "_") }) { return true }
        }
        if path.hasSuffix(".app"), Self.readPlistNoFollow(path + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String == owner { return true }
        let folder = (path as NSString).deletingLastPathComponent
        if launchdFolders.contains(folder) {
            if path.hasSuffix(".plist"), let dict = Self.readPlistNoFollow(path), launchdLinked(dict, file: (path as NSString).lastPathComponent, owner: owner) {
                return true
            }
            if privilegedExecutables(owner).contains((path as NSString).lastPathComponent) { return true }
        }
        return false
    }

    private static func capitalized(_ lower: String, in part: String) -> String {
        String(part.prefix(lower.count))
    }

    /// Apps com esse bundle ID nas pastas de apps (lidos como root, sem seguir links).
    private func ownerApps(_ owner: String) -> [String] {
        var out: [String] = []
        for root in appRoots {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".app") {
                let app = root + "/" + name
                guard !isSymlink(app), Self.readPlistNoFollow(app + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String == owner else { continue }
                out.append(app)
            }
        }
        return out
    }

    private static func appName(_ app: String) -> String? {
        (readPlistNoFollow(app + "/Contents/Info.plist")?["CFBundleName"] as? String) ?? ((app as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private func privilegedExecutables(_ owner: String) -> Set<String> {
        Set(ownerApps(owner).flatMap { ((Self.readPlistNoFollow($0 + "/Contents/Info.plist")?["SMPrivilegedExecutables"] as? [String: Any]) ?? [:]).keys })
    }

    /// Mesmo vínculo de related-files.md §loginItems, revalidado como root.
    private func launchdLinked(_ dict: [String: Any], file: String, owner: String) -> Bool {
        let label = dict["Label"] as? String ?? ""
        let name = (file as NSString).deletingPathExtension
        func ofOwner(_ x: String) -> Bool { x == owner || x.hasPrefix(owner + ".") }
        if ofOwner(label) && ofOwner(name) { return true }
        let associated = (dict["AssociatedBundleIdentifiers"] as? [String]) ?? ((dict["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? [])
        if associated.contains(owner) { return true }
        if name == label, privilegedExecutables(owner).contains(label) { return true }
        let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
        return program.map { Self.bundleID(containing: $0) == owner } == true
    }

    private func within(_ path: String, allowEqual: Bool) -> Bool {
        prefixes.contains { p in (allowEqual && path == p) || path.hasPrefix(p + "/") }
    }

    private func isSymlink(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }

    // MARK: - Ações

    private func remove(_ path: String) -> HelperResult {
        var st = stat()
        guard lstat(path, &st) == 0 else { return errno == ENOENT ? .ok : .failed(String(cString: strerror(errno))) }
        if st.st_flags & UInt32(UF_IMMUTABLE) != 0 { lchflags(path, st.st_flags & ~UInt32(UF_IMMUTABLE)) }
        do {
            try FileManager.default.removeItem(atPath: path)
            return .ok
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Move para o Lixo de quem pediu, no mesmo volume, com nome livre. As pastas de origem e do Lixo são abertas sem
    /// seguir links em nenhum componente e o `rename` é relativo a elas e exclusivo; o dono do item não muda (nada de
    /// `chown` como root, que seguiria links trocados pelo usuário).
    private func trash(_ path: String, requester: uid_t) -> HelperResult {
        var st = stat()
        guard lstat(path, &st) == 0 else { return errno == ENOENT ? .ok : .failed(String(cString: strerror(errno))) }
        guard let home = homeOf(requester) else { return .refused }
        let bin = home + "/.Trash"
        var binStat = stat()
        if lstat(bin, &binStat) != 0 {
            guard mkdir(bin, 0o700) == 0, lstat(bin, &binStat) == 0 else { return .failed("no trash folder") }
            lchown(bin, requester, gid_t(UInt32.max))
        }
        guard (binStat.st_mode & S_IFMT) == S_IFDIR else { return .refused }
        let noFollowAny: Int32 = 0x2000_0000 // O_NOFOLLOW_ANY
        let parentFD = open((path as NSString).deletingLastPathComponent, O_RDONLY | O_DIRECTORY | noFollowAny)
        guard parentFD >= 0 else { return .refused }
        defer { close(parentFD) }
        let binFD = open(bin, O_RDONLY | O_DIRECTORY | noFollowAny)
        guard binFD >= 0 else { return .refused }
        defer { close(binFD) }
        let name = (path as NSString).lastPathComponent
        var item = stat(), binInfo = stat()
        // O último componente é revisto pelo fd do pai: link → recusa (mesmo se trocado depois da validação).
        guard fstatat(parentFD, name, &item, AT_SYMLINK_NOFOLLOW) == 0, (item.st_mode & S_IFMT) != S_IFLNK,
              fstat(binFD, &binInfo) == 0 else { return .refused }
        // Entre volumes o helper não copia árvores.
        guard binInfo.st_dev == item.st_dev else { return .refused }
        var n = 1
        while n < 1000 {
            let target = n == 1 ? name : "\(name) \(n)"
            if renameatx_np(parentFD, name, binFD, target, UInt32(RENAME_EXCL)) == 0 { return .ok }
            guard errno == EEXIST else { return .failed(String(cString: strerror(errno))) }
            n += 1
        }
        return .failed("no free name in trash")
    }

    /// Descarrega um job do launchd. O plist é relido como root; o vínculo com o app é revalidado.
    private func bootout(_ plist: URL, owner: String, requester: uid_t) -> HelperResult {
        let lexical = PathPolicy.lexicalPath(plist.path)
        let folder = PathPolicy.realPath((lexical as NSString).deletingLastPathComponent)
        let file = (lexical as NSString).lastPathComponent
        let path = folder + "/" + file
        guard launchdFolders.contains(folder), file.hasSuffix(".plist"), !file.hasPrefix("com.apple."),
              !isSymlink(path), let dict = Self.readPlistNoFollow(path),
              let label = dict["Label"] as? String, !label.isEmpty, !label.hasPrefix("com.apple."),
              Self.isSafeIdentifier(label) || !label.contains("/") else { return .refused }
        guard launchdLinked(dict, file: file, owner: owner) else { return .refused }
        let target = (folder as NSString).lastPathComponent == "LaunchAgents" ? "gui/\(requester)/\(label)" : "system/\(label)"
        let r = commands.run("/bin/launchctl", ["bootout", target])
        // 3 (ESRCH) / 113: o job não estava carregado.
        return [0, 3, 113].contains(r.status) ? .ok : .failed("launchctl bootout: \(r.status)")
    }

    /// Esquece o recibo de um pacote do app (só no volume de inicialização).
    private func forget(_ id: String, owner: String) -> HelperResult {
        guard Self.isSafeIdentifier(id), !id.lowercased().hasPrefix("com.apple.") else { return .refused }
        // Vínculo: o recibo é do mesmo fornecedor (dois primeiros componentes do bundle ID).
        let vendor = owner.split(separator: ".").prefix(2).joined(separator: ".") + "."
        guard id.hasPrefix(vendor) || id == owner else { return .refused }
        let info = commands.run("/usr/sbin/pkgutil", ["--pkg-info", id])
        guard info.status == 0 else { return .failed("receipt not found") }
        let volume = info.output.split(separator: "\n").first { $0.hasPrefix("volume:") }
            .map { $0.dropFirst("volume:".count).trimmingCharacters(in: .whitespaces) }
        guard volume == "/" else { return .refused }
        let r = commands.run("/usr/sbin/pkgutil", ["--forget", id])
        return r.status == 0 ? .ok : .failed("pkgutil --forget: \(r.status)")
    }

    private static func readPlistNoFollow(_ path: String) -> [String: Any]? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        guard let data = try? handle.readToEnd(), data.count < 1_000_000 else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Bundle ID do `.app` que contém o executável (o mais externo).
    static func bundleID(containing executable: String) -> String? {
        let parts = (PathPolicy.lexicalPath(executable) as NSString).pathComponents
        guard let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let app = NSString.path(withComponents: Array(parts[...i]))
        guard let data = readPlistNoFollow(app + "/Contents/Info.plist") else { return nil }
        return data["CFBundleIdentifier"] as? String
    }

    private func thin(_ path: String, keep arch: String) -> HelperResult {
        let tmp = path + ".cymthin"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        p.arguments = [path, "-extract", arch, "-output", tmp]
        guard (try? p.run()) != nil else { return .failed("lipo") }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { try? FileManager.default.removeItem(atPath: tmp); return .failed("lipo failed") }
        var st = stat()
        if lstat(path, &st) == 0 {
            chmod(tmp, st.st_mode & 0o7777)
            chown(tmp, st.st_uid, st.st_gid)
        }
        guard rename(tmp, path) == 0 else { try? FileManager.default.removeItem(atPath: tmp); return .failed("rename failed") }
        return .ok
    }
}
