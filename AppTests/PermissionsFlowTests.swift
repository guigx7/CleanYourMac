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

@MainActor @Test func oldHelperAsksReinstall() {
    #expect(HelperManager.state(for: .enabled, version: 1) == .outdated)
    #expect(HelperManager.state(for: .enabled, version: HelperConstants.version) == .active)
    // Sem resposta do ping (ainda subindo): continua ativo; o plano B do AppleScript cobre.
    #expect(HelperManager.state(for: .enabled, version: nil) == .active)
    #expect(HelperManager.state(for: .requiresApproval, version: nil) == .needsApproval)
}

@MainActor @Test func appManagementNeededForAppsInApplications() {
    let ctx = ScanContext(root: URL(fileURLWithPath: "/tmp/cym-stub"), home: URL(fileURLWithPath: "/tmp/cym-stub/home"),
                          userName: "t", preferredLanguages: ["en"], now: .now)
    func leaf(_ path: String, _ removal: (URL) -> RemovalAction) -> JunkItem {
        let u = URL(fileURLWithPath: path)
        return JunkItem(id: AppItemID.leaf(mode: .uninstall, appID: "com.x|/Applications/X.app", path: path), group: .appUninstall,
                        name: u.lastPathComponent, url: u, size: 1, removal: removal(u))
    }
    let bundle = leaf("/tmp/cym-stub/Applications/X.app") { .trashAppBundle($0) }
    let system = leaf("/tmp/cym-stub/Library/Application Support/X") { .moveToTrash($0) }
    let home = leaf("/tmp/cym-stub/home/Library/Caches/com.x") { .moveToTrash($0) }
    let report = AppsReport(apps: [], uninstaller: [], leftovers: [], installers: [], updates: UpdateCheckResult(updates: [], offline: false))
    let m = AppsFlowModel(scan: StubAppsScan(report: report), cleaner: RecordingCleaner(), runningApps: StubRunning(), context: ctx)
    #expect(m.requirements([bundle]) == [.appManagement])
    #expect(m.requirements([system]) == [.admin])
    #expect(m.requirements([home]) == [])
    let withHelper = AppsFlowModel(scan: StubAppsScan(report: report), cleaner: RecordingCleaner(), runningApps: StubRunning(),
                                   context: ctx, helperActive: { true })
    #expect(withHelper.requirements([system]) == [])
}

@MainActor @Test func helperV2AsksUpdate() {
    #expect(HelperManager.state(for: .enabled, version: 2) == .outdated)
}

@MainActor @Test func performanceRequirements() async {
    let s = PerfSetup()
    let m = await s.scanned()
    let google = m.report!.backgroundItems[0], user = m.report!.backgroundItems[1], warp = m.report!.loginItems[0]
    // Sem o ajudante: tarefas de root e itens do sistema pedem a senha.
    #expect(m.requirements(tasks: [.flushDNS, .speedUpMail]) == [.admin])
    #expect(m.requirements(tasks: [.speedUpMail, .freeUpPurgeable]).isEmpty)
    #expect(m.requirements(items: [google], action: .disable) == [.admin])
    #expect(m.requirements(items: [user, warp], action: .remove).isEmpty)
    // Agente de /Library/LaunchAgents: desativar sem root, remover com root.
    let agent = StartupItem(kind: .systemAgent, name: "a", label: "a", plist: URL(fileURLWithPath: "/Library/LaunchAgents/a.plist"))
    #expect(m.requirements(items: [agent], action: .disable).isEmpty)
    #expect(m.requirements(items: [agent], action: .remove) == [.admin])
    // Com o ajudante ativo, nada pede senha.
    let withHelper = PerformanceFlowModel(scan: StubPerformanceScan(report: perfReport()), maintenance: s.maintenance, startup: s.startup,
                                          snapshots: { _ in [:] }, context: ScanContext.current(), helperActive: { true })
    #expect(withHelper.requirements(tasks: [.flushDNS]).isEmpty)
    #expect(withHelper.requirements(items: [google], action: .disable).isEmpty)
}
