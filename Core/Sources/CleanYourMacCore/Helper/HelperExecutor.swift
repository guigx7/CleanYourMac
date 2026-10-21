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

    public init(allowedPrefixes: [String] = HelperExecutor.productionPrefixes,
                trashPrefixes: [String] = HelperExecutor.productionTrashPrefixes,
                launchdFolders: [String] = HelperExecutor.productionLaunchdFolders,
                commands: any CommandRunner = SystemCommandRunner(),
                homeOf: @escaping @Sendable (uid_t) -> String? = HelperExecutor.home(of:)) {
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
                guard Self.isSafeOwner(owner), let path = validatedForTrash(u, requester: requester) else { return .refused }
                return trash(path, requester: requester)
            case .launchdBootout(let plist, let owner):
                guard Self.isSafeOwner(owner) else { return .refused }
                return bootout(plist, owner: owner, requester: requester)
            case .forgetPackage(let id, let owner):
                guard Self.isSafeOwner(owner) else { return .refused }
                return forget(id, owner: owner)
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

    /// Como `validated`, mas com os prefixos de `trash` e, em /Users, só a pasta de quem pediu.
    func validatedForTrash(_ u: URL, requester: uid_t) -> String? {
        guard let path = validated(u) else { return nil }
        let inPrefix = trashPrefixes.contains { path.hasPrefix($0 + "/") }
        guard inPrefix else { return nil }
        let users = trashPrefixes.first { ($0 as NSString).lastPathComponent == "Users" }
        if let users, path.hasPrefix(users + "/") {
            guard let home = homeOf(requester), path.hasPrefix(home + "/"),
                  !PathPolicy.isVital(path), path != home + "/.Trash" else { return nil }
        }
        return path
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

    /// Move para o Lixo de quem pediu, no mesmo volume, com nome livre; o item passa a ser do usuário.
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
        // Entre volumes o helper não copia árvores.
        guard binStat.st_dev == st.st_dev else { return .refused }
        let name = (path as NSString).lastPathComponent
        var target = bin + "/" + name
        var n = 2
        var probe = stat()
        while lstat(target, &probe) == 0 {
            target = bin + "/" + name + " \(n)"
            n += 1
        }
        guard rename(path, target) == 0 else { return .failed(String(cString: strerror(errno))) }
        Self.chownTree(target, to: requester)
        return .ok
    }

    /// `lchown -R` sem seguir links.
    private static func chownTree(_ path: String, to uid: uid_t) {
        lchown(path, uid, gid_t(UInt32.max))
        guard let e = FileManager.default.enumerator(atPath: path) else { return }
        while let rel = e.nextObject() as? String {
            lchown((path as NSString).appendingPathComponent(rel), uid, gid_t(UInt32.max))
        }
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
        let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
        let linked = label.hasPrefix(owner) || file.hasPrefix(owner) || program.map { Self.bundleID(containing: $0) == owner } == true
        guard linked else { return .refused }
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
