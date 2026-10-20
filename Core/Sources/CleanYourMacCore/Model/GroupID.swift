/// Cada grupo exibido na segunda coluna do Gerenciador de Limpeza.
public enum GroupID: String, CaseIterable, Codable, Sendable {
    // Detritos do Sistema
    case userCache, systemCache, userLogs, systemLogs, universalBinaries, languageFiles,
         brokenLoginItems, brokenPreferences, documentVersions, deletedUsers, iosBackups, xcodeJunk
    // Acúmulos de IA
    case aiAgentsJunk, localModels
    // Anexos do Mail
    case mailAttachments
    // Lixos
    case trash, mailTrash

    public var category: CategoryID {
        switch self {
        case .userCache, .systemCache, .userLogs, .systemLogs, .universalBinaries, .languageFiles,
             .brokenLoginItems, .brokenPreferences, .documentVersions, .deletedUsers, .iosBackups, .xcodeJunk:
            .systemJunk
        case .aiAgentsJunk, .localModels:
            .aiClutter
        case .mailAttachments:
            .mailAttachments
        case .trash, .mailTrash:
            .trashBins
        }
    }

    /// A limpeza precisa de privilégio de administrador (definido pela spec de cada grupo).
    public var requiresAdmin: Bool {
        switch self {
        case .systemCache, .systemLogs, .deletedUsers: true
        default: false
        }
    }

    /// A análise precisa de privilégio de administrador (definido pela spec de cada grupo).
    public var requiresAdminToScan: Bool {
        switch self {
        case .systemCache: true
        default: false
        }
    }
}
