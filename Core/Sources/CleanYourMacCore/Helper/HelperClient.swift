import Foundation

/// Fala com o helper privilegiado (daemon registrado pelo app via SMAppService).
public struct HelperPrivilegedRunner: PrivilegedRunner {
    public init() {}

    public func ping() async -> Bool {
        (try? await send(.ping)) != nil
    }

    /// Versão do protocolo do helper em execução (nil se não respondeu).
    public func version() async -> Int? {
        (try? await send(.ping))?.version
    }

    public func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] {
        guard !commands.isEmpty else { return [] }
        let response = try await send(.run(commands))
        return response.results.map { r in
            switch r {
            case .ok: .success(())
            case .refused: .failure(CleanFailure(reason: "path not allowed by helper"))
            case .failed(let e): .failure(CleanFailure(reason: e))
            }
        }
    }

    public func measure(_ urls: [URL]) async throws(PrivilegedError) -> [Int64?] {
        guard !urls.isEmpty else { return [] }
        return try await send(.measure(urls)).sizes
    }

    private func send(_ request: HelperRequest) async throws(PrivilegedError) -> HelperResponse {
        guard let data = try? JSONEncoder().encode(request) else { throw .failed("encode") }
        let reply: Data? = await withCheckedContinuation { cont in
            let connection = NSXPCConnection(machServiceName: HelperConstants.machService, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
            connection.resume()
            let once = Once()
            let errorBox = ConnectionBox(connection)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                if once.claim() { cont.resume(returning: nil) }
                errorBox.connection.invalidate()
            } as? HelperXPCProtocol
            guard let proxy else {
                if once.claim() { cont.resume(returning: nil) }
                return
            }
            let box = ConnectionBox(connection)
            proxy.handle(data) { response in
                if once.claim() { cont.resume(returning: response) }
                box.connection.invalidate()
            }
        }
        guard let reply, let response = try? JSONDecoder().decode(HelperResponse.self, from: reply) else {
            throw .failed("helper unavailable")
        }
        return response
    }
}

/// NSXPCConnection é segura entre threads, mas não é marcada como Sendable.
private final class ConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection
    init(_ connection: NSXPCConnection) { self.connection = connection }
}

/// Garante que a continuação seja retomada uma única vez (resposta ou erro de conexão).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
