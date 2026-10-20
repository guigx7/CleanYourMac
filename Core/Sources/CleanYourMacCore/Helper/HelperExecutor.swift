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

    private let prefixes: [String]

    public init(allowedPrefixes: [String] = HelperExecutor.productionPrefixes) {
        prefixes = allowedPrefixes.map { PathPolicy.realPath($0) }
    }

    public func handle(_ request: HelperRequest) -> HelperResponse {
        switch request {
        case .ping: HelperResponse()
        case .run(let commands): HelperResponse(results: run(commands))
        case .measure(let urls): HelperResponse(sizes: measure(urls))
        }
    }

    public func run(_ commands: [PrivilegedCommand]) -> [HelperResult] {
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
