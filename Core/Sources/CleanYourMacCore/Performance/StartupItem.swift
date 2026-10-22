import Foundation

/// De onde vem um item de início ou em segundo plano.
public enum StartupItemKind: String, Codable, Sendable {
    /// Lista de sessão antiga (Ajustes › Itens de Início › "Abrir ao iniciar sessão").
    case sessionLoginItem
    /// Plist em `~/Library/LaunchAgents`.
    case userAgent
    /// Plist em `/Library/LaunchAgents`.
    case systemAgent
    /// Plist em `/Library/LaunchDaemons`.
    case systemDaemon
    /// Registrado pelo próprio app (`SMAppService`); outro app só pode ler.
    case modern

    /// Agentes e daemons do launchd ficam em Itens em Segundo Plano; o resto, em Itens de Início.
    public var defaultIsBackground: Bool {
        switch self {
        case .userAgent, .systemAgent, .systemDaemon: true
        case .sessionLoginItem, .modern: false
        }
    }
}

public enum StartupItemState: String, Codable, Sendable {
    case enabled, disabled
}

public struct StartupItem: Identifiable, Hashable, Sendable {
    /// `"<kind>:<plist, label ou caminho>"`: estável entre análises.
    public let id: String
    public let kind: StartupItemKind
    /// Nome exibido (app dono ou arquivo).
    public let name: String
    /// `Label` do launchd.
    public let label: String?
    public let plist: URL?
    public let program: URL?
    /// App dono, se achado.
    public let ownerApp: URL?
    public let ownerBundleID: String?
    public let state: StartupItemState
    /// Seção Itens em Segundo Plano × Itens de Início.
    public let isBackground: Bool

    public init(kind: StartupItemKind, name: String, label: String? = nil, plist: URL? = nil, program: URL? = nil,
                ownerApp: URL? = nil, ownerBundleID: String? = nil, state: StartupItemState = .enabled,
                isBackground: Bool? = nil) {
        let key = plist?.path ?? label ?? program?.path ?? name
        self.id = "\(kind.rawValue):\(key)"
        self.kind = kind
        self.name = name
        self.label = label
        self.plist = plist
        self.program = program
        self.ownerApp = ownerApp
        self.ownerBundleID = ownerBundleID
        self.state = state
        self.isBackground = isBackground ?? kind.defaultIsBackground
    }
}
