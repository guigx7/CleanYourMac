import Foundation
import Testing
@testable import CleanYourMacCore

/// Teste real com os itens de teste `io.github.guigx7.cymtest.*` (agente em ~/Library/LaunchAgents carregado e o app de
/// teste na lista de sessão). Desativa, reativa e remove de verdade; no fim os itens estão no Lixo / fora da lista.
/// Só roda com `CYM_REAL_STARTUP_TEST=1 CYM_TEST_APP=<CYMTest.app>`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CYM_REAL_STARTUP_TEST"] == "1"), .serialized)
struct StartupItemsRealTests {
    let label = "io.github.guigx7.cymtest.agent"

    func launchctl(_ args: [String]) -> (status: Int32, output: String) { SystemCommandRunner().run("/bin/launchctl", args) }

    func item(_ ctx: ScanContext, where match: (StartupItem) -> Bool) throws -> StartupItem {
        let found = StartupItemsScanner().items(ctx).first(where: match)
        return try #require(found)
    }

    func ok(_ results: [String: Result<Void, CleanFailure>], _ item: StartupItem) -> Bool {
        if case .success = results[item.id] { return true }
        print("falhou:", item.name, results[item.id] as Any)
        return false
    }

    @Test func realAgentAndSessionItem() async throws {
        let ctx = ScanContext.current()
        let app = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CYM_TEST_APP"]))
        let actions = StartupItemsActions(privileged: AppleScriptPrivilegedRunner(), context: ctx, dryRun: false)
        let gui = "gui/\(ctx.uid)"

        // Agente: desativar → print-disabled mostra disabled e o job sai do launchd.
        var agent = try item(ctx) { $0.label == label }
        #expect(agent.state == .enabled)
        #expect(ok(await actions.perform(.disable, on: [agent]), agent))
        #expect(StartupItemsScanner.parseDisabled(launchctl(["print-disabled", gui]).output)[label] == true)
        #expect(launchctl(["print", "\(gui)/\(label)"]).status != 0)
        agent = try item(ctx) { $0.label == label }
        #expect(agent.state == .disabled)
        // Reativar → volta a rodar.
        #expect(ok(await actions.perform(.enable, on: [agent]), agent))
        #expect(StartupItemsScanner.parseDisabled(launchctl(["print-disabled", gui]).output)[label] == false)
        #expect(launchctl(["print", "\(gui)/\(label)"]).status == 0)
        // Desativar e Remover → plist no Lixo, job descarregado e sem "disabled" sobrando.
        agent = try item(ctx) { $0.label == label }
        _ = await actions.perform(.disable, on: [agent])
        agent = try item(ctx) { $0.label == label }
        #expect(ok(await actions.perform(.remove, on: [agent]), agent))
        #expect(!FileManager.default.fileExists(atPath: agent.plist!.path))
        #expect(launchctl(["print", "\(gui)/\(label)"]).status != 0)
        #expect(StartupItemsScanner.parseDisabled(launchctl(["print-disabled", gui]).output)[label] != true)

        // Item de sessão: desativar → sai da lista e entra no registro; reativar → volta; remover → sai.
        let path = app.standardizedFileURL.path
        var session = try item(ctx) { $0.kind == .sessionLoginItem && $0.program?.standardizedFileURL.path == path }
        #expect(ok(await actions.perform(.disable, on: [session]), session))
        #expect(!SystemLoginItems().entries(ctx).contains { $0.url?.standardizedFileURL.path == path })
        session = try item(ctx) { $0.kind == .sessionLoginItem && $0.program?.standardizedFileURL.path == path }
        #expect(session.state == .disabled)
        #expect(ok(await actions.perform(.enable, on: [session]), session))
        #expect(SystemLoginItems().entries(ctx).contains { $0.url?.standardizedFileURL.path == path })
        session = try item(ctx) { $0.kind == .sessionLoginItem && $0.program?.standardizedFileURL.path == path }
        #expect(ok(await actions.perform(.remove, on: [session]), session))
        #expect(!SystemLoginItems().entries(ctx).contains { $0.url?.standardizedFileURL.path == path })
        #expect(!DisabledLoginItemsStore.standard.load().contains { $0.path == path })
    }
}
