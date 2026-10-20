import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

struct CancellingRunner: PrivilegedRunner {
    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] { throw .userCancelled }
    func measure(_ urls: [URL]) async throws(PrivilegedError) -> [Int64?] { throw .userCancelled }
}

@MainActor @Test func cleanConfirmationFlags() async {
    let sys = stubItem(.systemCache, "s", 10), uc = stubItem(.userCache, "u", 10), ub = stubItem(.universalBinaries, "b", 10)
    let m = makeModel([StubScanner(group: .userCache, items: [uc])])
    #expect(m.cleanRequirements([uc]) == [])
    #expect(m.cleanRequirements([sys, uc]) == [.admin])
    #expect(m.cleanRequirements([ub]) == [.appManagement])
}

@MainActor @Test func adminMeasureCancelledKeepsReport() async {
    // Um candidato vazio em /Library/Caches do contexto de teste força a medição privilegiada.
    let candidate = URL(fileURLWithPath: "/tmp/cym-stub/Library/Caches/empty-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: candidate) }
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "u", 10)]), StubScanner(group: .systemCache)],
                      privileged: CancellingRunner())
    m.startScan()
    await waitFor { m.phase == .results }
    #expect(m.canMeasureAdminGroups)
    await m.measureAdminGroups()
    #expect(m.adminMeasure == .cancelled)
    #expect(m.report?.totalSize == 10)
    #expect(m.phase == .results)
}

struct SizingRunner: PrivilegedRunner {
    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] { commands.map { _ in .success(()) } }
    func measure(_ urls: [URL]) async throws(PrivilegedError) -> [Int64?] { urls.map { _ in 1_800_000_000 } }
}

@MainActor @Test func helperMeasuresSystemCacheAutomatically() async {
    let candidate = URL(fileURLWithPath: "/tmp/cym-stub/Library/Caches/sys-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: candidate) }
    let m = makeModel([StubScanner(group: .userCache, items: [stubItem(.userCache, "u", 10)]), StubScanner(group: .systemCache)],
                      privileged: SizingRunner(), helperActive: true)
    m.startScan()
    await waitFor { m.adminMeasure == .done }
    #expect(m.report?.groups[.systemCache]?.totalSize == 1_800_000_000)
    #expect(m.cleanRequirements([stubItem(.systemCache, "s", 1)]).isEmpty)
}
