// CleanYourMacHelper — daemon root registrado pelo app (SMAppService).
// Só aceita conexões do CleanYourMac assinado pelo mesmo time e só executa comandos tipados,
// revalidados pelo HelperExecutor (nunca scripts arbitrários).
import Foundation
import Security
import CleanYourMacCore

final class Service: NSObject, HelperXPCProtocol {
    private let executor = HelperExecutor()
    /// Quem pediu, pela conexão XPC (nunca pela mensagem): define o Lixo e o domínio gui/<uid> do launchd.
    private let requester: uid_t

    init(requester: uid_t) {
        self.requester = requester
    }

    func handle(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        guard let req = try? JSONDecoder().decode(HelperRequest.self, from: request) else {
            reply(Data())
            return
        }
        let response = executor.handle(req, requester: requester)
        reply((try? JSONEncoder().encode(response)) ?? Data())
    }
}

final class Delegate: NSObject, NSXPCListenerDelegate {
    let requirement: String

    init(requirement: String) {
        self.requirement = requirement
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.exportedObject = Service(requester: connection.effectiveUserIdentifier)
        connection.resume()
        return true
    }
}

/// Requisito de assinatura do cliente: o app CleanYourMac assinado pelo mesmo time deste helper.
func clientRequirement() -> String {
    var code: SecCode?
    var team = ""
    if SecCodeCopySelf([], &code) == errSecSuccess, let code {
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        if SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let dict = info as? [String: Any], let t = dict[kSecCodeInfoTeamIdentifier as String] as? String {
            team = t
        }
    }
    // Sem time (helper sem assinatura válida): exige algo impossível, recusando todos.
    guard !team.isEmpty else { return "identifier \"\(HelperConstants.clientIdentifier)\" and never" }
    return "identifier \"\(HelperConstants.clientIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
}

let delegate = Delegate(requirement: clientRequirement())
let listener = NSXPCListener(machServiceName: HelperConstants.machService)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
