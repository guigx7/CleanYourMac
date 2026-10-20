import SwiftUI

/// Arte do módulo: um disco de vidro espesso com núcleo em relevo e brilhos que cintilam.
/// Em repouso flutua devagar com uma faixa de luz passando; durante a análise um anel orbita.
struct ModuleArtwork: View {
    var module: AppModule
    var isAnimating: Bool
    var size: CGFloat = 320

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvasless(module: module, t: t, active: isAnimating, size: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// O desenho em si, função do tempo `t` (segundos).
private struct Canvasless: View {
    var module: AppModule
    var t: Double
    var active: Bool
    var size: CGFloat

    var body: some View {
        let accent = Theme.accent(for: module)
        let speed = active ? 2.2 : 1.0
        let float = CGFloat(sin(t * 0.9 * speed)) * size * 0.018
        let tilt = sin(t * 0.6 * speed) * 4
        let disc = size * 0.78
        let core = disc * 0.46
        let thickness = disc * 0.07

        ZStack {
            // Halo: respira mais forte durante a análise.
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(active ? 0.5 : 0.32), accent.opacity(0.08), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
                .scaleEffect(1 + CGFloat(sin(t * 1.6 * speed)) * (active ? 0.06 : 0.025))
                .blur(radius: size * 0.05)

            ZStack {
                // Sombra projetada no "chão".
                Ellipse()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: disc * 0.82, height: disc * 0.16)
                    .blur(radius: size * 0.04)
                    .offset(y: disc * 0.56 - float * 1.5)

                // Lateral do disco (espessura).
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x1E5A26), Color(hex: 0x0E3518)], startPoint: .top, endPoint: .bottom))
                    .frame(width: disc, height: disc)
                    .offset(y: thickness)

                // Face de vidro.
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x9BD47A, opacity: 0.78), Color(hex: 0x3F8A3A, opacity: 0.72),
                                                  Color(hex: 0x1F5E27, opacity: 0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        // Luz refratada na borda inferior direita.
                        Circle().trim(from: 0.02, to: 0.22)
                            .stroke(LinearGradient(colors: [accent.opacity(0), accent.opacity(0.35), accent.opacity(0)],
                                                   startPoint: .top, endPoint: .bottom),
                                    style: StrokeStyle(lineWidth: disc * 0.08, lineCap: .round))
                            .padding(disc * 0.06)
                            .blur(radius: disc * 0.05)
                    )
                    .overlay(
                        Circle().fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: UnitPoint(x: 0.35, y: 0.3),
                                                     startRadius: 0, endRadius: disc * 0.55))
                    )
                    .overlay(lightSweep(disc: disc))
                    .overlay(
                        Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.75), accent.opacity(0.25), .white.opacity(0.08)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                                              lineWidth: disc * 0.012)
                    )
                    .overlay(
                        // Borda interna mais escura: dá a sensação de vidro espesso.
                        Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: disc * 0.03).padding(disc * 0.015).blur(radius: 2)
                    )
                    .frame(width: disc, height: disc)

                // Reflexo curvo acompanhando a borda superior esquerda.
                Circle()
                    .trim(from: 0.55, to: 0.78)
                    .stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.85), .white.opacity(0)],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: disc * 0.035, lineCap: .round))
                    .frame(width: disc * 0.86, height: disc * 0.86)
                    .blur(radius: 1.5)

                // Núcleo fosco em relevo.
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: core, height: core)
                        .offset(y: core * 0.07)
                        .blur(radius: core * 0.06)
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0xF7FCF3), Color(hex: 0xD3E6CB), Color(hex: 0xB8D1AE)],
                                             startPoint: .top, endPoint: .bottom))
                        // Chanfro: brilho no topo, sombra interna embaixo.
                        .overlay(Circle().strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                                                       lineWidth: core * 0.035))
                        .overlay(Circle().trim(from: 0.1, to: 0.4).stroke(Color.black.opacity(0.12), lineWidth: core * 0.05)
                                    .padding(core * 0.04).blur(radius: core * 0.02))
                        .frame(width: core, height: core)
                    sparkles(core: core)
                }
            }
            // Inclinação 2D leve (rotação + achatamento): mesmo efeito, sem transformação 3D.
            .rotationEffect(.degrees(tilt * 0.6))
            .scaleEffect(x: 1, y: 1 - CGFloat(abs(tilt)) * 0.004)
            .offset(y: float)

            // Anel orbital durante a análise.
            if active {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(AngularGradient(colors: [.clear, accent, .white], center: .center),
                            style: StrokeStyle(lineWidth: size * 0.016, lineCap: .round))
                    .frame(width: size * 0.95, height: size * 0.95)
                    .rotationEffect(.radians(t * 3.4))
                    .transition(.opacity)
            }
        }
    }

    /// Faixa de luz que atravessa o vidro em diagonal, de tempos em tempos.
    private func lightSweep(disc: CGFloat) -> some View {
        let period = active ? 2.4 : 5.0
        let phase = (t.truncatingRemainder(dividingBy: period)) / period   // 0…1
        let x = CGFloat(phase * 2.4 - 1.2) * disc
        return Rectangle()
            .fill(LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing))
            .frame(width: disc * 0.28, height: disc * 1.6)
            .rotationEffect(.degrees(25))
            .offset(x: x)
            .clipShape(Circle())
            .blendMode(.plusLighter)
    }

    /// Três estrelas de quatro pontas, cada uma cintilando no seu ritmo.
    private func sparkles(core: CGFloat) -> some View {
        let green = Color(hex: 0x3F8A3A)
        let stars: [(x: CGFloat, y: CGFloat, s: CGFloat, phase: Double)] = [
            (0.06, 0.06, 0.46, 0), (-0.2, -0.16, 0.24, 1.7), (0.2, -0.24, 0.17, 3.1),
        ]
        return ZStack {
            ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                let pulse = (sin(t * (active ? 4.0 : 2.0) + star.phase) + 1) / 2   // 0…1
                Sparkle()
                    .fill(LinearGradient(colors: [green.opacity(0.95), Color(hex: 0x2A6B2E)], startPoint: .top, endPoint: .bottom))
                    .frame(width: core * star.s, height: core * star.s)
                    .scaleEffect(0.8 + 0.25 * pulse)
                    .rotationEffect(.degrees(pulse * 12))
                    .opacity(0.65 + 0.35 * pulse)
                    .offset(x: core * star.x, y: core * star.y)
            }
        }
    }
}

/// Estrela de quatro pontas com lados côncavos.
private struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let w = r.width / 2, h = r.height / 2
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - h))
        p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: c)
        p.closeSubpath()
        return p
    }
}
