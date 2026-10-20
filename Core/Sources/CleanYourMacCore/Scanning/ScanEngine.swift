import Foundation

/// Roda os scanners pedidos em paralelo e transmite o progresso.
public final class ScanEngine: Sendable {
    private let scanners: [GroupID: any GroupScanner]
    private let maxConcurrent = 4
    private let progressInterval: Duration = .milliseconds(50)

    public init(scanners: [any GroupScanner]) {
        var map: [GroupID: any GroupScanner] = [:]
        for s in scanners { map[s.group] = s }
        self.scanners = map
    }

    public func scan(_ groups: Set<GroupID>, context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
        let selected = GroupID.allCases.filter(groups.contains).compactMap { scanners[$0] }
        let interval = progressInterval
        let limit = maxConcurrent
        return AsyncThrowingStream { continuation in
            let task = Task {
                let throttle = ProgressThrottle(interval: interval)
                var results: [GroupID: GroupResult] = [:]
                await withTaskGroup(of: GroupResult?.self) { tasks in
                    var pending = selected[...]
                    func startNext() {
                        guard let scanner = pending.popFirst() else { return }
                        tasks.addTask {
                            let items: [JunkItem]
                            do {
                                items = try await scanner.scan(context) { p in
                                    if throttle.shouldEmit(p.group) { continuation.yield(.progress(p)) }
                                }
                            } catch {
                                if Task.isCancelled { return nil }
                                items = []
                            }
                            return Task.isCancelled ? nil : GroupResult(group: scanner.group, items: items)
                        }
                    }
                    for _ in 0..<limit { startNext() }
                    for await result in tasks {
                        if let result {
                            results[result.group] = result
                            continuation.yield(.groupFinished(result))
                        }
                        startNext()
                    }
                }
                if Task.isCancelled {
                    continuation.finish(throwing: CancellationError())
                } else {
                    continuation.yield(.finished(ScanReport(groups: results)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// No máximo um evento de progresso por grupo a cada `interval`.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: Duration
    private var last: [GroupID: ContinuousClock.Instant] = [:]

    init(interval: Duration) { self.interval = interval }

    func shouldEmit(_ group: GroupID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = ContinuousClock.now
        if let previous = last[group], now - previous < interval { return false }
        last[group] = now
        return true
    }
}
