import SwiftUI

/// Arte do módulo: uma lente de vidro com um núcleo; durante a análise um anel orbita.
struct ModuleArtwork: View {
    var module: AppModule
    var isAnimating: Bool
    var size: CGFloat = 320

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var breathe = false

    var body: some View {
        let accent = Theme.accent(for: module)
        ZStack {
            // Halo
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.35), accent.opacity(0.12), .clear], center: .center,
                                     startRadius: size * 0.05, endRadius: size * 0.5))
                .blur(radius: size * 0.06)
                .scaleEffect(breathe ? 1.08 : 0.96)

            // Lente
            Circle()
                .fill(LinearGradient(colors: [Color.white.opacity(0.32), accent.opacity(0.18), Color.black.opacity(0.25)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.7), accent.opacity(0.3), .white.opacity(0.1)],
                                                              startPoint: .topLeading, endPoint: .bottomTrailing),
                                               lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 24)
                .frame(width: size * 0.82, height: size * 0.82)

            // Reflexo
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.5, height: size * 0.2)
                .offset(x: -size * 0.08, y: -size * 0.26)
                .blur(radius: 2)

            // Núcleo
            Image(systemName: module.symbol)
                .font(.system(size: size * 0.24, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: accent.opacity(0.8), radius: 18)

            // Anel orbital (só durante a análise/limpeza)
            if isAnimating {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(AngularGradient(colors: [.clear, accent, .white], center: .center),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: size * 0.94, height: size * 0.94)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: isAnimating, initial: true) { _, running in
            guard !reduceMotion else { return }
            if running {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { spin = true }
                withAnimation(.easeInOut(duration: 1.2).repeatForever()) { breathe = true }
            } else {
                withAnimation(.easeOut(duration: 0.4)) { spin = false; breathe = false }
            }
        }
        .accessibilityHidden(true)
    }
}
