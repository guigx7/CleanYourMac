import SwiftUI
import CleanYourMacCore

struct IntroView: View {
    var onScan: () -> Void

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .cleanup, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 18) {
                Text("cleanup.intro.title")
                    .font(Theme.display(46))
                Text("cleanup.intro.subtitle")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(CategoryID.cleanupCases, id: \.self) { c in
                        HStack(spacing: 14) {
                            CategoryBadge(symbol: c.symbol)
                            Text(c.title).font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                .padding(.top, 10)
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.scan", action: onScan)
        }
    }
}

/// Layout comum das telas do módulo: arte à esquerda, texto à direita, ação centralizada embaixo.
struct ModuleStage<Art: View, Side: View, Action: View>: View {
    @ViewBuilder var art: Art
    @ViewBuilder var side: Side
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 40) {
                art.frame(maxWidth: .infinity)
                side.frame(maxWidth: 420, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 40)
            action.padding(.bottom, 36)
        }
    }
}

/// Botão circular principal (Analisar / Parar / Limpar).
struct PrimaryRoundButton: View {
    var title: LocalizedStringKey
    var size: CGFloat = 96
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.accent(for: .cleanup).opacity(0.9), Color(hex: 0x2F6B2A)],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: Theme.accent(for: .cleanup).opacity(hovering ? 0.7 : 0.45), radius: hovering ? 26 : 18)
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1.5))
                .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy(duration: 0.2)) { hovering = h } }
        .keyboardShortcut(.defaultAction)
    }
}
