import Testing
import Foundation
@testable import CleanYourMacCore

/// Executa os comandos privilegiados de verdade (no fixture), como root faria.
final class FakePrivilegedRunner: PrivilegedRunner, @unchecked Sendable {
    var calls: [[PrivilegedCommand]] = []
    var cancel = false

    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] {
        calls.append(commands)
        if cancel { throw .userCancelled }
        return commands.map { cmd in
            do {
                switch cmd {
                case .remove(let u): try FileManager.default.removeItem(at: u)
                case .removeContents(let u):
                    for c in try FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil) {
                        try FileManager.default.removeItem(at: c)
                    }
                default: return .failure(CleanFailure(reason: "unsupported"))
                }
                return .success(())
            } catch {
                return .failure(CleanFailure(reason: "\(error)"))
            }
        }
    }
}

private func leaf(_ t: FixtureTree, _ group: GroupID, _ rel: String, bytes: Int = 4096,
                  removal: ((URL) -> RemovalAction)? = nil) -> JunkItem {
    let u = t.file(rel, bytes: bytes)
    return JunkItem(group: group, name: u.lastPathComponent, url: u, size: FixtureTree.allocated(u),
                    removal: (removal ?? { .delete($0) })(u))
}

private func engine(_ t: FixtureTree, runner: FakePrivilegedRunner = FakePrivilegedRunner(), dryRun: Bool = false,
                    admin: Set<GroupID> = []) -> CleanEngine {
    let policy = PathPolicy(allowedRoots: [t.url("R")])
    var policies: [GroupID: PathPolicy] = [:]
    for g in GroupID.allCases { policies[g] = policy }
    return CleanEngine(policies: policies, privileged: runner, dryRun: dryRun,
                       log: CleanupLog(directory: t.dir("logs")), requiresAdmin: { admin.contains($0) })
}

private func run(_ e: CleanEngine, _ items: [JunkItem]) async -> (CleanReport?, [CleanEvent]) {
    var events: [CleanEvent] = []
    for await ev in e.clean(items) { events.append(ev) }
    if case .completed(let r)? = events.last { return (r, events) }
    return (nil, events)
}

@Test func deletesOnlySelected() async throws {
    let t = FixtureTree()
    let a = leaf(t, .userCache, "R/a")
    let b = leaf(t, .userCache, "R/b")
    let c = leaf(t, .userCache, "R/c")
    let (report, _) = await run(engine(t), [a, b])
    #expect(!FileManager.default.fileExists(atPath: a.url!.path))
    #expect(!FileManager.default.fileExists(atPath: b.url!.path))
    #expect(FileManager.default.fileExists(atPath: c.url!.path))
    #expect(report?.freedBytes == a.size + b.size)
    #expect(Set(report?.removed ?? []) == [a.id, b.id])
}

@Test func parentItemCleansLeaves() async throws {
    let t = FixtureTree()
    let a = leaf(t, .aiAgentsJunk, "R/tool/cache")
    let b = leaf(t, .aiAgentsJunk, "R/tool/logs")
    let parent = JunkItem(group: .aiAgentsJunk, name: "tool", url: nil, size: 0, children: [a, b])
    let (report, _) = await run(engine(t), [parent])
    #expect(report?.removed.count == 2)
}

@Test func deleteContentsKeepsFolder() async throws {
    let t = FixtureTree()
    t.file("R/Trash/x", bytes: 10)
    t.file("R/Trash/y/z", bytes: 10)
    let dir = t.url("R/Trash")
    let it = JunkItem(group: .trash, name: "Trash", url: dir, size: 8192, removal: .deleteContents(of: dir))
    let (report, _) = await run(engine(t), [it])
    #expect(FileManager.default.fileExists(atPath: dir.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    #expect(report?.failed.isEmpty == true)
}

@Test func deleteContentsOfAllowedRootItself() async throws {
    let t = FixtureTree()
    t.file("R/x", bytes: 10)
    let it = JunkItem(group: .trash, name: "R", url: t.url("R"), size: 4096, removal: .deleteContents(of: t.url("R")))
    let (report, _) = await run(engine(t), [it])
    #expect(FileManager.default.fileExists(atPath: t.url("R").path))
    #expect(!FileManager.default.fileExists(atPath: t.url("R/x").path))
    #expect(report?.failed.isEmpty == true)
}

@Test func refusesOutsidePolicy() async throws {
    let t = FixtureTree()
    let outside = t.file("outside/secret", bytes: 10)
    let bad = JunkItem(group: .userCache, name: "secret", url: outside, size: 10, removal: .delete(outside))
    let (report, _) = await run(engine(t), [bad])
    #expect(FileManager.default.fileExists(atPath: outside.path))
    #expect(report?.failed[bad.id] != nil)
}

@Test func refusesItemWithoutPolicy() async throws {
    let t = FixtureTree()
    let a = leaf(t, .userCache, "R/a")
    let e = CleanEngine(policies: [:], privileged: FakePrivilegedRunner(), dryRun: false,
                        log: CleanupLog(directory: t.dir("logs")))
    let (report, _) = await run(e, [a])
    #expect(FileManager.default.fileExists(atPath: a.url!.path))
    #expect(report?.failed[a.id] != nil)
}

@Test func dryRunTouchesNothing() async throws {
    let t = FixtureTree()
    let a = leaf(t, .userCache, "R/a")
    let b = leaf(t, .systemCache, "R/b")
    let before = try FileManager.default.subpathsOfDirectory(atPath: t.url("R").path).sorted()
    let runner = FakePrivilegedRunner()
    let (report, _) = await run(engine(t, runner: runner, dryRun: true, admin: [.systemCache]), [a, b])
    #expect(try FileManager.default.subpathsOfDirectory(atPath: t.url("R").path).sorted() == before)
    #expect(runner.calls.isEmpty)
    #expect(report?.dryRun == true)
    #expect(report?.freedBytes == a.size + b.size)
}

@Test func adminBatchedOnce() async throws {
    let t = FixtureTree()
    let a = leaf(t, .systemCache, "R/a")
    let b = leaf(t, .systemCache, "R/b")
    let c = leaf(t, .userCache, "R/c")
    let runner = FakePrivilegedRunner()
    let (report, _) = await run(engine(t, runner: runner, admin: [.systemCache]), [a, b, c])
    #expect(runner.calls.count == 1)
    #expect(runner.calls.first?.count == 2)
    #expect(report?.removed.count == 3)
}

@Test func noAdminNoPrompt() async throws {
    let t = FixtureTree()
    let runner = FakePrivilegedRunner()
    _ = await run(engine(t, runner: runner), [leaf(t, .userCache, "R/a")])
    #expect(runner.calls.isEmpty)
}

@Test func adminCancelled() async throws {
    let t = FixtureTree()
    let a = leaf(t, .systemCache, "R/a")
    let c = leaf(t, .userCache, "R/c")
    let runner = FakePrivilegedRunner()
    runner.cancel = true
    let (report, _) = await run(engine(t, runner: runner, admin: [.systemCache]), [a, c])
    #expect(report?.failed[a.id] == "cancelled")
    #expect(report?.removed == [c.id])
    #expect(FileManager.default.fileExists(atPath: a.url!.path))
    #expect(!FileManager.default.fileExists(atPath: c.url!.path))
}

@Test func permissionDeniedFallsBackToAdmin() async throws {
    let t = FixtureTree()
    let a = leaf(t, .userCache, "R/locked/a")
    t.chmod("R/locked", 0o555)
    let runner = FakePrivilegedRunner()
    let (_, _) = await run(engine(t, runner: runner), [a])
    #expect(runner.calls.count == 1)
    t.chmod("R/locked", 0o755)
}

@Test func emitsStartedAndFinishedPerItem() async throws {
    let t = FixtureTree()
    let a = leaf(t, .userCache, "R/a")
    let (_, events) = await run(engine(t), [a])
    let started = events.filter { if case .started = $0 { true } else { false } }.count
    let finished = events.filter { if case .finished = $0 { true } else { false } }.count
    #expect(started == 1 && finished == 1)
}

@Test func logWritten() async throws {
    let t = FixtureTree()
    _ = await run(engine(t), [leaf(t, .userCache, "R/a")])
    let logs = try FileManager.default.contentsOfDirectory(atPath: t.url("logs").path)
    #expect(logs.count == 1)
    #expect(logs[0].hasPrefix("cleanup-") && logs[0].hasSuffix(".json"))
    let data = try Data(contentsOf: t.url("logs/\(logs[0])"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(CleanReport.self, from: data).removed.count == 1)
}
