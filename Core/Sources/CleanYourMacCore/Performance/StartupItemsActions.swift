import Foundation

public enum StartupAction: Sendable {
    case disable, enable, remove
}

public enum StartupWarning: Hashable, Sendable {
    /// O app dono continua instalado e pode recriar o item ao abrir (background-items.md §7.7).
    case ownerMayRecreate(URL)
}

/// Desativar, Reativar e Remover (login-items.md §7, background-items.md §7). Cada item é revalidado antes da ação;
/// o que precisa de root vai num único lote do ajudante. Remover leva para o Lixo, nunca o app dono.
public struct StartupItemsActions: Sendable {
    private let loginItems: any LoginItemsSource
    private let commands: any CommandRunner
    private let privileged: any PrivilegedRunner
    private let trasher: any Trasher
    private let disabledRecord: DisabledLoginItemsStore
    private let context: ScanContext
    private let dryRun: Bool

    public init(loginItems: any LoginItemsSource = SystemLoginItems(), commands: any CommandRunner = SystemCommandRunner(),
                privileged: any PrivilegedRunner, trasher: any Trasher = FileTrasher(),
                disabledRecord: DisabledLoginItemsStore = .standard, context: ScanContext, dryRun: Bool) {
        self.loginItems = loginItems
        self.commands = commands
        self.privileged = privileged
        self.trasher = trasher
        self.disabledRecord = disabledRecord
        self.context = context
        self.dryRun = dryRun
    }

    public func warnings(for item: StartupItem) -> [StartupWarning] {
        guard item.kind != .sessionLoginItem, let app = item.ownerApp, FileManager.default.fileExists(atPath: app.path) else { return [] }
        return [.ownerMayRecreate(app)]
    }

    public func perform(_ action: StartupAction, on items: [StartupItem]) async -> [String: Result<Void, CleanFailure>] {
        var results: [String: Result<Void, CleanFailure>] = [:]
        var batch: [(String, [PrivilegedCommand])] = []
        for item in items {
            if dryRun {
                results[item.id] = .success(())
                continue
            }
            switch item.kind {
            case .sessionLoginItem:
                results[item.id] = session(action, item)
            case .modern:
                // Sem API pública para outro app; a UI abre os Ajustes.
                results[item.id] = .failure(CleanFailure(reason: "open settings"))
            case .userAgent, .systemAgent, .systemDaemon:
                guard let job = revalidated(item) else {
                    results[item.id] = .failure(CleanFailure(reason: "item changed"))
                    continue
                }
                if let privilegedCommands = rootCommands(action, item, job) {
                    batch.append((item.id, privilegedCommands))
                } else {
                    results[item.id] = userLaunchd(action, item, job)
                }
            }
        }
        guard !batch.isEmpty else { return results }
        do throws(PrivilegedError) {
            let out = try await privileged.run(batch.flatMap(\.1))
            var i = 0
            for (id, cmds) in batch {
                let slice = out.indices.contains(i + cmds.count - 1) ? Array(out[i..<i + cmds.count]) : []
                i += cmds.count
                if slice.isEmpty {
                    results[id] = .failure(CleanFailure(reason: "no result"))
                } else if let f = slice.lazy.compactMap({ r -> CleanFailure? in if case .failure(let f) = r { f } else { nil } }).first {
                    results[id] = .failure(f)
                } else {
                    results[id] = .success(())
                }
            }
        } catch {
            let reason = switch error {
            case .userCancelled: CleanFailure.cancelled
            case .failed(let message): CleanFailure(reason: message)
            }
            for (id, _) in batch { results[id] = .failure(reason) }
        }
        return results
    }

    // MARK: - Lista de sessão

    private func session(_ action: StartupAction, _ item: StartupItem) -> Result<Void, CleanFailure> {
        guard let app = item.program else { return .failure(CleanFailure(reason: "item changed")) }
        let entry = loginItems.entries(context).first { $0.url?.standardizedFileURL == app.standardizedFileURL }
        var record = disabledRecord.load()
        switch action {
        case .disable:
            guard let entry else { return .failure(CleanFailure(reason: "item changed")) }
            // Grava antes de tirar da lista; se tirar falhar, desfaz.
            record.removeAll { $0.path == app.path }
            record.append(DisabledLoginItem(name: entry.name ?? item.name, path: app.path, bundleIdentifier: item.ownerBundleID, disabledAt: Date()))
            do { try disabledRecord.save(record) } catch { return .failure(CleanFailure(reason: "record not saved")) }
            guard loginItems.remove(entry) else {
                record.removeAll { $0.path == app.path }
                try? disabledRecord.save(record)
                return .failure(CleanFailure(reason: "login item not removed"))
            }
            return .success(())
        case .enable:
            guard entry != nil || loginItems.add(app) else { return .failure(CleanFailure(reason: "login item not added")) }
            record.removeAll { $0.path == app.path }
            try? disabledRecord.save(record)
            return .success(())
        case .remove:
            if let entry, !loginItems.remove(entry) { return .failure(CleanFailure(reason: "login item not removed")) }
            if record.contains(where: { $0.path == app.path }) {
                record.removeAll { $0.path == app.path }
                try? disabledRecord.save(record)
            }
            return .success(())
        }
    }

    // MARK: - launchd

    private struct Job {
        let plist: URL
        let label: String
        /// Bundle ID do app dono, ou o próprio Label (o ajudante revalida o vínculo).
        let owner: String
    }

    /// O plist ainda é um arquivo comum (não link) com o mesmo Label da análise, e não é da Apple.
    private func revalidated(_ item: StartupItem) -> Job? {
        guard let plist = item.plist, let label = item.label, !StartupItemsScanner.isExcluded(label) else { return nil }
        var st = stat()
        guard lstat(plist.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
              let dict = NSDictionary(contentsOf: plist) as? [String: Any], dict["Label"] as? String == label else { return nil }
        return Job(plist: plist, label: label, owner: item.ownerBundleID ?? label)
    }

    /// Executável em /Library/PrivilegedHelperTools com o nome do Label ou do plist (background-items.md §7.6).
    private func helperTool(_ item: StartupItem, _ job: Job) -> URL? {
        guard let program = item.program else { return nil }
        let tools = PathPolicy.realPath(context.root.appendingPathComponent("Library/PrivilegedHelperTools").path)
        let folder = PathPolicy.realPath(program.deletingLastPathComponent().path)
        let name = program.lastPathComponent
        guard folder == tools, name == job.label || name == job.plist.deletingPathExtension().lastPathComponent,
              FileManager.default.fileExists(atPath: program.path) else { return nil }
        return program
    }

    /// `nil` quando a ação roda sem root.
    private func rootCommands(_ action: StartupAction, _ item: StartupItem, _ job: Job) -> [PrivilegedCommand]? {
        switch (action, item.kind) {
        case (.disable, .systemDaemon): [.launchdDisable(plist: job.plist, owner: job.owner)]
        case (.enable, .systemDaemon): [.launchdEnable(plist: job.plist, owner: job.owner)]
        case (.remove, .systemDaemon), (.remove, .systemAgent):
            [.launchdBootout(plist: job.plist, owner: job.owner), .trash(job.plist, owner: job.owner)]
                + (helperTool(item, job).map { [.trash($0, owner: job.owner)] } ?? [])
        default: nil
        }
    }

    /// Agentes no domínio `gui/<uid>`, sem root.
    private func userLaunchd(_ action: StartupAction, _ item: StartupItem, _ job: Job) -> Result<Void, CleanFailure> {
        let domain = "gui/\(context.uid)", target = "\(domain)/\(job.label)"
        func launchctl(_ args: [String], okStatus: Set<Int32> = [0]) -> Bool {
            okStatus.contains(commands.run("/bin/launchctl", args).status)
        }
        switch action {
        case .disable:
            guard launchctl(["disable", target]) else { return .failure(CleanFailure(reason: "launchctl disable failed")) }
            return launchctl(["bootout", target], okStatus: [0, 3, 113]) ? .success(()) : .failure(CleanFailure(reason: "launchctl bootout failed"))
        case .enable:
            guard launchctl(["enable", target]) else { return .failure(CleanFailure(reason: "launchctl enable failed")) }
            return launchctl(["bootstrap", domain, job.plist.path], okStatus: [0, 17, 37])
                ? .success(()) : .failure(CleanFailure(reason: "launchctl bootstrap failed"))
        case .remove:
            guard launchctl(["bootout", target], okStatus: [0, 3, 113]) else { return .failure(CleanFailure(reason: "launchctl bootout failed")) }
            do {
                try trasher.trash(job.plist)
                return .success(())
            } catch {
                return .failure(CleanFailure(reason: error.localizedDescription))
            }
        }
    }
}
