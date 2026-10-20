import Testing
import Foundation
@testable import CleanYourMacCore

/// O executor roda como root no helper: revalida tudo, independentemente do app.
private func executor(_ t: FixtureTree) -> HelperExecutor {
    HelperExecutor(allowedPrefixes: [t.url("Library/Caches").path, t.url("Users").path])
}

@Test func helper_removesAllowedPath() throws {
    let t = FixtureTree()
    let f = t.file("Library/Caches/com.x/data", bytes: 10)
    let results = executor(t).run([.remove(f.deletingLastPathComponent())])
    #expect(results == [.ok])
    #expect(!FileManager.default.fileExists(atPath: f.path))
}

@Test func helper_refusesOutsideAllowedPrefixes() {
    let t = FixtureTree()
    let f = t.file("etc/hosts", bytes: 10)
    #expect(executor(t).run([.remove(f)]) == [.refused])
    #expect(FileManager.default.fileExists(atPath: f.path))
}

@Test func helper_refusesAllowedRootItselfAndVitalPaths() {
    let t = FixtureTree()
    t.dir("Library/Caches")
    let e = executor(t)
    #expect(e.run([.remove(t.url("Library/Caches"))]) == [.refused])
    #expect(e.run([.remove(URL(fileURLWithPath: "/Applications"))]) == [.refused])
    #expect(e.run([.remove(FileManager.default.homeDirectoryForCurrentUser)]) == [.refused])
}

@Test func helper_refusesSymlinkEscape() {
    let t = FixtureTree()
    let victim = t.file("outside/victim", bytes: 10)
    t.dir("Library/Caches")
    t.symlink("Library/Caches/link", to: t.url("outside"))
    let e = executor(t)
    #expect(e.run([.remove(t.url("Library/Caches/link/victim"))]) == [.refused])
    #expect(e.run([.removeContents(t.url("Library/Caches/link"))]) == [.refused])
    #expect(FileManager.default.fileExists(atPath: victim.path))
    // Apagar o próprio link é permitido e não toca o destino.
    #expect(e.run([.remove(t.url("Library/Caches/link"))]) == [.ok])
    #expect(FileManager.default.fileExists(atPath: victim.path))
}

@Test func helper_removeContentsKeepsFolder() {
    let t = FixtureTree()
    t.file("Library/Caches/box/a", bytes: 10)
    t.file("Library/Caches/box/b/c", bytes: 10)
    #expect(executor(t).run([.removeContents(t.url("Library/Caches/box"))]) == [.ok])
    #expect(FileManager.default.fileExists(atPath: t.url("Library/Caches/box").path))
    #expect((try? FileManager.default.contentsOfDirectory(atPath: t.url("Library/Caches/box").path))?.isEmpty == true)
}

@Test func helper_measureReturnsAllocatedSizes() {
    let t = FixtureTree()
    let f = t.file("Library/Caches/m/x", bytes: 10_000)
    let sizes = executor(t).measure([t.url("Library/Caches/m"), t.url("etc/nope")])
    #expect(sizes == [FixtureTree.allocated(f), nil])
}

@Test func helper_requestRoundTripsAsJSON() throws {
    let req = HelperRequest.run([.remove(URL(fileURLWithPath: "/Library/Caches/x")), .lipoThin(URL(fileURLWithPath: "/Applications/A.app/Contents/MacOS/A"), keepArch: "arm64")])
    let data = try JSONEncoder().encode(req)
    #expect(try JSONDecoder().decode(HelperRequest.self, from: data) == req)
}
