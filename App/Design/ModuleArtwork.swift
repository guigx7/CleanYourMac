import SwiftUI
import AppKit

/// Arte do módulo: um disco de vidro espesso com núcleo em relevo e brilhos que cintilam.
/// As camadas são rasterizadas uma vez e animadas pelo Core Animation (fora do main thread),
/// então o movimento fica fluido mesmo com o app ocupado na análise.
struct ModuleArtwork: View {
    var module: AppModule
    var isAnimating: Bool
    var size: CGFloat = 320

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ArtworkLayerView(layers: ArtworkLayers.cached(accent: Theme.accent(for: module), size: size, scale: displayScale),
                         size: size, active: isAnimating,
                         animate: !reduceMotion && ProcessInfo.processInfo.environment["CYM_STATIC_ART"] == nil)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Camadas CALayer com animações CABasicAnimation (rodam no servidor de renderização).
private struct ArtworkLayerView: NSViewRepresentable {
    let layers: ArtworkLayers
    let size: CGFloat
    let active: Bool
    let animate: Bool

    func makeNSView(context: Context) -> ArtworkNSView {
        let v = ArtworkNSView(layers: layers, size: size)
        v.configure(active: active, animate: animate)
        return v
    }

    func updateNSView(_ view: ArtworkNSView, context: Context) {
        view.configure(active: active, animate: animate)
    }
}

final class ArtworkNSView: NSView {
    private let size: CGFloat
    private let halo = CALayer(), floorShadow = CALayer(), group = CALayer(), discLayer = CALayer()
    private let bandHolder = CALayer(), band = CALayer(), orbit = CAShapeLayer()
    private var stars: [CALayer] = []
    private var state: (Bool, Bool)?

    fileprivate init(layers: ArtworkLayers, size: CGFloat) {
        self.size = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        let root = layer!
        root.masksToBounds = false
        let disc = size * 0.78, core = disc * 0.46
        let center = CGPoint(x: size / 2, y: size / 2)
        func image(_ l: CALayer, _ img: NSImage, _ w: CGFloat, _ h: CGFloat, _ p: CGPoint) {
            l.contents = img
            l.contentsGravity = .resizeAspect
            l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            l.position = p
        }
        image(halo, layers.halo, size, size, center)
        // Coordenadas do CALayer crescem para cima: a sombra fica abaixo do centro.
        image(floorShadow, layers.shadow, disc * 0.95, disc * 0.22, CGPoint(x: center.x, y: center.y - disc * 0.56))
        group.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        group.position = center
        image(discLayer, layers.disc, disc * 1.2, disc * 1.2, CGPoint(x: size / 2, y: size / 2))
        // Faixa de luz recortada pelo círculo da face.
        bandHolder.bounds = CGRect(x: 0, y: 0, width: disc, height: disc)
        bandHolder.position = CGPoint(x: size / 2, y: size / 2)
        let mask = CAShapeLayer()
        mask.path = CGPath(ellipseIn: bandHolder.bounds, transform: nil)
        bandHolder.mask = mask
        bandHolder.compositingFilter = "plusL"
        image(band, layers.band, disc * 0.3, disc * 1.6, CGPoint(x: disc / 2, y: disc / 2))
        band.setAffineTransform(CGAffineTransform(rotationAngle: -25 * .pi / 180))
        bandHolder.addSublayer(band)
        group.addSublayer(discLayer)
        group.addSublayer(bandHolder)
        let specs: [(x: CGFloat, y: CGFloat, s: CGFloat)] = [(0.06, 0.06, 0.46), (-0.2, -0.16, 0.24), (0.2, -0.24, 0.17)]
        for spec in specs {
            let star = CALayer()
            image(star, layers.star, core * spec.s, core * spec.s,
                  CGPoint(x: size / 2 + core * spec.x, y: size / 2 - core * spec.y))
            group.addSublayer(star)
            stars.append(star)
        }
        // Anel orbital (arco com degradê de opacidade simulado por linha + sombra).
        orbit.bounds = CGRect(x: 0, y: 0, width: size * 0.95, height: size * 0.95)
        orbit.position = center
        orbit.path = CGPath(ellipseIn: orbit.bounds.insetBy(dx: size * 0.008, dy: size * 0.008), transform: nil)
        orbit.fillColor = nil
        orbit.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        orbit.lineWidth = size * 0.016
        orbit.lineCap = .round
        orbit.strokeStart = 0
        orbit.strokeEnd = 0.28
        orbit.shadowColor = NSColor(Theme.accent(for: .cleanup)).cgColor
        orbit.shadowRadius = size * 0.02
        orbit.shadowOpacity = 1
        orbit.shadowOffset = .zero
        for l in [halo, floorShadow, group, orbit] { root.addSublayer(l) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    func configure(active: Bool, animate: Bool) {
        guard state.map({ $0 != (active, animate) }) ?? true else { return }
        state = (active, animate)
        for l in [halo, floorShadow, group, band, orbit] + stars { l.removeAllAnimations() }
        orbit.isHidden = !active
        guard animate else { return }
        let speed = active ? 2.2 : 1.0

        func loop(_ key: String, from: Any, to: Any, duration: Double, reverse: Bool = true, delay: Double = 0,
                  timing: CAMediaTimingFunctionName = .easeInEaseOut) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.toValue = to
            a.duration = duration
            a.autoreverses = reverse
            a.repeatCount = .infinity
            a.beginTime = CACurrentMediaTime() + delay
            a.timingFunction = CAMediaTimingFunction(name: timing)
            a.isRemovedOnCompletion = false
            return a
        }
        let breathe = 3.2 / speed
        group.add(loop("transform.translation.y", from: -size * 0.018, to: size * 0.018, duration: breathe), forKey: "float")
        group.add(loop("transform.rotation.z", from: 2.4 * .pi / 180, to: -2.4 * .pi / 180, duration: breathe), forKey: "tilt")
        halo.add(loop("transform.scale", from: 0.97, to: active ? 1.07 : 1.03, duration: breathe), forKey: "halo")
        halo.opacity = active ? 1 : 0.8
        floorShadow.add(loop("transform.scale", from: 1.0, to: 0.94, duration: breathe), forKey: "shadowScale")
        floorShadow.add(loop("opacity", from: 1.0, to: 0.75, duration: breathe), forKey: "shadowFade")

        // Faixa de luz: atravessa e espera um pouco antes de passar de novo.
        let disc = size * 0.78
        let pass = CABasicAnimation(keyPath: "position.x")
        pass.fromValue = -disc * 0.7
        pass.toValue = disc * 1.7
        pass.duration = 2.6 / speed
        pass.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // Na pausa entre passagens a faixa fica parada fora do disco (no fim da passagem),
        // e a posição de repouso também é fora dele — nunca volta ao centro.
        pass.fillMode = .both
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.position.x = -disc * 0.7
        CATransaction.commit()
        let sweep = CAAnimationGroup()
        sweep.animations = [pass]
        sweep.duration = pass.duration + (active ? 0.4 : 1.6)
        sweep.repeatCount = .infinity
        sweep.isRemovedOnCompletion = false
        band.add(sweep, forKey: "sweep")

        for (i, star) in stars.enumerated() {
            let d = [1.7, 2.3, 2.9][i] / speed
            star.add(loop("transform.scale", from: 0.82, to: 1.05, duration: d, delay: Double(i) * 0.35), forKey: "twinkle")
            star.add(loop("opacity", from: 0.7, to: 1.0, duration: d, delay: Double(i) * 0.35), forKey: "fade")
        }
        if active {
            orbit.add(loop("transform.rotation.z", from: 0, to: -2 * Double.pi, duration: 1.6, reverse: false, timing: .linear),
                      forKey: "orbit")
        }
    }
}

/// Camadas da arte rasterizadas uma vez (na escala da tela).
@MainActor
fileprivate struct ArtworkLayers {
    private static var cache: [String: ArtworkLayers] = [:]

    static func cached(accent: Color, size: CGFloat, scale: CGFloat) -> ArtworkLayers {
        let key = "\(accent.description)-\(size)-\(scale)"
        if let hit = cache[key] { return hit }
        let made = make(accent: accent, size: size, scale: scale)
        cache[key] = made
        return made
    }

    let halo: NSImage
    let shadow: NSImage
    let disc: NSImage
    let band: NSImage
    let star: NSImage

    static func make(accent: Color, size: CGFloat, scale: CGFloat) -> ArtworkLayers {
        func render(_ view: some View) -> NSImage {
            let r = ImageRenderer(content: view)
            r.scale = max(scale, 2)
            return r.nsImage ?? NSImage()
        }
        let disc = size * 0.78
        let core = disc * 0.46
        return ArtworkLayers(
            halo: render(Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.42), accent.opacity(0.1), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
                .frame(width: size, height: size)),
            shadow: render(Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: disc * 0.42))
                .frame(width: disc * 0.95, height: disc * 0.22)),
            disc: render(StaticDisc(accent: accent, disc: disc, core: core)),
            band: render(Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: disc * 0.3, height: disc * 1.6)),
            star: render(Sparkle()
                .fill(LinearGradient(colors: [Color(hex: 0x4A9A44), Color(hex: 0x2A6B2E)], startPoint: .top, endPoint: .bottom))
                .frame(width: core * 0.5, height: core * 0.5))
        )
    }
}

/// Camadas que não se movem entre si: desenhadas uma vez e transformadas como um bloco.
private struct StaticDisc: View {
    var accent: Color
    var disc: CGFloat
    var core: CGFloat

    var body: some View {
        let thickness = disc * 0.07
        ZStack {
            // Lateral (espessura).
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x1E5A26), Color(hex: 0x0E3518)], startPoint: .top, endPoint: .bottom))
                .frame(width: disc, height: disc)
                .offset(y: thickness)

            // Face de vidro translúcida.
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x9BD47A, opacity: 0.8), Color(hex: 0x3F8A3A, opacity: 0.75),
                                              Color(hex: 0x1F5E27, opacity: 0.88)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.26), .clear], center: UnitPoint(x: 0.35, y: 0.3),
                                                      startRadius: 0, endRadius: disc * 0.55)))
                .overlay(Circle().fill(RadialGradient(colors: [accent.opacity(0.28), .clear], center: UnitPoint(x: 0.78, y: 0.8),
                                                      startRadius: 0, endRadius: disc * 0.35)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.75), accent.opacity(0.25), .white.opacity(0.08)],
                                                              startPoint: .topLeading, endPoint: .bottomTrailing),
                                               lineWidth: disc * 0.012))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.16), lineWidth: disc * 0.03).padding(disc * 0.015))
                .frame(width: disc, height: disc)

            // Reflexo curvo na borda superior esquerda.
            Circle()
                .trim(from: 0.55, to: 0.78)
                .stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.85), .white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: disc * 0.035, lineCap: .round))
                .frame(width: disc * 0.86, height: disc * 0.86)

            // Núcleo fosco em relevo.
            Circle()
                .fill(RadialGradient(colors: [.black.opacity(0.28), .clear], center: .center, startRadius: core * 0.4, endRadius: core * 0.62))
                .frame(width: core * 1.3, height: core * 1.3)
                .offset(y: core * 0.08)
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0xF7FCF3), Color(hex: 0xD3E6CB), Color(hex: 0xB8D1AE)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                                               lineWidth: core * 0.035))
                .frame(width: core, height: core)
        }
        .frame(width: disc * 1.2, height: disc * 1.2)
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
