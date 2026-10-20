import Testing
import Foundation
@testable import CleanYourMacCore

/// Compila um executável mínimo para as arquiteturas pedidas (cache por conjunto de arquiteturas).
enum MachOFixtures {
    nonisolated(unsafe) private static var cache: [String: URL] = [:]
    private static let lock = NSLock()

    static func binary(_ archs: [String]) -> URL {
        lock.lock(); defer { lock.unlock() }
        let key = archs.joined(separator: "+")
        if let u = cache[key] { return u }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cym-macho-\(key)-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let src = dir.appendingPathComponent("m.c")
        try! "int main(void){return 0;}\n".write(to: src, atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("m")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        p.arguments = archs.flatMap { ["-arch", $0] } + ["-o", out.path, src.path]
        try! p.run(); p.waitUntilExit()
        precondition(p.terminationStatus == 0, "clang falhou")
        cache[key] = out
        return out
    }

    /// Fatia em bytes de uma arquitetura (via lipo).
    static func sliceSize(_ url: URL, _ arch: String) -> Int64 {
        let file = MachOFile(url: url)
        return file?.slices.first { $0.arch == arch }?.size ?? 0
    }
}

private func makeApp(_ t: FixtureTree, _ rel: String, bundleID: String = "com.test.app", main archs: [String]) -> URL {
    let app = t.app(rel, bundleID: bundleID)
    let exe = app.appendingPathComponent("Contents/MacOS/app")
    try! FileManager.default.copyItem(at: MachOFixtures.binary(archs), to: exe)
    return app
}

private func ub(_ t: FixtureTree) -> UniversalBinariesScanner {
    UniversalBinariesScanner(inventory: FolderAppInventory(folders: ["/Applications", "~/Applications", "~/Downloads"]), hostArch: "arm64")
}

private func scan(_ s: any GroupScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}

@Test func ub_fatMainBecomesItem() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = makeApp(t, "Applications/App.app", main: ["arm64", "x86_64"])
    let items = try await scan(ub(t), ctx)
    #expect(items.map(\.name) == ["App.app"])
    let exe = app.appendingPathComponent("Contents/MacOS/app")
    #expect(items[0].totalSize == MachOFixtures.sliceSize(exe, "x86_64"))
    guard case .thinBinary(let e, let arch, let bundle)? = items[0].children.first?.removal else { Issue.record("removal"); return }
    #expect(e.path == exe.path && arch == "arm64" && bundle.standardizedFileURL.path == app.standardizedFileURL.path)
    #expect(!items[0].isRecommended && !items[0].displaysChildren)
}

@Test func ub_frameworkBinaryCountsDylibIgnored() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = makeApp(t, "Applications/App.app", main: ["arm64", "x86_64"])
    let fw = app.appendingPathComponent("Contents/Frameworks/F.framework/Versions/A")
    try FileManager.default.createDirectory(at: fw, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: MachOFixtures.binary(["arm64", "x86_64"]), to: fw.appendingPathComponent("F"))
    try FileManager.default.copyItem(at: MachOFixtures.binary(["arm64", "x86_64"]), to: app.appendingPathComponent("Contents/Frameworks/libx.dylib"))
    #expect(try await scan(ub(t), ctx).first?.children.count == 2)
}

@Test func ub_nonExecutableAndSymlinkIgnored() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = makeApp(t, "Applications/App.app", main: ["arm64", "x86_64"])
    let res = app.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
    let noexec = res.appendingPathComponent("noexec")
    try FileManager.default.copyItem(at: MachOFixtures.binary(["arm64", "x86_64"]), to: noexec)
    chmod(noexec.path, 0o644)
    try FileManager.default.createSymbolicLink(at: res.appendingPathComponent("link"), withDestinationURL: noexec)
    #expect(try await scan(ub(t), ctx).first?.children.count == 1)
}

@Test func ub_sealedToolExcludedUnlessOptional() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = makeApp(t, "Applications/App.app", main: ["arm64", "x86_64"])
    let res = app.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: MachOFixtures.binary(["arm64", "x86_64"]), to: res.appendingPathComponent("tool"))
    let sig = app.appendingPathComponent("Contents/_CodeSignature")
    try FileManager.default.createDirectory(at: sig, withIntermediateDirectories: true)
    let sealed: [String: Any] = ["files": [:], "files2": ["Resources/tool": ["hash2": Data([1])]]]
    try PropertyListSerialization.data(fromPropertyList: sealed, format: .xml, options: 0).write(to: sig.appendingPathComponent("CodeResources"))
    #expect(try await scan(ub(t), ctx).first?.children.count == 1)
    let optional: [String: Any] = ["files": [:], "files2": ["Resources/tool": ["hash2": Data([1]), "optional": true]]]
    try PropertyListSerialization.data(fromPropertyList: optional, format: .xml, options: 0).write(to: sig.appendingPathComponent("CodeResources"))
    #expect(try await scan(ub(t), ctx).first?.children.count == 2)
}

@Test func ub_thinMainNoItem() async throws {
    let t = FixtureTree(); let ctx = t.context()
    _ = makeApp(t, "Applications/App.app", main: ["arm64"])
    #expect(try await scan(ub(t), ctx).isEmpty)
}

@Test func ub_scriptOrX86HelperSkipsApp() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let a = makeApp(t, "Applications/A.app", bundleID: "com.a", main: ["arm64", "x86_64"])
    let script = a.appendingPathComponent("Contents/MacOS/run")
    try "#!/bin/sh\necho hi\n".write(to: script, atomically: true, encoding: .utf8)
    chmod(script.path, 0o755)
    let b = makeApp(t, "Applications/B.app", bundleID: "com.b", main: ["arm64", "x86_64"])
    try FileManager.default.copyItem(at: MachOFixtures.binary(["x86_64"]), to: b.appendingPathComponent("Contents/MacOS/helper"))
    #expect(try await scan(ub(t), ctx).isEmpty)
}

@Test func ub_arm64eHandling() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let a = makeApp(t, "Applications/A.app", bundleID: "com.a", main: ["arm64", "arm64e", "x86_64"])
    _ = makeApp(t, "Applications/B.app", bundleID: "com.b", main: ["arm64e", "x86_64"])
    let items = try await scan(ub(t), ctx)
    #expect(items.map(\.name) == ["A.app"])
    let exe = a.appendingPathComponent("Contents/MacOS/app")
    #expect(items[0].totalSize == MachOFixtures.sliceSize(exe, "arm64e") + MachOFixtures.sliceSize(exe, "x86_64"))
}

@Test func ub_ignoredBundlesAndScope() async throws {
    let t = FixtureTree(); let ctx = t.context()
    for (rel, id) in [("Applications/Apple.app", "com.apple.foo"), ("Applications/Chrome.app", "com.google.Chrome"),
                      ("Applications/Web.app", "com.google.Chrome.app.abc"), ("Applications/Teaser.app", "com.setapp.teaser"),
                      ("Applications/X.bundle/Inner.app", "com.x.inner"), ("Applications/Host.app/Contents/Helpers/Nested.app", "com.nested")] {
        _ = makeApp(t, rel, bundleID: id, main: ["arm64", "x86_64"])
    }
    let mas = makeApp(t, "Applications/Store.app", bundleID: "com.store", main: ["arm64", "x86_64"])
    t.file("Applications/Store.app/Contents/_MASReceipt/receipt", bytes: 10)
    _ = mas
    _ = makeApp(t, "Users/tester/Downloads/Hidden Bar.app", bundleID: "com.dwarvesv.minimalbar", main: ["arm64", "x86_64"])
    _ = makeApp(t, "Applications/Setapp/Spotifast.app", bundleID: "com.spotifast", main: ["arm64", "x86_64"])
    let names = Set(try await scan(ub(t), ctx).map(\.name))
    #expect(names == ["Hidden Bar.app", "Spotifast.app", "Host.app"] || names == ["Hidden Bar.app", "Spotifast.app"])
    #expect(!names.contains("Nested.app") && !names.contains("Inner.app"))
}

@Test func ub_rosettaPreferenceSkips() async throws {
    let t = FixtureTree(); let ctx = t.context()
    _ = makeApp(t, "Applications/App.app", bundleID: "com.rosetta", main: ["arm64", "x86_64"])
    let ls = "Users/tester/Library/Preferences/com.apple.LaunchServices"
    t.dir(ls)
    try PropertyListSerialization.data(fromPropertyList: ["Architectures for x86_64": ["com.rosetta": ["x86_64"]]], format: .xml, options: 0)
        .write(to: t.url("\(ls)/com.apple.LaunchServices.plist"))
    #expect(try await scan(ub(t), ctx).isEmpty)
}

@Test func ub_thinningKeepsSignatureValid() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = makeApp(t, "Applications/App.app", main: ["arm64", "x86_64"])
    let sign = Process()
    sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    sign.arguments = ["--force", "--deep", "--sign", "-", app.path]
    try sign.run(); sign.waitUntilExit()
    let exe = app.appendingPathComponent("Contents/MacOS/app")
    let modeBefore = try FileManager.default.attributesOfItem(atPath: exe.path)[.posixPermissions] as? NSNumber
    let s = ub(t)
    let items = try await scan(s, ctx)
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")))
    var report: CleanReport?
    for await e in engine.clean(items) { if case .completed(let r) = e { report = r } }
    #expect(report?.failed.isEmpty == true)
    #expect(MachOFile(url: exe)?.slices.map(\.arch) == ["arm64"])
    #expect(try FileManager.default.attributesOfItem(atPath: exe.path)[.posixPermissions] as? NSNumber == modeBefore)
    let verify = SystemCommandRunner().run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    #expect(verify.status == 0)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: exe.deletingLastPathComponent().path)
    #expect(leftovers == ["app"])
}

@Test func ub_dryRunChangesNothing() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = makeApp(t, "Applications/App.app", main: ["arm64", "x86_64"])
    let exe = app.appendingPathComponent("Contents/MacOS/app")
    let before = try Data(contentsOf: exe)
    let s = ub(t)
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: true, log: CleanupLog(directory: t.dir("logs")))
    for await _ in engine.clean(try await scan(s, ctx)) {}
    #expect(try Data(contentsOf: exe) == before)
}
