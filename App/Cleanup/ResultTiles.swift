import SwiftUI
import CleanYourMacCore

/// Cartões da tela de Resultados (results-screen §1.2).
struct ResultTile: Identifiable, Equatable {
    enum Kind: CaseIterable {
        case systemJunk, aiClutter, mailAttachments, trashBins, universalBinaries,
             xcodeJunk, iosBackups, deletedUsers, documentVersions

        /// Grupos somados no cartão. Detritos do Sistema exclui os grupos que têm cartão próprio.
        var groups: [GroupID] {
            switch self {
            case .systemJunk: [.userCache, .systemCache, .userLogs, .systemLogs, .languageFiles,
                               .brokenLoginItems, .brokenPreferences]
            case .aiClutter: [.aiAgentsJunk, .localModels]
            case .mailAttachments: [.mailAttachments]
            case .trashBins: [.trash, .mailTrash]
            case .universalBinaries: [.universalBinaries]
            case .xcodeJunk: [.xcodeJunk]
            case .iosBackups: [.iosBackups]
            case .deletedUsers: [.deletedUsers]
            case .documentVersions: [.documentVersions]
            }
        }

        var key: String {
            switch self {
            case .systemJunk: "systemJunk"
            case .aiClutter: "aiClutter"
            case .mailAttachments: "mailAttachments"
            case .trashBins: "trashBins"
            case .universalBinaries: "universalBinaries"
            case .xcodeJunk: "xcodeJunk"
            case .iosBackups: "iosBackups"
            case .deletedUsers: "deletedUsers"
            case .documentVersions: "documentVersions"
            }
        }
    }

    let kind: Kind
    let size: Int64
    /// Até 3 maiores grupos com itens (ícones do cartão).
    let iconGroups: [GroupID]

    var id: Kind { kind }
    /// Só o cartão Detritos do Sistema tem Limpar na v1.
    var canClean: Bool { kind == .systemJunk }
    var category: CategoryID { kind.groups[0].category }

    static func make(from report: ScanReport) -> [ResultTile] {
        Kind.allCases.compactMap { kind in
            let sizes = kind.groups.map { ($0, report.groups[$0]?.totalSize ?? 0) }
            let total = sizes.reduce(0) { $0 + $1.1 }
            guard total > 0 else { return nil }
            let icons = sizes.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
            return ResultTile(kind: kind, size: total, iconGroups: Array(icons))
        }
    }
}
