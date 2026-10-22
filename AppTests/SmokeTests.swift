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

@MainActor @Test func allPerformanceStringsLocalized() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let tsv = try String(contentsOf: repo.appendingPathComponent("App/Resources/Strings.tsv"), encoding: .utf8)
    var known: [String: [String]] = [:]
    for line in tsv.split(separator: "\n") where !line.hasPrefix("#") {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3 { known[parts[0]] = [parts[1], parts[2]] }
    }
    var used = Set<String>()
    let dir = repo.appendingPathComponent("App/Performance")
    for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #""(perf\.[A-Za-z0-9_.]+[A-Za-z0-9_])""#)
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            used.insert(String(text[Range(m.range(at: 1), in: text)!]))
        }
    }
    // Chaves montadas em tempo de execução.
    for id in MaintenanceTaskID.allCases { used.formUnion(["perf.task.\(id.rawValue).title", "perf.task.\(id.rawValue).description"]) }
    used.formUnion(["perf.confirm.heavy.freeUpPurgeable", "perf.confirm.heavy.reindexSpotlight"])
    used.formUnion(PerformanceCategory.allCases.map { "perf.category.\($0.rawValue)" })
    used.formUnion(["maintenance", "loginItems", "backgroundItems", "timeMachine"].map { "perf.scan.phase.\($0)" })
    for s in PerformanceFlowModel.Section.allCases { used.formUnion(["perf.section.\(s.rawValue)", "perf.section.\(s.rawValue).description"]) }
    for k in PerformanceTile.Kind.allCases {
        used.insert("perf.tile.\(k.rawValue).description")
        if [.freeUpRAM, .thinSnapshots].contains(k) { used.insert("perf.tile.\(k.rawValue).title") }
        else { used.formUnion(["perf.tile.\(k.rawValue).title.one", "perf.tile.\(k.rawValue).title.other"]) }
    }
    for k in ["tasks", "disable", "enable", "remove", "snapshots"] { used.formUnion(["perf.done.\(k).title", "perf.done.\(k).partial"]) }
    for a in ["disable", "enable", "remove"] { used.formUnion(["perf.confirm.\(a).title", "perf.confirm.\(a).message", "perf.action.\(a)"]) }
    for k in ["sessionLoginItem", "userAgent", "systemAgent", "systemDaemon", "modern"] { used.insert("perf.kind.\(k)") }
    used.formUnion(["reason.timedOut", "reason.changed", "reason.openSettings"])
    let missing = used.filter { known[$0] == nil || known[$0]!.contains(where: \.isEmpty) }.sorted()
    #expect(missing.isEmpty, "sem tradução: \(missing)")
}

/// Liberar Espaço Purgável pode apagar capturas locais do Time Machine: a confirmação precisa dizer isso.
@Test func purgeableConfirmationMentionsSnapshots() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let tsv = try String(contentsOf: repo.appendingPathComponent("App/Resources/Strings.tsv"), encoding: .utf8)
    let line = try #require(tsv.split(separator: "\n").first { $0.hasPrefix("perf.confirm.heavy.freeUpPurgeable\t") })
    let parts = line.split(separator: "\t").map(String.init)
    #expect(parts[1].contains("Time Machine snapshots"))
    #expect(parts[2].contains("capturas locais do Time Machine"))
}

@MainActor @Test func allSpaceLensStringsLocalized() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let tsv = try String(contentsOf: repo.appendingPathComponent("App/Resources/Strings.tsv"), encoding: .utf8)
    var known: [String: [String]] = [:]
    for line in tsv.split(separator: "\n") where !line.hasPrefix("#") {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3 { known[parts[0]] = [parts[1], parts[2]] }
    }
    var used = Set<String>()
    let dir = repo.appendingPathComponent("App/SpaceLens")
    for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #""(lens\.[A-Za-z0-9_.]+[A-Za-z0-9_])""#)
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            used.insert(String(text[Range(m.range(at: 1), in: text)!]))
        }
    }
    #expect(used.count > 20)
    let missing = used.filter { known[$0] == nil || known[$0]!.contains(where: \.isEmpty) }.sorted()
    #expect(missing.isEmpty, "sem tradução: \(missing)")
}
