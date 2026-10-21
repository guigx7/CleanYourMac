import Testing
@testable import CleanYourMac

@Test func appTitle() {
    #expect(AppInfo.name == "CleanYourMac")
}

import Foundation
import CleanYourMacCore

/// Toda chave `apps.*` usada no código do módulo (literal ou montada) existe no Strings.tsv em en e pt-BR.
@Test func allAppsStringsLocalized() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let tsv = try String(contentsOf: repo.appendingPathComponent("App/Resources/Strings.tsv"), encoding: .utf8)
    var known: [String: [String]] = [:]
    for line in tsv.split(separator: "\n") where !line.hasPrefix("#") {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3 { known[parts[0]] = [parts[1], parts[2]] }
    }
    var used = Set<String>()
    let dir = repo.appendingPathComponent("App/Applications")
    for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #""(apps\.[A-Za-z0-9_.]+)""#)
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            used.insert(String(text[Range(m.range(at: 1), in: text)!]))
        }
    }
    used.formUnion(ResourceKind.allCases.map { "apps.kind.\($0.rawValue)" })
    used.formUnion(["apps", "related", "leftovers", "installers", "updates"].map { "apps.scan.phase.\($0)" })
    used.formUnion(UninstallerSort.Key.allCases.map { "apps.sort.\($0.rawValue)" })
    used.formUnion(["sparkle", "appStore", "homebrew", "macOS"].map { "apps.source.\($0)" })
    used.formUnion(AppStore.allCases.map { "apps.store.\($0.rawValue)" } + AppVendor.allCases.map { "apps.vendor.\($0.rawValue)" })
    used.formUnion(AppsFlowModel.Section.allCases.map { "apps.section.\($0.rawValue)" })
    for kind in AppsTile.Kind.allCases { used.formUnion(["apps.tile.\(kind.rawValue).title", "apps.tile.\(kind.rawValue).description"]) }
    let missing = used.filter { known[$0] == nil || known[$0]!.contains(where: \.isEmpty) }.sorted()
    #expect(missing.isEmpty, "sem tradução: \(missing)")
}
