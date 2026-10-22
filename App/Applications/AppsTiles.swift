import SwiftUI
import CleanYourMacCore

/// Cartões da tela de Resultados (docs/re/specs/apps/results-screen.md), na ordem dos dados.
extension LocalizedStringKey {
    /// Chave montada em tempo de execução (a interpolação num literal viraria um marcador na chave).
    static func dynamic(_ key: String) -> LocalizedStringKey { LocalizedStringKey(key) }
}

struct AppsTile: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case macOSUpdates, appUpdates, uninstaller, bit32, leftovers, installers
    }

    enum Action: Hashable {
        /// Abre o Gerenciador numa seção (e filtro).
        case review(AppsFlowModel.Section, focus: AppsFlowModel.Focus?)
        case openSoftwareUpdate
        /// Marca os recomendados do cartão e segue para a ação (com as confirmações de sempre).
        case removeRecommended
    }

    let kind: Kind
    /// Bytes (sobras, instaladores) ou contagem (atualizações, apps).
    let size: Int64
    let count: Int
    var id: Kind { kind }

    var actions: [Action] {
        switch kind {
        case .macOSUpdates: [.review(.updater, focus: .systemUpdates), .openSoftwareUpdate]
        case .appUpdates: [.review(.updater, focus: nil)]
        case .uninstaller: [.review(.uninstaller, focus: nil)]
        case .bit32: [.review(.uninstaller, focus: nil), .removeRecommended]
        case .leftovers: [.review(.leftovers, focus: nil), .removeRecommended]
        case .installers: [.review(.leftovers, focus: .installers)]
        }
    }

    static func tiles(for report: AppsReport) -> [AppsTile] {
        let apps = report.apps.filter { $0.kind == .application }
        let system = report.updates.updates.filter { $0.source == .macOS && !$0.isMajor }
        let appUpdates = report.updates.updates.filter { $0.source != .macOS }
        var out: [AppsTile] = []
        for kind in Kind.allCases {
            switch kind {
            case .macOSUpdates where !system.isEmpty:
                out.append(AppsTile(kind: kind, size: 0, count: system.count))
            case .appUpdates where !appUpdates.isEmpty:
                out.append(AppsTile(kind: kind, size: 0, count: appUpdates.count))
            case .uninstaller where apps.contains { !$0.isProtected && !$0.isSelf }:
                out.append(AppsTile(kind: kind, size: 0, count: apps.count))
            case .bit32 where apps.contains(where: \.is32Bit):
                let ids = Set(apps.filter(\.is32Bit).map(\.id))
                let size = report.uninstaller.filter { ids.contains(appID(of: $0) ?? "") }.reduce(0) { $0 + $1.totalSize }
                out.append(AppsTile(kind: kind, size: size, count: ids.count))
            case .leftovers where !report.leftovers.isEmpty:
                out.append(AppsTile(kind: kind, size: report.leftovers.reduce(0) { $0 + $1.totalSize }, count: report.leftovers.count))
            case .installers where !report.installers.isEmpty:
                out.append(AppsTile(kind: kind, size: report.installers.reduce(0) { $0 + $1.totalSize }, count: report.installers.count))
            default:
                break
            }
        }
        return out
    }

    /// Itens que o botão de ação direta marca.
    static func recommendedItems(for kind: Kind, in report: AppsReport) -> [JunkItem] {
        switch kind {
        case .leftovers: return report.leftovers
        case .bit32:
            let ids = Set(report.apps.filter(\.is32Bit).map(\.id))
            return report.uninstaller.filter { ids.contains(appID(of: $0) ?? "") }
        default: return []
        }
    }

    static func appID(of item: JunkItem) -> String? { item.leaves.first.flatMap { AppItemID.appID(of: $0.id) } }

    var symbol: String {
        switch kind {
        case .macOSUpdates: "gearshape.arrow.triangle.2.circlepath"
        case .appUpdates: "arrow.down.app.fill"
        case .uninstaller: "xmark.bin.fill"
        case .bit32: "memorychip"
        case .leftovers: "puzzlepiece.extension.fill"
        case .installers: "shippingbox.fill"
        }
    }
}
