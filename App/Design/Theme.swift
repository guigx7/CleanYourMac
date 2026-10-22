import SwiftUI

/// Tokens visuais do app.
enum Theme {
    static func gradient(for module: AppModule) -> LinearGradient {
        let colors: [Color] = switch module {
        case .cleanup: [Color(hex: 0x0E3A1F), Color(hex: 0x2F6B2A), Color(hex: 0x8FB339)]
        case .performance: [Color(hex: 0x5A1A0C), Color(hex: 0xA2401A), Color(hex: 0xE08A3C)]
        case .applications: [Color(hex: 0x15175E), Color(hex: 0x2A3FB0), Color(hex: 0x4F86E6)]
        case .spaceLens: [Color(hex: 0x1E0B4A), Color(hex: 0x4A1FA0), Color(hex: 0x7B55E0)]
        }
        return LinearGradient(colors: colors, startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    /// Cor de destaque do módulo, usada em brilhos e no botão principal.
    static func accent(for module: AppModule) -> Color {
        switch module {
        case .cleanup: Color(hex: 0x9BD15A)
        case .performance: Color(hex: 0xF2A65A)
        case .applications: Color(hex: 0x7FB2FF)
        case .spaceLens: Color(hex: 0xA98BFF)
        }
    }

    /// Tom escuro do botão principal de cada módulo.
    static func deep(for module: AppModule) -> Color {
        switch module {
        case .cleanup: Color(hex: 0x2F6B2A)
        case .performance: Color(hex: 0xA2401A)
        case .applications: Color(hex: 0x2A3FB0)
        case .spaceLens: Color(hex: 0x4A1FA0)
        }
    }

    /// Tinta das telas claras do Gerenciador de Aplicativos.
    static let appsTint = Color(hex: 0x2F62D8)
    static let perfTint = Color(hex: 0xC4521F)
    static let lensTint = Color(hex: 0x6A44D8)

    /// Tinta das telas claras (Gerenciador de Limpeza).
    static let reviewTint = Color(hex: 0x2E8B47)

    static let glassFill = Color.white.opacity(0.10)
    static let glassStroke = Color.white.opacity(0.18)
    static let secondaryText = Color.white.opacity(0.72)

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
