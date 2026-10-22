import Foundation

/// Nome do serviço Mach do helper privilegiado (o mesmo no plist do launchd).
public enum HelperConstants {
    public static let machService = "io.github.guigx7.CleanYourMac.helper"
    public static let plistName = "io.github.guigx7.CleanYourMac.helper.plist"
    public static let clientIdentifier = "io.github.guigx7.CleanYourMac"
    public static let version = 3
}

/// Interface XPC: um único método com JSON para manter o contrato tipado em Swift.
@objc public protocol HelperXPCProtocol {
    func handle(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
}

public enum HelperRequest: Codable, Equatable, Sendable {
    case ping
    case run([PrivilegedCommand])
    case measure([URL])
}

public enum HelperResult: Codable, Equatable, Sendable {
    case ok
    case refused
    case failed(String)
}

public struct HelperResponse: Codable, Sendable {
    public var version = HelperConstants.version
    public var results: [HelperResult] = []
    public var sizes: [Int64?] = []

    public init(results: [HelperResult] = [], sizes: [Int64?] = []) {
        self.results = results
        self.sizes = sizes
    }
}
