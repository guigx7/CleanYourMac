import Foundation

/// Loja de onde o app veio (filtro "Lojas" do Desinstalador).
public enum AppStore: String, Codable, Sendable, CaseIterable {
    case appStore, setapp, steam, battleNet, other
}

/// Fornecedor do app (filtro "Fornecedores").
public enum AppVendor: String, Codable, Sendable, CaseIterable {
    case apple, google, jetBrains, macPaw, microsoft, adobe, other
}

public enum AppKind: String, Codable, Sendable {
    case application, audioPlugin
}

/// Um app (ou plug-in) instalado, com os metadados que o módulo Aplicativos exibe.
public struct AppRecord: Identifiable, Hashable, Sendable {
    /// bundleID + "|" + caminho.
    public let id: String
    public let url: URL
    public let bundleID: String
    public let name: String
    public let version: String?
    public let build: String?
    public let teamID: String?
    public let store: AppStore
    public let vendor: AppVendor
    public let kind: AppKind
    public let lastOpened: Date?
    public let lastUpdated: Date?
    /// App da Apple protegido pelo sistema: só pode ser redefinido.
    public let isProtected: Bool
    /// O próprio CleanYourMac.
    public let isSelf: Bool
    public let is32Bit: Bool
    public let bundleSize: Int64
    /// `SUFeedURL` do Info.plist (Sparkle).
    public let feedURL: URL?

    public init(url: URL, bundleID: String, name: String, version: String? = nil, build: String? = nil,
                teamID: String? = nil, store: AppStore = .other, vendor: AppVendor = .other,
                kind: AppKind = .application, lastOpened: Date? = nil, lastUpdated: Date? = nil,
                isProtected: Bool = false, isSelf: Bool = false, is32Bit: Bool = false,
                bundleSize: Int64 = 0, feedURL: URL? = nil) {
        self.id = bundleID + "|" + url.path
        self.url = url
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.build = build
        self.teamID = teamID
        self.store = store
        self.vendor = vendor
        self.kind = kind
        self.lastOpened = lastOpened
        self.lastUpdated = lastUpdated
        self.isProtected = isProtected
        self.isSelf = isSelf
        self.is32Bit = is32Bit
        self.bundleSize = bundleSize
        self.feedURL = feedURL
    }
}

/// Tipos em que os arquivos de um app são agrupados (docs/re/specs/apps/related-files.md).
public enum ResourceKind: String, CaseIterable, Codable, Sendable {
    case applications, binaries, container, crashes, dockIcon, help, installers,
         loginItems, logs, other, plugins, preferences, supportingFiles, userData
}

/// Um arquivo ou pasta ligado a um app.
public struct RelatedFile: Hashable, Sendable {
    public let url: URL
    public let kind: ResourceKind
    public let size: Int64
    /// Marcado por padrão ao revisar.
    public let isSelected: Bool
    public let removal: RemovalAction

    public init(url: URL, kind: ResourceKind, size: Int64, isSelected: Bool, removal: RemovalAction) {
        self.url = url
        self.kind = kind
        self.size = size
        self.isSelected = isSelected
        self.removal = removal
    }
}
