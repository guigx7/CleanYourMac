import Foundation

/// Resultado da análise do módulo Aplicativos.
public struct AppsReport: Sendable {
    public let apps: [AppRecord]
    /// Um item por app (e por plug-in de áudio).
    public let uninstaller: [JunkItem]
    public let leftovers: [JunkItem]
    public let installers: [JunkItem]
    public let updates: UpdateCheckResult
    public let date: Date

    public init(apps: [AppRecord], uninstaller: [JunkItem], leftovers: [JunkItem], installers: [JunkItem],
                updates: UpdateCheckResult, date: Date = Date()) {
        self.apps = apps
        self.uninstaller = uninstaller
        self.leftovers = leftovers
        self.installers = installers
        self.updates = updates
        self.date = date
    }

    /// Mesmo formato de docs/re/parity/apps-baseline-*.json (scripts/parity/apps_ax_to_baseline.py).
    public func parityJSON() -> [String: Any] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        func entries(_ items: [JunkItem]) -> [[String: Any]] {
            items.map { ["name": $0.url?.lastPathComponent ?? $0.name, "size": $0.totalSize] }
        }
        func related(_ item: JunkItem) -> [String: Any] {
            var out: [String: Any] = [:]
            for kind in item.children { if let k = kind.detail { out[k] = entries(kind.children) } }
            return out
        }
        let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let appsOut: [[String: Any]] = uninstaller.compactMap { item in
            guard let id = item.leaves.first.flatMap({ AppItemID.appID(of: $0.id) }), let app = byID[id], app.kind == .application else { return nil }
            return ["name": app.name, "lastOpened": app.lastOpened.map(day.string(from:)) as Any? ?? NSNull(),
                    "size": item.totalSize, "related": related(item)]
        }
        let filters = AppFilter.counts(apps: apps, selected: [], now: date)
        return [
            "tool": "cym",
            "capturedAt": ISO8601DateFormatter().string(from: date),
            "apps": appsOut,
            "filters": Dictionary(uniqueKeysWithValues: filters.map { ($0.key.parityKey, $0.value) }),
            "updates": updates.updates.map { u -> [String: Any] in
                ["name": u.name.hasSuffix(".app") ? String(u.name.dropLast(4)) : u.name, "source": u.source.rawValue,
                 "installed": u.installedVersion, "available": u.availableVersion]
            },
            "offline": updates.offline,
            "leftovers": [
                "leftoverFiles": leftovers.map { ["name": $0.name, "size": $0.totalSize, "related": related($0)] as [String: Any] },
                "installers": entries(installers),
            ] as [String: Any],
        ]
    }
}

public enum AppsScanPhase: String, Sendable {
    case apps, related, leftovers, installers, updates
}

public enum AppsScanEvent: Sendable {
    case progress(phase: AppsScanPhase, path: String)
    case finished(AppsReport)
}

/// Orquestra a análise: inventário uma vez, depois arquivos relacionados, e sobras, instaladores e atualizações em paralelo.
public final class AppsScan: Sendable {
    private let catalog: AppCatalog
    private let uninstaller: UninstallerScanner
    private let leftovers: LeftoversScanner
    private let installers: InstallersScanner
    private let updates: UpdateChecker

    public init(catalog: AppCatalog, uninstaller: UninstallerScanner, leftovers: LeftoversScanner,
                installers: InstallersScanner, updates: UpdateChecker) {
        self.catalog = catalog
        self.uninstaller = uninstaller
        self.leftovers = leftovers
        self.installers = installers
        self.updates = updates
    }

    public func run(_ context: ScanContext) -> AsyncThrowingStream<AppsScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.progress(phase: .apps, path: context.resolve("/Applications").path))
                    let apps = catalog.apps(context)
                    try Task.checkCancellation()
                    let items = try uninstaller.items(for: apps, context: context) { p in
                        continuation.yield(.progress(phase: .related, path: p.currentPath))
                    }
                    continuation.yield(.progress(phase: .leftovers, path: context.resolve("~/Library/Containers").path))
                    async let checked = updates.check(apps, now: context.now)
                    let found = try leftovers.items(installed: apps, context: context)
                    continuation.yield(.progress(phase: .installers, path: context.home.path))
                    let dmgs = try await installers.scan(context) { _ in }
                    continuation.yield(.progress(phase: .updates, path: ""))
                    let result = await checked
                    try Task.checkCancellation()
                    continuation.yield(.finished(AppsReport(apps: apps, uninstaller: items, leftovers: found, installers: dmgs,
                                                            updates: result, date: context.now)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
