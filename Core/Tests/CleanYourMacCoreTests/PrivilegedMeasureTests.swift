import Testing
import Foundation
@testable import CleanYourMacCore

@Test func measureScriptParsesSizes() throws {
    let urls = [URL(fileURLWithPath: "/tmp/a b"), URL(fileURLWithPath: "/tmp/it's")]
    let script = AppleScriptPrivilegedRunner.makeMeasureScript(urls)
    #expect(script.contains("'/tmp/a b'"))
    #expect(script.contains("'/tmp/it'\\''s'"))
    let sizes = AppleScriptPrivilegedRunner.parseSizes("CYM:0:ok:12\nCYM:1:fail\n", count: 2)
    #expect(sizes == [12 * 1024, nil])
}

final class MeasuringRunner: PrivilegedRunner, @unchecked Sendable {
    var sizes: [String: Int64] = [:]
    var cancel = false
    var measured: [[URL]] = []
    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] { [] }
    func measure(_ urls: [URL]) async throws(PrivilegedError) -> [Int64?] {
        measured.append(urls)
        if cancel { throw .userCancelled }
        return urls.map { sizes[$0.lastPathComponent] }
    }
}

@Test func systemCacheMeasuredWithAdmin() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.dir("Library/Caches/com.apple.iconservices.store")
    t.file("Library/Caches/readable/x", bytes: 10)
    t.dir("System/Library/Caches/com.apple.coresymbolicationd")
    let runner = MeasuringRunner()
    runner.sizes = ["com.apple.iconservices.store": 765_000_000, "com.apple.coresymbolicationd": 40_000]
    let result = try await AdminMeasure.systemCache(context: ctx, runner: runner)
    let names = Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0.totalSize) })
    #expect(names["com.apple.iconservices.store"] == 765_000_000)
    #expect(names["com.apple.coresymbolicationd"] == 40_000)
    #expect(names["readable"] != nil)
    #expect(runner.measured.count == 1)
}
