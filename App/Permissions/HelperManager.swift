import Foundation
import Observation
import ServiceManagement
import CleanYourMacCore

/// Instala e acompanha o helper privilegiado (daemon registrado via SMAppService).
@MainActor @Observable
final class HelperManager {
    enum State: Equatable { case notInstalled, needsApproval, active, unavailable }

    static let shared = HelperManager()
    private(set) var state: State = .notInstalled
    private(set) var lastError: String?
    private let service = SMAppService.daemon(plistName: HelperConstants.plistName)

    init() { refresh() }

    func refresh() {
        state = switch service.status {
        case .enabled: .active
        case .requiresApproval: .needsApproval
        // Um daemon nunca registrado também aparece como .notFound.
        case .notRegistered, .notFound: .notInstalled
        @unknown default: .unavailable
        }
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

    nonisolated static var isActive: Bool {
        SMAppService.daemon(plistName: HelperConstants.plistName).status == .enabled
    }
}

/// Usa o helper quando ativo; senão (ou se ele não responder), pede a senha pelo AppleScript.
struct AppPrivilegedRunner: PrivilegedRunner {
    private let helper = HelperPrivilegedRunner()
    private let fallback = AppleScriptPrivilegedRunner()

    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] {
        if HelperManager.isActive, let results = try? await helper.run(commands) { return results }
        return try await fallback.run(commands)
    }

    func measure(_ urls: [URL]) async throws(PrivilegedError) -> [Int64?] {
        if HelperManager.isActive, let sizes = try? await helper.measure(urls) { return sizes }
        return try await fallback.measure(urls)
    }
}
