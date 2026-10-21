import Foundation

/// Busca na rede (injetável nos testes).
public protocol HTTPFetcher: Sendable {
    func get(_ url: URL, timeout: Duration) async throws -> Data
}

/// URLSession efêmera: sem cookies nem cache compartilhado; identifica só o app (updater.md §Rede e privacidade).
public struct URLSessionFetcher: HTTPFetcher {
    private let session: URLSession
    private let userAgent: String

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        userAgent = "CleanYourMac/\(version)"
    }

    public func get(_ url: URL, timeout: Duration) async throws -> Data {
        guard url.scheme == "https" || url.scheme == "http" else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url, timeoutInterval: Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
