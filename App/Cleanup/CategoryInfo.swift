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
        }
    }
}

/// Ícone circular de categoria, usado na Intro e nos cartões.
struct CategoryBadge: View {
    var symbol: String
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.accent(for: .cleanup).opacity(0.55)))
            .overlay(Circle().strokeBorder(.white.opacity(0.3)))
    }
}
