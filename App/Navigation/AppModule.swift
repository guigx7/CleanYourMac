import SwiftUI

enum AppModule: String, CaseIterable, Identifiable {
    case cleanup, performance, applications, clutter, spaceLens

    var id: String { rawValue }

    /// Módulos já implementados.
    var isAvailable: Bool { true }

    var title: LocalizedStringKey {
        switch self {
        case .cleanup: "module.cleanup"
        case .performance: "module.performance"
        case .applications: "module.applications"
        case .clutter: "module.clutter"
        case .spaceLens: "module.spaceLens"
        }
    }

    var symbol: String {
        switch self {
        case .cleanup: "sparkles"
        case .performance: "bolt.fill"
        case .applications: "square.grid.2x2.fill"
        case .clutter: "doc.on.doc.fill"
        case .spaceLens: "circle.hexagongrid.fill"
        }
    }
}
