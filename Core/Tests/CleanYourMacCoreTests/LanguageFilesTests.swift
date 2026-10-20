import Testing
import Foundation
@testable import CleanYourMacCore

private func lang(_ keyboard: [String] = []) -> LanguageFilesScanner {
    LanguageFilesScanner(inventory: FolderAppInventory(folders: ["/Applications"]), keyboardLanguages: { keyboard })
}

private func scan(_ s: any GroupScanner, _ ctx: ScanContext) async throws -> [JunkItem] {
    try await s.scan(ctx) { _ in }
}

@discardableResult
private func lproj(_ t: FixtureTree, _ app: String, _ name: String, files: [String: Int] = ["Localizable.strings": 100],
                   under: String = "Contents/Resources") -> URL {
    let dir = t.dir("Applications/\(app)/\(under)/\(name).lproj")
    for (f, size) in files { t.file("Applications/\(app)/\(under)/\(name).lproj/\(f)", bytes: size) }
    return dir
}

private func codes(_ items: [JunkItem]) -> Set<String> { Set(items.compactMap(\.detail)) }

@Test func lang_keepsPreferredLanguages() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR", "en"])
    t.app("Applications/A.app", bundleID: "com.a")
    for l in ["pt-BR", "pt", "pt_PT", "en", "en_GB", "Base", "fr", "de"] { lproj(t, "A.app", l) }
    #expect(codes(try await scan(lang(), ctx)) == ["fr", "de"])
}

@Test func lang_legacyNamesCanonicalized() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR"])
    t.app("Applications/A.app", bundleID: "com.a")
    for l in ["English", "French", "zh_CN", "zh-Hant", "ua", "jp"] { lproj(t, "A.app", l) }
    #expect(codes(try await scan(lang(), ctx)) == ["fr", "zh-Hans", "zh-Hant", "uk", "ja"])
}

@Test func lang_userChineseProtectsAllChinese() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["zh-Hans"])
    t.app("Applications/A.app", bundleID: "com.a")
    for l in ["en", "zh_CN", "zh-Hant", "fr"] { lproj(t, "A.app", l) }
    #expect(codes(try await scan(lang(), ctx)) == ["fr"])
}

@Test func lang_neverLeavesResourcesWithoutLanguage() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR"])
    t.app("Applications/A.app", bundleID: "com.a")
    lproj(t, "A.app", "fr"); lproj(t, "A.app", "de")
    #expect(try await scan(lang(), ctx).isEmpty)
}

@Test func lang_onlyStringsFilesAndEmptyAllowed() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR"])
    t.app("Applications/A.app", bundleID: "com.a")
    lproj(t, "A.app", "en")
    lproj(t, "A.app", "fr", files: ["MainMenu.nib": 100])
    lproj(t, "A.app", "de", files: ["A.strings": 100, "B.stringsdict": 5000])
    t.dir("Applications/A.app/Contents/Resources/it.lproj")
    let items = try await scan(lang(), ctx)
    #expect(codes(items) == ["de", "it"])
    #expect(items.first { $0.detail == "it" }?.totalSize == 0)
}

@Test func lang_sealedLprojExcluded() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR"])
    t.app("Applications/A.app", bundleID: "com.a")
    lproj(t, "A.app", "en"); lproj(t, "A.app", "fr")
    t.dir("Applications/A.app/Contents/_CodeSignature")
    let cr = t.url("Applications/A.app/Contents/_CodeSignature/CodeResources")
    try PropertyListSerialization.data(fromPropertyList: ["files2": ["Resources/fr.lproj/Localizable.strings": ["hash2": Data([1])]]],
                                       format: .xml, options: 0).write(to: cr)
    #expect(try await scan(lang(), ctx).isEmpty)
    try PropertyListSerialization.data(fromPropertyList: ["files2": ["Resources/fr.lproj/Localizable.strings": ["hash2": Data([1]), "optional": true]]],
                                       format: .xml, options: 0).write(to: cr)
    #expect(codes(try await scan(lang(), ctx)) == ["fr"])
}

@Test func lang_frameworkResourcesAndOutsideIgnored() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR"])
    t.app("Applications/A.app", bundleID: "com.a")
    let fw = "Contents/Frameworks/F.framework/Versions/A/Resources"
    lproj(t, "A.app", "en", under: fw); lproj(t, "A.app", "fr", under: fw)
    try FileManager.default.createSymbolicLink(at: t.url("Applications/A.app/Contents/Frameworks/F.framework/Resources"),
                                               withDestinationURL: t.url("Applications/A.app/\(fw)"))
    lproj(t, "A.app", "de", under: "Contents")
    let items = try await scan(lang(), ctx)
    #expect(codes(items) == ["fr"])
    #expect(items.first?.leaves.count == 1)
}

@Test func lang_ignoredApps() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR"])
    for (name, id) in [("Xcode.app", "com.apple.dt.Xcode"), ("Chrome.app", "com.google.Chrome")] {
        t.app("Applications/\(name)", bundleID: id)
        lproj(t, name, "en"); lproj(t, name, "fr")
    }
    t.app("Applications/Store.app", bundleID: "com.store")
    lproj(t, "Store.app", "en"); lproj(t, "Store.app", "fr")
    t.file("Applications/Store.app/Contents/_MASReceipt/receipt", bytes: 1)
    #expect(try await scan(lang(), ctx).isEmpty)
}

@Test func lang_keyboardLanguageProtected() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR"])
    t.app("Applications/A.app", bundleID: "com.a")
    lproj(t, "A.app", "en"); lproj(t, "A.app", "ru"); lproj(t, "A.app", "fr")
    #expect(codes(try await scan(lang(["ru"]), ctx)) == ["fr"])
}

@Test func lang_groupedByLanguageAcrossApps() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR"])
    for app in ["A.app", "B.app"] {
        t.app("Applications/\(app)", bundleID: "com.\(app)")
        lproj(t, app, "en"); lproj(t, app, "fr")
    }
    let fr = try #require(try await scan(lang(), ctx).first { $0.detail == "fr" })
    #expect(fr.children.count == 2)
    #expect(fr.children.allSatisfy { !$0.isRecommended })
}

@Test func lang_removalKeepsSignatureAndApp() async throws {
    let t = FixtureTree(); let ctx = t.context(languages: ["pt-BR"])
    let app = t.app("Applications/A.app", bundleID: "com.a")
    try FileManager.default.copyItem(at: MachOFixtures.binary(["arm64"]), to: app.appendingPathComponent("Contents/MacOS/app"))
    lproj(t, "A.app", "en"); let fr = lproj(t, "A.app", "fr")
    _ = SystemCommandRunner().run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
    let s = lang()
    let items = try await scan(s, ctx)
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")))
    var report: CleanReport?
    for await e in engine.clean(items) { if case .completed(let r) = e { report = r } }
    #expect(report?.failed.isEmpty == true)
    #expect(!FileManager.default.fileExists(atPath: fr.path))
    #expect(SystemCommandRunner().run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0)
}

@Test func lang_removalRejectsNonLproj() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let app = t.app("Applications/A.app", bundleID: "com.a")
    let plist = app.appendingPathComponent("Contents/Info.plist")
    let bad = JunkItem(group: .languageFiles, name: "x", url: nil, size: 1,
                       removal: .removeLocalizations(bundle: app, lprojs: [plist]))
    let s = lang()
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")))
    for await _ in engine.clean([bad]) {}
    #expect(FileManager.default.fileExists(atPath: plist.path))
}
