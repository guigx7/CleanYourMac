import Foundation

public enum CleanEvent: Sendable {
    case started(JunkItem)
    case finished(JunkItem, Result<Int64, CleanFailure>)
    case completed(CleanReport)
}

/// Responde se um processo do usuário está rodando (proteção de pastas temporárias em uso).
public protocol ProcessChecker: Sendable {
    func isRunning(_ name: String, uid: uid_t) -> Bool
}

public struct SystemProcessChecker: ProcessChecker {
    public init() {}

    public func isRunning(_ name: String, uid: uid_t) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", "-U", String(uid), name]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

/// Algo que limpa itens e transmite o andamento.
public protocol Cleaning: Sendable {
    func clean(_ items: [JunkItem]) -> AsyncStream<CleanEvent>
}

/// Remove os itens selecionados, validando cada caminho pela política do seu grupo.
public final class CleanEngine: Cleaning {
    private let policyProvider: @Sendable () -> [GroupID: PathPolicy]
    private let privileged: any PrivilegedRunner
    private let dryRun: Bool
    private let log: CleanupLog
    private let requiresAdmin: @Sendable (GroupID) -> Bool
    private let processes: any ProcessChecker
    private let commands: any CommandRunner
    private let loginItems: any LoginItemsSource
    private let documentVersions: any DocumentVersionSource

    public init(policies: [GroupID: PathPolicy], privileged: any PrivilegedRunner, dryRun: Bool, log: CleanupLog,
                requiresAdmin: @escaping @Sendable (GroupID) -> Bool = { $0.requiresAdmin },
                processes: any ProcessChecker = SystemProcessChecker(),
                commands: any CommandRunner = SystemCommandRunner(),
                loginItems: any LoginItemsSource = SystemLoginItems(),
                documentVersions: any DocumentVersionSource = SystemDocumentVersions()) {
        self.policyProvider = { policies }
        self.privileged = privileged
        self.dryRun = dryRun
        self.log = log
        self.requiresAdmin = requiresAdmin
        self.processes = processes
        self.commands = commands
        self.loginItems = loginItems
        self.documentVersions = documentVersions
    }

    /// Políticas calculadas na hora da limpeza (raízes podem surgir depois do início do app).
    public init(policyProvider: @escaping @Sendable () -> [GroupID: PathPolicy], privileged: any PrivilegedRunner,
                dryRun: Bool, log: CleanupLog, requiresAdmin: @escaping @Sendable (GroupID) -> Bool = { $0.requiresAdmin },
                processes: any ProcessChecker = SystemProcessChecker(),
                commands: any CommandRunner = SystemCommandRunner(),
                loginItems: any LoginItemsSource = SystemLoginItems(),
                documentVersions: any DocumentVersionSource = SystemDocumentVersions()) {
        self.policyProvider = policyProvider
        self.privileged = privileged
        self.dryRun = dryRun
        self.log = log
        self.requiresAdmin = requiresAdmin
        self.processes = processes
        self.commands = commands
        self.loginItems = loginItems
        self.documentVersions = documentVersions
    }

    public func clean(_ items: [JunkItem]) -> AsyncStream<CleanEvent> {
        AsyncStream { continuation in
            let task = Task {
                let report = await self.perform(items) { continuation.yield($0) }
                continuation.yield(.completed(report))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func perform(_ items: [JunkItem], emit: (CleanEvent) -> Void) async -> CleanReport {
        let policies = policyProvider()
        var seen = Set<String>()
        let leaves = items.flatMap(\.leaves).filter { $0.removal != nil && seen.insert($0.id).inserted }
        var freed: Int64 = 0
        var removed: [String] = []
        var failed: [String: String] = [:]
        var deferred: [(JunkItem, [PrivilegedCommand])] = []
        var restartPreferences = false

        func finish(_ item: JunkItem, _ result: Result<Int64, CleanFailure>) {
            switch result {
            case .success(let bytes):
                freed += bytes
                removed.append(item.id)
            case .failure(let f):
                failed[item.id] = f.reason
            }
            emit(.finished(item, result))
        }

        for item in leaves {
            // Parar: os itens restantes não são tocados.
            if Task.isCancelled { break }
            emit(.started(item))
            guard let removal = item.removal else { continue }
            do {
                try validate(removal, group: item.group, policies: policies)
            } catch {
                finish(item, .failure(error))
                continue
            }
            if case .deleteUnlessRunning(_, let process) = removal, processes.isRunning(process, uid: getuid()) {
                finish(item, .failure(CleanFailure(reason: "in use")))
                continue
            }
            if case .deleteStaleVersion(let url, let link) = removal, Self.resolves(link, to: url) {
                finish(item, .failure(CleanFailure(reason: "now active")))
                continue
            }
            if dryRun {
                finish(item, .success(item.totalSize))
                continue
            }
            if requiresAdmin(item.group) {
                deferred.append((item, commands(for: removal)))
                continue
            }
            do {
                switch removal {
                case .removeSessionLoginItem(let name, let url):
                    guard loginItems.remove(LoginItemEntry(name: name, url: url)) else {
                        throw CleanFailure(reason: "could not remove login item")
                    }
                case .removeFileVersion(let document, let version):
                    guard documentVersions.remove(version: version, of: document) else {
                        throw CleanFailure(reason: "could not remove version")
                    }
                case .deleteSimulator(let udid, let simctl):
                    guard commands.run(simctl, ["delete", udid]).status == 0 else { throw CleanFailure(reason: "simctl delete failed") }
                case .deleteRuntime(let id, let simctl):
                    guard commands.run(simctl, ["runtime", "delete", id]).status == 0 else { throw CleanFailure(reason: "simctl runtime delete failed") }
                case .removeLaunchdItem(let plist, _):
                    _ = commands.run("/bin/launchctl", ["unload", plist.path])
                    try Self.removeUnprivileged(removal)
                case .removePreference(let file):
                    if file.pathExtension.lowercased() != "lockfile" {
                        _ = commands.run("/usr/bin/defaults", ["delete", file.deletingPathExtension().path])
                    }
                    try Self.removeUnprivileged(removal)
                    restartPreferences = true
                default:
                    try Self.removeUnprivileged(removal)
                }
                finish(item, .success(item.totalSize))
            } catch let error as CocoaError where error.code == .fileWriteNoPermission || error.code == .fileReadNoPermission {
                deferred.append((item, commands(for: removal)))
            } catch let error as CleanFailure {
                finish(item, .failure(error))
            } catch {
                if Self.isPermissionError(error) {
                    deferred.append((item, commands(for: removal)))
                } else {
                    finish(item, .failure(CleanFailure(reason: error.localizedDescription)))
                }
            }
        }

        let batch = Task.isCancelled ? [] : deferred.filter { !$0.1.isEmpty }
        for (item, cmds) in deferred where cmds.isEmpty {
            finish(item, .failure(CleanFailure(reason: "unsupported removal")))
        }
        if !batch.isEmpty {
            do {
                let results = try await privileged.run(batch.flatMap(\.1))
                var index = 0
                for (item, cmds) in batch {
                    let slice = results[index..<min(index + cmds.count, results.count)]
                    index += cmds.count
                    if let failure = slice.first(where: { if case .failure = $0 { true } else { false } }),
                       case .failure(let f) = failure {
                        finish(item, .failure(f))
                    } else if slice.count < cmds.count {
                        finish(item, .failure(CleanFailure(reason: "no result")))
                    } else {
                        finish(item, .success(item.totalSize))
                    }
                }
            } catch {
                let reason = switch error {
                case .userCancelled: CleanFailure.cancelled
                case .failed(let message): CleanFailure(reason: message)
                }
                for (item, _) in batch { finish(item, .failure(reason)) }
            }
        }

        if restartPreferences {
            // O cfprefsd guarda as preferências em cache; reiniciá-lo evita que regrave o arquivo apagado.
            _ = commands.run("/usr/bin/killall", ["-u", NSUserName(), "cfprefsd"])
        }
        let report = CleanReport(freedBytes: freed, removed: removed, failed: failed, dryRun: dryRun)
        _ = try? log.write(report)
        return report
    }

    private func validate(_ removal: RemovalAction, group: GroupID, policies: [GroupID: PathPolicy]) throws(CleanFailure) {
        guard let policy = policies[group] else { throw CleanFailure(reason: "no policy for \(group.rawValue)") }
        func check(_ url: URL, allowRoot: Bool = false) throws(CleanFailure) {
            do {
                _ = try policy.validate(url)
            } catch {
                if allowRoot, case .isAllowedRootItself = error { return }
                throw CleanFailure(reason: "path not allowed: \(url.path)")
            }
        }
        switch removal {
        case .delete(let u), .moveToTrash(let u), .deleteStaleVersion(let u, _), .deleteUnlessRunning(let u, _),
             .removePreference(let u):
            try check(u)
        case .removeLaunchdItem(let plist, let helper):
            try check(plist)
            if let helper { try check(helper) }
        case .removeSessionLoginItem:
            break
        case .deleteContents(let u):
            try check(u, allowRoot: true)
        case .thinBinary(let exe, _, let bundle):
            try check(bundle)
            try check(exe)
        case .removeLocalizations(let bundle, let lprojs):
            try check(bundle)
            for l in lprojs { try check(l) }
        case .removeFileVersion, .deleteSimulator, .deleteRuntime:
            break // pela API/ferramenta do sistema, não apaga caminhos diretamente
        case .deleteFiles(let urls):
            for u in urls { try check(u) }
        case .removeOllamaModel(let manifest, _):
            try check(manifest)
        }
    }

    private func commands(for removal: RemovalAction) -> [PrivilegedCommand] {
        switch removal {
        case .delete(let u), .deleteStaleVersion(let u, _), .deleteUnlessRunning(let u, _), .removePreference(let u): [.remove(u)]
        case .removeLaunchdItem(let plist, let helper): (helper.map { [.remove($0)] } ?? []) + [.remove(plist)]
        case .removeSessionLoginItem: []
        case .deleteContents(let u): [.removeContents(u)]
        case .removeLocalizations(_, let lprojs): lprojs.map { .remove($0) }
        case .deleteFiles(let urls): urls.map { .remove($0) }
        case .moveToTrash, .thinBinary, .removeFileVersion, .deleteSimulator, .deleteRuntime, .removeOllamaModel: []
        }
    }

    static func removeUnprivileged(_ removal: RemovalAction) throws {
        let fm = FileManager.default
        /// Já apagado nesta limpeza (caminhos sobrepostos entre grupos): ignora sem erro.
        func gone(_ u: URL) -> Bool {
            var st = stat()
            return lstat(u.path, &st) != 0 && errno == ENOENT
        }
        /// Tira a trava `uchg` antes de apagar (o item seria removido de qualquer forma).
        func unlock(_ u: URL) {
            var st = stat()
            if lstat(u.path, &st) == 0, st.st_flags & UInt32(UF_IMMUTABLE) != 0 {
                lchflags(u.path, st.st_flags & ~UInt32(UF_IMMUTABLE))
            }
        }
        func remove(_ u: URL) throws {
            if gone(u) { return }
            unlock(u)
            try fm.removeItem(at: u)
        }
        switch removal {
        case .delete(let u), .deleteStaleVersion(let u, _), .deleteUnlessRunning(let u, _), .removePreference(let u):
            try remove(u)
        case .removeLaunchdItem(let plist, let helper):
            if let helper { try remove(helper) }
            try remove(plist)
        case .removeSessionLoginItem:
            break
        case .moveToTrash(let u):
            try fm.trashItem(at: u, resultingItemURL: nil)
        case .deleteContents(let u):
            for child in try fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil) {
                try remove(child)
            }
        case .removeLocalizations(_, let lprojs):
            for l in lprojs { try fm.removeItem(at: l) }
        case .deleteFiles(let urls):
            for u in urls { try remove(u) }
        case .removeOllamaModel(let manifest, let store):
            try OllamaStore(root: store).remove(manifest: manifest)
        case .thinBinary, .removeFileVersion, .deleteSimulator, .deleteRuntime:
            throw CleanFailure(reason: "unsupported removal")
        }
    }

    /// O link aponta (depois de resolvido) para `target`?
    static func resolves(_ link: URL, to target: URL) -> Bool {
        PathPolicy.realPath(link.path) == PathPolicy.realPath(target.path)
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code) {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return [Int(EACCES), Int(EPERM)].contains(underlying.code)
        }
        return ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code)
    }
}
