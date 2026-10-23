import SwiftUI
import CleanYourMacCore

extension CategoryID {
    var title: LocalizedStringKey { LocalizedStringKey(stringLiteral: "category." + rawValue) }

    var symbol: String {
        switch self {
        case .systemJunk: "gearshape.2.fill"
        case .aiClutter: "cpu.fill"
        case .mailAttachments: "envelope.fill"
        case .trashBins: "trash.fill"
        case .applications: "square.grid.2x2.fill"
        }
    }
}

extension GroupID {
    var title: LocalizedStringKey { LocalizedStringKey(stringLiteral: "group." + rawValue) }

    var symbol: String {
        switch self {
        case .userCache: "person.crop.circle.badge.clock"
        case .systemCache: "gearshape.arrow.triangle.2.circlepath"
        case .userLogs: "doc.text"
        case .systemLogs: "doc.text.fill"
        case .universalBinaries: "cpu"
        case .languageFiles: "globe"
        case .brokenLoginItems: "power.circle"
        case .brokenPreferences: "slider.horizontal.3"
        case .documentVersions: "doc.on.doc"
        case .deletedUsers: "person.crop.circle.badge.xmark"
        case .iosBackups: "iphone"
        case .xcodeJunk: "hammer"
        case .aiAgentsJunk: "sparkles"
        case .localModels: "brain"
        case .mailAttachments: "paperclip"
        case .trash: "trash"
        case .mailTrash: "envelope.badge"
        case .appUninstall: "square.grid.2x2"
        case .appLeftovers: "puzzlepiece.extension"
        case .appInstallers: "shippingbox"
        }
    }
}

/// Ícone circular de categoria, usado na Intro e nos cartões.
struct CategoryBadge: View {
    var symbol: String
    var size: CGFloat = 34
    var module: AppModule = .cleanup

    private var colors: [Color] {
        switch module {
        case .applications: [Color(hex: 0x8DB6FF), Color(hex: 0x3D63D6)]
        case .performance: [Color(hex: 0xFFB877), Color(hex: 0xC4521F)]
        case .clutter: [Color(hex: 0x8FEDE4), Color(hex: 0x0E8A8F)]
        case .agents: [Color(hex: 0xB9C6F4), Color(hex: 0x4A5C9E)]
        case .spaceLens: [Color(hex: 0xC9B6FF), Color(hex: 0x6A44D8)]
        default: [Color(hex: 0xA6D96A), Color(hex: 0x3E8E3A)]
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: size * 0.03, y: size * 0.02)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: max(1, size * 0.02)))
            .shadow(color: .black.opacity(0.2), radius: size * 0.08, y: size * 0.05)
            .accessibilityHidden(true)
    }
}
