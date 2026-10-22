import Foundation
import Testing
@testable import CleanYourMacCore

/// Mexe na lista de sessão de verdade (com um app de teste `io.github.guigx7.cymtest`, removido no fim).
/// Só roda com `CYM_LOGIN_ITEMS_TEST=1 CYM_TEST_APP=<caminho do .app>`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CYM_LOGIN_ITEMS_TEST"] == "1"))
struct SystemLoginItemsTests {
    @Test func addAndRemoveRealSessionItem() throws {
        let app = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CYM_TEST_APP"]))
        let items = SystemLoginItems()
        let ctx = ScanContext.current()
        #expect(items.add(app))
        let entry = try #require(items.entries(ctx).first { $0.url?.standardizedFileURL.path == app.standardizedFileURL.path })
        #expect(items.remove(entry))
        #expect(!items.entries(ctx).contains { $0.url?.standardizedFileURL.path == app.standardizedFileURL.path })
    }
}
