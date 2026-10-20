import SwiftUI

/// Painel de vidro usado nos cartões de resultado.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.glassFill)
                    .background(.ultraThinMaterial.opacity(0.35), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.glassStroke, lineWidth: 1)
            }
    }
}

/// Botão secundário translúcido ("Revisar").
struct GlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : .white)
            .background(
                Capsule().fill(prominent ? Color.white.opacity(configuration.isPressed ? 0.75 : 0.92)
                                         : Color.white.opacity(configuration.isPressed ? 0.22 : 0.14))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(prominent ? 0 : 0.2)))
            .contentShape(Capsule())
    }
}
