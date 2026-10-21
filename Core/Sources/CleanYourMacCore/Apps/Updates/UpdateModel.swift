import Foundation

public enum UpdateSourceKind: String, Codable, Sendable {
    case sparkle, appStore, homebrew, macOS
}

/// O que o botão Atualizar faz na etapa 1 (updater.md §Botões).
public enum UpdateAction: Hashable, Sendable {
    case openAppStore(URL, fallback: URL?)
    case openSoftwareUpdate
    /// Abre o próprio app; `notes` abre as novidades.
    case openApp(URL, notes: URL?)
    /// Comando do Homebrew para copiar e a página do fornecedor.
    case copyCommand(String, homepage: URL?)
}

public struct AppUpdate: Identifiable, Hashable, Sendable {
    /// bundleID, ou "macOS:<produto>".
    public let id: String
    /// `AppRecord.id`.
    public let appID: String?
    public let name: String
    public let source: UpdateSourceKind
    /// Versão curta instalada.
    public let installedVersion: String
    public let availableVersion: String
    public let releaseDate: Date?
    /// Tamanho da atualização (nil = desconhecido, nunca 0).
    public let size: Int64?
    /// Texto puro.
    public let notes: String?
    public let action: UpdateAction
    /// Para a etapa 2 (não usado na v0.2).
    public let downloadURL: URL?
    public let expectedTeamID: String?
    public let isCritical: Bool
    /// Atualização de versão principal do macOS.
    public let isMajor: Bool

    public init(id: String, appID: String?, name: String, source: UpdateSourceKind, installedVersion: String,
                availableVersion: String, releaseDate: Date? = nil, size: Int64? = nil, notes: String? = nil,
                action: UpdateAction, downloadURL: URL? = nil, expectedTeamID: String? = nil,
                isCritical: Bool = false, isMajor: Bool = false) {
        self.id = id
        self.appID = appID
        self.name = name
        self.source = source
        self.installedVersion = installedVersion
        self.availableVersion = availableVersion
        self.releaseDate = releaseDate
        self.size = size
        self.notes = notes
        self.action = action
        self.downloadURL = downloadURL
        self.expectedTeamID = expectedTeamID
        self.isCritical = isCritical
        self.isMajor = isMajor
    }
}

/// Resposta de uma fonte para um app.
public enum UpdateVerdict: Sendable {
    case update(AppUpdate)
    /// A fonte respondeu e o app está em dia (encerra a busca).
    case current
    /// Falhou ou não é confiável: vale a próxima fonte.
    case unknown
}

/// Uma fonte de atualizações de apps. Apps ausentes do resultado: a fonte não se aplica a eles.
public protocol UpdateSource: Sendable {
    var kind: UpdateSourceKind { get }
    func check(_ apps: [AppRecord], fetcher: any HTTPFetcher) async -> [String: UpdateVerdict]
}

public struct UpdateCheckResult: Sendable {
    public let updates: [AppUpdate]
    /// Nenhuma requisição deu certo (sem rede).
    public let offline: Bool

    public init(updates: [AppUpdate], offline: Bool) {
        self.updates = updates
        self.offline = offline
    }
}

enum InfoPlist {
    static func read(_ app: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [:] }
        return dict
    }
}

enum Machine {
    static var arch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
