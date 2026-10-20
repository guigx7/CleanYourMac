import Testing
import Foundation
@testable import CleanYourMacCore

struct StubScanner: GroupScanner {
    let group: GroupID
    var items: [JunkItem] = []
    var delay: Duration = .zero
    var fails = false

    func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        report(ScanProgress(group: group, currentPath: "/stub/\(group.rawValue)", bytesFound: 0))
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw CocoaError(.fileReadNoPermission) }
        return items
    }
}

func item(_ group: GroupID, _ name: String, _ size: Int64, recommended: Bool = false, children: [JunkItem] = []) -> JunkItem {
    JunkItem(group: group, name: name, url: URL(fileURLWithPath: "/x/\(group.rawValue)/\(name)"), size: size,
             isRecommended: recommended, children: children)
}

private let ctx = ScanContext(root: URL(fileURLWithPath: "/"), home: URL(fileURLWithPath: "/Users/t"),
                              userName: "t", preferredLanguages: ["en"], now: .now)

private func collect(_ engine: ScanEngine, _ groups: Set<GroupID>) async throws -> [ScanEvent] {
    var events: [ScanEvent] = []
    for try await e in engine.scan(groups, context: ctx) { events.append(e) }
    return events
}

@Test func emitsFinishedWithAllGroups() async throws {
    let engine = ScanEngine(scanners: [
        StubScanner(group: .userCache, items: [item(.userCache, "a", 10)]),
        StubScanner(group: .trash, items: [item(.trash, "t", 5)]),
    ])
    let events = try await collect(engine, [.userCache, .trash])
    guard case .finished(let report)? = events.last else { Issue.record("sem finished"); return }
    #expect(Set(report.groups.keys) == [.userCache, .trash])
    #expect(report.totalSize == 15)
    let finishedGroups = events.compactMap { if case .groupFinished(let g) = $0 { g.group } else { nil } }
    #expect(Set(finishedGroups) == [.userCache, .trash])
}

@Test func onlyRequestedGroupsRun() async throws {
    let engine = ScanEngine(scanners: [
        StubScanner(group: .userCache, items: [item(.userCache, "a", 10)]),
        StubScanner(group: .trash, items: [item(.trash, "t", 5)]),
    ])
    let events = try await collect(engine, [.trash])
    guard case .finished(let report)? = events.last else { Issue.record("sem finished"); return }
    #expect(Array(report.groups.keys) == [.trash])
}

@Test func totalsByCategory() async throws {
    let engine = ScanEngine(scanners: [
        StubScanner(group: .userCache, items: [item(.userCache, "a", 10)]),
        StubScanner(group: .systemLogs, items: [item(.systemLogs, "l", 7)]),
        StubScanner(group: .localModels, items: [item(.localModels, "m", 100)]),
    ])
    let events = try await collect(engine, [.userCache, .systemLogs, .localModels])
    guard case .finished(let report)? = events.last else { Issue.record("sem finished"); return }
    #expect(report.totalSize(of: .systemJunk) == 17)
    #expect(report.totalSize(of: .aiClutter) == 100)
    #expect(report.totalSize(of: .trashBins) == 0)
}

@Test func childrenCountedOnceInTotals() async throws {
    let parent = item(.aiAgentsJunk, "Claude", 0, children: [item(.aiAgentsJunk, "cache", 30), item(.aiAgentsJunk, "logs", 12)])
    let engine = ScanEngine(scanners: [StubScanner(group: .aiAgentsJunk, items: [parent])])
    let events = try await collect(engine, [.aiAgentsJunk])
    guard case .finished(let report)? = events.last else { Issue.record("sem finished"); return }
    #expect(report.totalSize == 42)
}

@Test func duplicateIDsCountedOnce() async throws {
    let a = item(.userCache, "a", 10)
    let engine = ScanEngine(scanners: [StubScanner(group: .userCache, items: [a, a])])
    let events = try await collect(engine, [.userCache])
    guard case .finished(let report)? = events.last else { Issue.record("sem finished"); return }
    #expect(report.totalSize == 10)
}

@Test func failingScannerDoesNotAbort() async throws {
    let engine = ScanEngine(scanners: [
        StubScanner(group: .userCache, fails: true),
        StubScanner(group: .trash, items: [item(.trash, "t", 5)]),
    ])
    let events = try await collect(engine, [.userCache, .trash])
    guard case .finished(let report)? = events.last else { Issue.record("sem finished"); return }
    #expect(report.groups[.userCache]?.items.isEmpty == true)
    #expect(report.totalSize == 5)
}

@Test func cancellationStopsQuickly() async throws {
    let engine = ScanEngine(scanners: [StubScanner(group: .userCache, delay: .seconds(10))])
    let start = ContinuousClock.now
    let task = Task { () -> [ScanEvent] in
        var events: [ScanEvent] = []
        do { for try await e in engine.scan([.userCache], context: ctx) { events.append(e) } } catch {}
        return events
    }
    try await Task.sleep(for: .milliseconds(200))
    task.cancel()
    let events = await task.value
    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(!events.contains { if case .finished = $0 { true } else { false } })
}

@Test func recommendedItems() async throws {
    let child = item(.aiAgentsJunk, "cache", 30, recommended: true)
    let parent = item(.aiAgentsJunk, "Claude", 0, children: [child, item(.aiAgentsJunk, "logs", 12)])
    let engine = ScanEngine(scanners: [
        StubScanner(group: .aiAgentsJunk, items: [parent]),
        StubScanner(group: .userCache, items: [item(.userCache, "a", 10, recommended: true), item(.userCache, "b", 1)]),
    ])
    let events = try await collect(engine, [.aiAgentsJunk, .userCache])
    guard case .finished(let report)? = events.last else { Issue.record("sem finished"); return }
    #expect(Set(report.recommendedItems().map(\.name)) == ["cache", "a"])
}

@Test func progressIsThrottled() async throws {
    struct Chatty: GroupScanner {
        let group = GroupID.userCache
        func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
            for i in 0..<10_000 { report(ScanProgress(group: group, currentPath: "/p/\(i)", bytesFound: Int64(i))) }
            return []
        }
    }
    let events = try await collect(ScanEngine(scanners: [Chatty()]), [.userCache])
    let progress = events.filter { if case .progress = $0 { true } else { false } }
    #expect(progress.count >= 1)
    #expect(progress.count < 100)
}
