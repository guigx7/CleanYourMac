import Foundation
import Observation
import ServiceManagement
import CleanYourMacCore

/// Instala e acompanha o helper privilegiado (daemon registrado via SMAppService).
@MainActor @Observable
final class HelperManager {
    /// `outdated`: registrado e rodando, mas com um protocolo antigo (o processo antigo segue vivo até reiniciar).
    enum State: Equatable { case notInstalled, needsApproval, active, outdated, unavailable }

    static let shared = HelperManager()
    private(set) var state: State = .notInstalled
    private(set) var lastError: String?
    private let service = SMAppService.daemon(plistName: HelperConstants.plistName)

    init() { refresh() }

    private var runningVersion: Int?

    func refresh() {
        state = Self.state(for: service.status, version: runningVersion)
        Self.isOutdated = state == .outdated
    }

    static func state(for status: SMAppService.Status, version: Int?) -> State {
        switch status {
        case .enabled: version.map { $0 == HelperConstants.version ? .active : .outdated } ?? .active
        case .requiresApproval: .needsApproval
        // Um daemon nunca registrado também aparece como .notFound.
        case .notRegistered, .notFound: .notInstalled
        @unknown default: .unavailable
        }
    }

    /// Pergunta a versão ao helper em execução (o app pode ter sido atualizado com o helper antigo ainda rodando).
    func checkVersion() async {
        guard service.status == .enabled else { return }
        runningVersion = await HelperPrivilegedRunner().version()
        refresh()
    }

    /// Reinicia o helper com o binário novo do app (desregistra e registra de novo).
    func update() {
        try? service.unregister()
        runningVersion = nil
        install()
    }

    /// Registra o daemon. O macOS pede aprovação em Ajustes do Sistema › Itens de Início e Extensões.
    func install() {
        do {
            try service.register()
            lastError = nil
        } catch {
            // Sem aprovação, o registro devolve "Operation not permitted" e o status vira requiresApproval.
            lastError = error.localizedDescription
        }
        refresh()
        if state != .active { SMAppService.openSystemSettingsLoginItems() }
    }

    func uninstall() {
        try? service.unregister()
        refresh()
    }

    /// Ativo e com o protocolo atual (o helper antigo não entende os comandos novos).
    nonisolated(unsafe) static var isOutdated = false

    nonisolated static var isActive: Bool {
        SMAppService.daemon(plistName: HelperConstants.plistName).status == .enabled && !isOutdated
    }

    /// O ajudante recusa daemons de quem não é administrador; essa conta usa a senha (de um administrador).
    nonisolated static let userIsAdmin = HelperExecutor.isAdmin(uid: getuid())
}

/// Usa o helper quando ativo; senão (ou se ele não responder), pede a senha pelo AppleScript.
struct AppPrivilegedRunner: PrivilegedRunner {
    private let helper = HelperPrivilegedRunner()
    private let fallback = AppleScriptPrivilegedRunner()

    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] {
        if HelperManager.isActive, HelperManager.userIsAdmin, let results = try? await helper.run(commands) { return results }
        return try await fallback.run(commands)
    }

    func measure(_ urls: [URL]) async throws(PrivilegedError) -> [Int64?] {
        if HelperManager.isActive, let sizes = try? await helper.measure(urls) { return sizes }
        return try await fallback.measure(urls)
    }
}
