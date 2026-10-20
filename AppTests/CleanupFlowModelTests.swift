import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

struct StubScanner: GroupScanner {
    let group: GroupID
    var items: [JunkItem] = []
    var delay: Duration = .zero
    var steps: [Int64] = []

    func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        for b in steps {
            report(ScanProgress(group: group, currentPath: "/stub/\(b)", bytesFound: b))
            try await Task.sleep(for: .milliseconds(60))
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        return items
    }
}

struct NoAdmin: PrivilegedRunner {
    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] {
        commands.map { _ in .success(()) }
    }
}

func stubItem(_ group: GroupID, _ name: String, _ size: Int64, recommended: Bool = true) -> JunkItem {
    let url = URL(fileURLWithPath: "/tmp/cym-stub/\(name)")
    return JunkItem(group: group, name: name, url: url, size: size, isRecommended: recommended, removal: .delete(url))
}

@MainActor
func makeModel(_ scanners: [any GroupScanner]) -> CleanupFlowModel {
    let ctx = ScanContext(root: URL(fileURLWithPath: "/tmp/cym-stub"), home: URL(fileURLWithPath: "/tmp/cym-stub/home"),
                          userName: "t", preferredLanguages: ["en"], now: .now)
    let logs = FileManager.default.temporaryDirectory.appendingPathComponent("cym-logs-\(UUID())")
    var policies: [GroupID: PathPolicy] = [:]
    for g in GroupID.allCases { policies[g] = PathPolicy(allowedRoots: [URL(fileURLWithPath: "/tmp/cym-stub")]) }
    return CleanupFlowModel(scanEngine: ScanEngine(scanners: scanners),
                            cleanEngine: CleanEngine(policies: policies, privileged: NoAdmin(), dryRun: true,
                                                     log: CleanupLog(directory: logs)),
                            context: ctx, groups: Set(scanners.map(\.group)))
}

@MainActor
func waitFor(_ condition: @escaping () -> Bool, timeout: Duration = .seconds(5)) async {
    let start = ContinuousClock.now
    while !condition(), ContinuousClock.now - start < timeout { try? await Task.sleep(for: .milliseconds(20)) }
}

@MainActor @Test func scanGoesToResults() async {
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "a", 100)])])
    #expect(m.phase == .intro)
    m.startScan()
    #expect(m.phase == .scanning)
    await waitFor { m.phase != .scanning }
    #expect(m.phase == .results)
    #expect(m.report?.totalSize == 100)
}

@MainActor @Test func emptyScanGoesToNothingFound() async {
    let m = makeModel([StubScanner(group: .userCache)])
    m.startScan()
    await waitFor { m.phase != .scanning }
    #expect(m.phase == .nothingFound)
}

@MainActor @Test func stopScanReturnsToIntro() async {
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "a", 1)], delay: .seconds(10))])
    m.startScan()
    try? await Task.sleep(for: .milliseconds(100))
    m.stopScan()
    #expect(m.phase == .intro)
    try? await Task.sleep(for: .milliseconds(300))
    #expect(m.phase == .intro)
    #expect(m.report == nil)
}

@MainActor @Test func bytesFoundIncreasesMonotonically() async {
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "a", 300)], steps: [100, 200, 300])])
    var seen: [Int64] = []
    m.startScan()
    while m.phase == .scanning {
        seen.append(m.bytesFound)
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(seen == seen.sorted())
    #expect(m.bytesFound == 300)
}

@MainActor @Test func cleanGoesToDoneWithReport() async {
    let a = stubItem(.userCache, "a", 100)
    let m = makeModel([StubScanner(group: .userCache, items: [a])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.clean(items: [a])
    #expect(m.phase == .cleaning)
    await waitFor { if case .done = m.phase { true } else { false } }
    guard case .done(let report) = m.phase else { Issue.record("não terminou"); return }
    #expect(report.freedBytes == 100)
    #expect(m.freedBytes == 100)
}

@MainActor @Test func cleanRecommendedInCategory() async {
    let a = stubItem(.userCache, "a", 100)
    let b = stubItem(.userCache, "b", 50, recommended: false)
    let c = stubItem(.localModels, "m", 1000)
    let m = makeModel([StubScanner(group: .userCache, items: [a, b]), StubScanner(group: .localModels, items: [c])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.cleanRecommended(in: .systemJunk)
    await waitFor { if case .done = m.phase { true } else { false } }
    guard case .done(let report) = m.phase else { Issue.record("não terminou"); return }
    #expect(report.removed == [a.id])
}

@MainActor @Test func restartClearsState() async {
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "a", 100)])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.restart()
    #expect(m.phase == .intro)
    #expect(m.report == nil)
    #expect(m.bytesFound == 0)
}

@MainActor @Test func reviewOpensAndCloses() async {
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "a", 100)])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.openReview(category: .systemJunk)
    #expect(m.phase == .review)
    #expect(m.reviewCategory == .systemJunk)
    m.closeReview()
    #expect(m.phase == .results)
}
