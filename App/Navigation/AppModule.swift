import SwiftUI

enum AppModule: String, CaseIterable, Identifiable {
    case cleanup, performance, applications, spaceLens

    var id: String { rawValue }

    /// Módulos já implementados.
    var isAvailable: Bool { self != .spaceLens }

    var title: LocalizedStringKey {
        switch self {
        case .cleanup: "module.cleanup"
        case .performance: "module.performance"
        case .applications: "module.applications"
        case .spaceLens: "module.spaceLens"
        }
    }

    var symbol: String {
        switch self {
        case .cleanup: "sparkles"
        case .performance: "bolt.fill"
        case .applications: "square.grid.2x2.fill"
        case .spaceLens: "circle.hexagongrid.fill"
        }
    }
}
