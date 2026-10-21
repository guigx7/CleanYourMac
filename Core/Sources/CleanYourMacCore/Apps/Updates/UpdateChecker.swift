import Foundation

/// Junta as fontes com a prioridade de updater.md §Prioridade entre fontes, com tempo-limite.
public struct UpdateChecker: Sendable {
    private let sources: [any UpdateSource]
    private let macOS: MacOSUpdateSource?
    private let fetcher: any HTTPFetcher
    private let requestTimeout: Duration
    private let totalTimeout: Duration

    public init(sources: [any UpdateSource], macOS: MacOSUpdateSource? = MacOSUpdateSource(),
                fetcher: any HTTPFetcher = URLSessionFetcher(),
                requestTimeout: Duration = .seconds(10), totalTimeout: Duration = .seconds(60)) {
        self.sources = sources
        self.macOS = macOS
        self.fetcher = fetcher
        self.requestTimeout = requestTimeout
        self.totalTimeout = totalTimeout
    }

    /// As fontes de produção.
    public static func production(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> UpdateChecker {
        UpdateChecker(sources: [AppStoreSource(), SparkleSource(home: home), HomebrewSource()])
    }

    private enum Partial: Sendable {
        case verdicts(UpdateSourceKind, [String: UpdateVerdict], Set<String>)
        case system([AppUpdate])
        case timeout
    }

    public func check(_ installed: [AppRecord], now: Date = Date()) async -> UpdateCheckResult {
        let apps = Self.candidates(installed)
        let counter = CountingFetcher(base: fetcher, timeout: requestTimeout)
        var verdicts: [UpdateSourceKind: [String: UpdateVerdict]] = [:]
        var inCaskroom = Set<String>()
        var system: [AppUpdate] = []
        let limit = totalTimeout
        await withTaskGroup(of: Partial.self) { group in
            for source in sources {
                group.addTask {
                    if let brew = source as? HomebrewSource {
                        let r = await brew.checkDetailed(apps, fetcher: counter)
                        return .verdicts(source.kind, r.verdicts, r.inCaskroom)
                    }
                    return .verdicts(source.kind, await source.check(apps, fetcher: counter), [])
                }
            }
            if let macOS { group.addTask { .system(await macOS.updates(now: now)) } }
            group.addTask {
                try? await Task.sleep(for: limit)
                return .timeout
            }
            var remaining = sources.count + (macOS == nil ? 0 : 1)
            while remaining > 0, let next = await group.next() {
                switch next {
                case .verdicts(let kind, let v, let room):
                    verdicts[kind] = v
                    inCaskroom.formUnion(room)
                    remaining -= 1
                case .system(let u):
                    system = u
                    remaining -= 1
                case .timeout:
                    remaining = 0
                }
            }
            group.cancelAll()
        }
        var updates: [AppUpdate] = []
        for app in apps {
            let order: [UpdateSourceKind] = app.store == .appStore ? [.appStore]
                : inCaskroom.contains(app.id) ? [.homebrew, .sparkle] : [.sparkle, .homebrew]
            for kind in order {
                guard let v = verdicts[kind]?[app.id] else { continue }
                if case .unknown = v { continue }
                if case .update(let u) = v { updates.append(u) }
                break
            }
        }
        return UpdateCheckResult(updates: updates + system, offline: counter.attempts > 0 && counter.successes == 0)
    }

    /// Fora: o próprio app, apps protegidos (só pela fonte macOS) e plug-ins. Duplicatas: fica a de maior versão.
    static func candidates(_ apps: [AppRecord]) -> [AppRecord] {
        var best: [String: AppRecord] = [:]
        for app in apps where !app.isSelf && !app.isProtected && app.kind == .application {
            let key = app.bundleID.lowercased()
            if let current = best[key] {
                let order = Version.compare(app.version ?? "", current.version ?? "")
                if order == .orderedDescending || (order != .orderedAscending && app.url.path < current.url.path) { best[key] = app }
            } else {
                best[key] = app
            }
        }
        return apps.filter { best[$0.bundleID.lowercased()]?.id == $0.id }
    }
}

/// Aplica o tempo-limite por requisição e conta tentativas e sucessos (para saber se está sem rede).
final class CountingFetcher: HTTPFetcher, @unchecked Sendable {
    private let base: any HTTPFetcher
    private let timeout: Duration
    private let lock = NSLock()
    private var _attempts = 0, _successes = 0

    init(base: any HTTPFetcher, timeout: Duration) {
        self.base = base
        self.timeout = timeout
    }

    var attempts: Int { lock.lock(); defer { lock.unlock() }; return _attempts }
    var successes: Int { lock.lock(); defer { lock.unlock() }; return _successes }

    func get(_ url: URL, timeout: Duration) async throws -> Data {
        count { $0._attempts += 1 }
        let data = try await base.get(url, timeout: min(timeout, self.timeout))
        count { $0._successes += 1 }
        return data
    }

    private func count(_ change: (CountingFetcher) -> Void) {
        lock.lock(); defer { lock.unlock() }
        change(self)
    }
}
