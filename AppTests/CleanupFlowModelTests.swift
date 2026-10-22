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
func makeModel(_ scanners: [any GroupScanner], failing: Set<String> = [], privileged: any PrivilegedRunner = NoAdmin(),
               helperActive: Bool = false) -> CleanupFlowModel {
    let ctx = ScanContext(root: URL(fileURLWithPath: "/tmp/cym-stub"), home: URL(fileURLWithPath: "/tmp/cym-stub/home"),
                          userName: "t", preferredLanguages: ["en"], now: .now)
    let logs = FileManager.default.temporaryDirectory.appendingPathComponent("cym-logs-\(UUID())")
    var policies: [GroupID: PathPolicy] = [:]
    for g in GroupID.allCases { policies[g] = PathPolicy(allowedRoots: [URL(fileURLWithPath: "/tmp/cym-stub")]) }
    // Itens em `failing` ficam sem política e falham na validação.
    let cleaner = FailingFilterEngine(failing: failing, policies: policies, logs: logs)
    return CleanupFlowModel(scanEngine: ScanEngine(scanners: scanners),
                            cleanEngine: cleaner,
                            context: ctx, groups: Set(scanners.map(\.group)), privileged: privileged,
                            helperActive: { helperActive })
}

/// Limpeza simulada: os ids em `failing` falham.
struct FailingFilterEngine: Cleaning {
    let failing: Set<String>
    let policies: [GroupID: PathPolicy]
    let logs: URL

    func clean(_ items: [JunkItem]) -> AsyncStream<CleanEvent> {
        let ok = CleanEngine(policies: policies, privileged: NoAdmin(), dryRun: true, log: CleanupLog(directory: logs))
        let failing = failing
        return AsyncStream { cont in
            Task {
                var removed: [String] = [], failed: [String: String] = [:], freed: Int64 = 0
                for await e in ok.clean(items.filter { !failing.contains($0.id) }) {
                    switch e {
                    case .started, .finished: cont.yield(e)
                    case .completed(let r): removed = r.removed; freed = r.freedBytes; failed = r.failed
                    }
                }
                for item in items where failing.contains(item.id) {
                    cont.yield(.started(item))
                    cont.yield(.finished(item, .failure(CleanFailure(reason: "boom"))))
                    failed[item.id] = "boom"
                }
                cont.yield(.completed(CleanReport(freedBytes: freed, removed: removed, failed: failed, dryRun: true)))
                cont.finish()
            }
        }
    }
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

@MainActor @Test func stopScanWithNothingFoundReturnsToIntro() async {
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "a", 1)], delay: .seconds(10))])
    m.startScan()
    try? await Task.sleep(for: .milliseconds(100))
    m.stopScan()
    #expect(m.phase == .intro)
    try? await Task.sleep(for: .milliseconds(300))
    #expect(m.phase == .intro)
    #expect(m.report == nil)
}

@MainActor @Test func stopScanShowsPartialResults() async {
    let m = makeModel([StubScanner(group: .trash, items: [stubItem(.trash, "t", 5)]),
                       StubScanner(group: .userCache, items: [stubItem(.userCache, "a", 1)], delay: .seconds(10))])
    m.startScan()
    await waitFor { m.bytesFound == 5 }
    m.stopScan()
    #expect(m.phase == .results)
    #expect(m.report?.totalSize == 5)
    #expect(m.isPartial)
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
    m.clean(tile: .systemJunk)
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

@MainActor @Test func acknowledgeDoneShowsCompletedTiles() async {
    let a = stubItem(.userCache, "a", 100), u = stubItem(.universalBinaries, "u", 30)
    let m = makeModel([StubScanner(group: .userCache, items: [a]), StubScanner(group: .universalBinaries, items: [u])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.clean(tile: .systemJunk)
    await waitFor { if case .done = m.phase { true } else { false } }
    m.acknowledgeDone()
    #expect(m.phase == .results)
    #expect(m.completedTiles[.systemJunk] == 100)
    #expect(m.report?.groups[.userCache]?.items.isEmpty == true)
    #expect(m.report?.totalSize == 30)
}

@MainActor @Test func closeReviewDiscardsSelection() async {
    let a = stubItem(.userCache, "a", 100)
    let m = makeModel([StubScanner(group: .userCache, items: [a])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.openReview()
    m.selection.toggle(a)
    m.closeReview()
    #expect(m.selection.selectedItems.isEmpty)
}

@MainActor @Test func reviewRemainingSelectsFailures() async {
    let a = stubItem(.userCache, "a", 100)
    let m = makeModel([StubScanner(group: .userCache, items: [a])], failing: [a.id])
    m.startScan()
    await waitFor { m.phase == .results }
    m.clean(items: [a])
    await waitFor { if case .done = m.phase { true } else { false } }
    #expect(m.failures[a.id] != nil)
    m.reviewRemaining()
    #expect(m.phase == .review)
    #expect(m.selection.selectedItems.map(\.id) == [a.id])
}

@MainActor @Test func doneTotalsByKind() async {
    let a = stubItem(.userCache, "a", 100), t = stubItem(.trash, "t", 7), mail = stubItem(.mailAttachments, "m", 3)
    let m = makeModel([StubScanner(group: .userCache, items: [a]), StubScanner(group: .trash, items: [t]),
                       StubScanner(group: .mailAttachments, items: [mail])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.clean(items: [a, t, mail])
    await waitFor { if case .done = m.phase { true } else { false } }
    #expect(m.freedByKind == [.junk: 100, .mail: 3, .trash: 7])
}

// M5: depois de uma limpeza, os itens mantêm títulos localizados e filhos ocultos.
@MainActor @Test func acknowledgeKeepsItemPresentation() async {
    let a = stubItem(.aiAgentsJunk, "a", 10), b = stubItem(.aiAgentsJunk, "b", 10)
    let kind = JunkItem(id: "k", group: .aiAgentsJunk, name: "Caches", url: nil, size: 0, children: [a, b],
                        displaysChildren: false, titleKey: "aiKind.caches")
    let m = makeModel([StubScanner(group: .aiAgentsJunk, items: [kind])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.clean(items: [a])
    await waitFor { if case .done = m.phase { true } else { false } }
    m.acknowledgeDone()
    let kept = m.report?.groups[.aiAgentsJunk]?.items.first
    #expect(kept?.titleKey == "aiKind.caches")
    #expect(kept?.displaysChildren == false)
}

// "Revisar" de um cartão abre o Gerenciador no grupo do cartão (results-screen §1.2).
@MainActor @Test func reviewFromTileOpensItsGroup() async {
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "u", 1000)]),
                       StubScanner(group: .universalBinaries, items: [stubItem(.universalBinaries, "b", 10)]),
                       StubScanner(group: .xcodeJunk, items: [stubItem(.xcodeJunk, "x", 20)])])
    m.startScan()
    await waitFor { m.phase == .results }
    m.openReview(tile: .universalBinaries)
    #expect(m.reviewCategory == .systemJunk)
    #expect(m.reviewGroup == .universalBinaries)
    m.closeReview()
    m.openReview(tile: .xcodeJunk)
    #expect(m.reviewGroup == .xcodeJunk)
    m.closeReview()
    m.openReview()
    #expect(m.reviewGroup == nil)
}

/// Voltar (no topo dos Resultados): leva à Intro sem analisar de novo; Recomeçar analisa de novo.
@MainActor @Test func backAndRescanFromResults() async {
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "a", 100)])])
    m.startScan()
    await waitFor { m.phase != .scanning }
    m.back()
    #expect(m.phase == .intro)
    #expect(m.report == nil)
    m.startScan()
    await waitFor { m.phase != .scanning }
    m.rescan()
    #expect(m.phase == .scanning)
    await waitFor { m.phase != .scanning }
    #expect(m.phase == .results)
}
