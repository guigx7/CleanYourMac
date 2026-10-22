import SwiftUI
import CleanYourMacCore

/// Cartões da tela de Resultados (docs/re/specs/performance/results-screen.md), na ordem dos dados.
struct PerformanceTile: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case freeUpRAM, maintenance, thinSnapshots, loginItems, backgroundItems
    }

    enum Action: Hashable {
        case review(PerformanceFlowModel.Section)
        /// Roda as tarefas do cartão direto (com o aviso das demoradas).
        case run([MaintenanceTaskID])
    }

    let kind: Kind
    let count: Int
    let actions: [Action]
    /// Símbolos das primeiras tarefas por título (até 3) ou o símbolo do cartão.
    let icons: [String]
    var id: Kind { kind }

    static func tiles(for report: PerformanceReport) -> [PerformanceTile] {
        let ids = report.tasks.map(\.id)
        // A RAM tem cartão próprio; o resto conta como manutenção recomendada (§2.3).
        let weekly = report.recommendedTasks.map(\.id).filter { $0 != .freeUpRAM }
        let login = report.loginItems.filter { $0.state == .enabled }.count
        var out: [PerformanceTile] = []
        for kind in Kind.allCases {
            switch kind {
            case .freeUpRAM where ids.contains(.freeUpRAM):
                out.append(PerformanceTile(kind: kind, count: 1, actions: [.run([.freeUpRAM])], icons: [MaintenanceTaskID.freeUpRAM.symbol]))
            case .maintenance where !weekly.isEmpty:
                let icons = weekly.sorted { $0.localizedTitle.localizedStandardCompare($1.localizedTitle) == .orderedAscending }
                    .prefix(3).map(\.symbol)
                out.append(PerformanceTile(kind: kind, count: weekly.count, actions: [.review(.maintenance), .run(weekly)], icons: icons))
            case .thinSnapshots where ids.contains(.thinSnapshots):
                out.append(PerformanceTile(kind: kind, count: 1, actions: [.review(.snapshots), .run([.thinSnapshots])],
                                           icons: [MaintenanceTaskID.thinSnapshots.symbol]))
            case .loginItems where login > 0:
                out.append(PerformanceTile(kind: kind, count: login, actions: [.review(.loginItems)], icons: ["power"]))
            case .backgroundItems where !report.backgroundItems.isEmpty:
                out.append(PerformanceTile(kind: kind, count: report.backgroundItems.count, actions: [.review(.backgroundItems)],
                                           icons: ["gearshape.2.fill"]))
            default:
                break
            }
        }
        return out
    }
}

extension MaintenanceTaskID {
    var localizedTitle: String { NSLocalizedString("perf.task.\(rawValue).title", comment: "") }

    var symbol: String {
        switch self {
        case .speedUpMail: "envelope.fill"
        case .flushDNS: "network"
        case .freeUpPurgeable: "internaldrive.fill"
        case .reindexSpotlight: "magnifyingglass"
        case .repairPermissions: "lock.shield.fill"
        case .freeUpRAM: "memorychip.fill"
        case .periodicScripts: "calendar.badge.clock"
        case .thinSnapshots: "clock.arrow.circlepath"
        }
    }
}
