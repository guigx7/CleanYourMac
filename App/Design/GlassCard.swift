import SwiftUI

/// Painel de vidro usado nos cartões de resultado.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                // Vidro discreto: mais claro no topo, quase transparente embaixo.
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.05)],
                                          startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

/// Botão secundário translúcido ("Revisar").
struct GlassButtonStyle: ButtonStyle {
    enum Size { case regular, large }
    var prominent = false
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .large ? 15 : 13, weight: .semibold))
            .padding(.horizontal, size == .large ? 20 : 16)
            .padding(.vertical, size == .large ? 10 : 8)
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : .white)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? Color.white.opacity(configuration.isPressed ? 0.75 : 0.94)
                                    : Color.white.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(prominent ? 0 : 0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
