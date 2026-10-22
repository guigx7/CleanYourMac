import Testing
import Foundation
@testable import CleanYourMac

@MainActor
@Suite struct SettingsAboutTests {
    /// Cada estado do ajudante tem um texto próprio e uma ação (ou nenhuma, se não há o que fazer).
    @Test func helperStatusAndAction() {
        let states: [HelperManager.State] = [.notInstalled, .needsApproval, .active, .outdated, .unavailable]
        let keys = states.map(SettingsView.helperStatusKey)
        #expect(Set(keys).count == states.count)
        #expect(SettingsView.helperActionKey(.notInstalled) == "helper.install")
        #expect(SettingsView.helperActionKey(.needsApproval) == "helper.approve")
        #expect(SettingsView.helperActionKey(.outdated) == "helper.update")
        #expect(SettingsView.helperActionKey(.active) == "settings.helper.remove")
        #expect(SettingsView.helperActionKey(.unavailable) == nil)
    }

    @Test func versionLine() {
        #expect(AboutView.versionLine(short: "0.4.0", build: "5") == String(format: NSLocalizedString("about.version", comment: ""), "0.4.0", "5"))
    }

    @Test func sidebarPagesLocalized() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let tsv = try String(contentsOf: repo.appendingPathComponent("App/Resources/Strings.tsv"), encoding: .utf8)
        var known: [String: [String]] = [:]
        for line in tsv.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 3 { known[parts[0]] = [parts[1], parts[2]] }
        }
        var used = Set<String>()
        for name in ["SettingsView.swift", "AboutView.swift"] {
            let text = try String(contentsOf: repo.appendingPathComponent("App/Navigation/" + name), encoding: .utf8)
            let regex = try NSRegularExpression(pattern: #""((?:settings|about|helper|sidebar)\.[A-Za-z0-9_.]+[A-Za-z0-9_])""#)
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                used.insert(String(text[Range(m.range(at: 1), in: text)!]))
            }
        }
        used.formUnion([HelperManager.State.notInstalled, .needsApproval, .active, .outdated, .unavailable].map(SettingsView.helperStatusKey))
        #expect(used.count > 10)
        let missing = used.filter { known[$0] == nil || known[$0]!.contains(where: \.isEmpty) }.sorted()
        #expect(missing.isEmpty, "sem tradução: \(missing)")
    }
}
