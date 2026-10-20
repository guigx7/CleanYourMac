import Foundation

public enum CleanEvent: Sendable {
    case started(JunkItem)
    case finished(JunkItem, Result<Int64, CleanFailure>)
    case completed(CleanReport)
}

/// Remove os itens selecionados, validando cada caminho pela política do seu grupo.
public final class CleanEngine: Sendable {
    private let policies: [GroupID: PathPolicy]
    private let privileged: any PrivilegedRunner
    private let dryRun: Bool
    private let log: CleanupLog
    private let requiresAdmin: @Sendable (GroupID) -> Bool

    public init(policies: [GroupID: PathPolicy], privileged: any PrivilegedRunner, dryRun: Bool, log: CleanupLog,
                requiresAdmin: @escaping @Sendable (GroupID) -> Bool = { $0.requiresAdmin }) {
        self.policies = policies
        self.privileged = privileged
        self.dryRun = dryRun
        self.log = log
        self.requiresAdmin = requiresAdmin
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
        var seen = Set<String>()
        let leaves = items.flatMap(\.leaves).filter { $0.removal != nil && seen.insert($0.id).inserted }
        var freed: Int64 = 0
        var removed: [String] = []
        var failed: [String: String] = [:]
        var deferred: [(JunkItem, [PrivilegedCommand])] = []

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
            emit(.started(item))
            guard let removal = item.removal else { continue }
            do {
                try validate(removal, group: item.group)
            } catch {
                finish(item, .failure(error))
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
                try Self.removeUnprivileged(removal)
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

        let batch = deferred.filter { !$0.1.isEmpty }
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

        let report = CleanReport(freedBytes: freed, removed: removed, failed: failed, dryRun: dryRun)
        _ = try? log.write(report)
        return report
    }

    private func validate(_ removal: RemovalAction, group: GroupID) throws(CleanFailure) {
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
        case .delete(let u), .moveToTrash(let u), .removeLoginItem(let u):
            try check(u)
        case .deleteContents(let u):
            try check(u, allowRoot: true)
        case .thinBinary(let exe, _, let bundle):
            try check(bundle)
            try check(exe)
        case .removeLocalizations(let bundle, let lprojs):
            try check(bundle)
            for l in lprojs { try check(l) }
        case .deleteDocumentVersions(let volume, _):
            try check(volume, allowRoot: true)
        }
    }

    private func commands(for removal: RemovalAction) -> [PrivilegedCommand] {
        switch removal {
        case .delete(let u), .removeLoginItem(let u): [.remove(u)]
        case .deleteContents(let u): [.removeContents(u)]
        case .removeLocalizations(_, let lprojs): lprojs.map { .remove($0) }
        case .moveToTrash, .thinBinary, .deleteDocumentVersions: []
        }
    }

    static func removeUnprivileged(_ removal: RemovalAction) throws {
        let fm = FileManager.default
        switch removal {
        case .delete(let u), .removeLoginItem(let u):
            try fm.removeItem(at: u)
        case .moveToTrash(let u):
            try fm.trashItem(at: u, resultingItemURL: nil)
        case .deleteContents(let u):
            for child in try fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil) {
                try fm.removeItem(at: child)
            }
        case .removeLocalizations(_, let lprojs):
            for l in lprojs { try fm.removeItem(at: l) }
        case .thinBinary, .deleteDocumentVersions:
            throw CleanFailure(reason: "unsupported removal")
        }
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
