import CoreGraphics
import Foundation

/// Mapa de bolhas: um círculo por item, com área proporcional ao tamanho, sem sobreposição, dentro de um retângulo.
/// Empacotamento por "cadeia de frente": cada círculo novo encosta em dois vizinhos da borda atual; se cruzar algum,
/// a borda recua e ele é recolocado. Depois tudo é centralizado e escalado para caber.
public enum BubbleLayout {
    public struct Circle: Hashable, Sendable {
        public var x: CGFloat
        public var y: CGFloat
        public var r: CGFloat
    }

    /// Círculos na mesma ordem de `sizes`. `minRadius` (em pontos) mantém itens minúsculos clicáveis.
    public static func pack(_ sizes: [Double], in bounds: CGSize, minRadius: CGFloat = 0, padding: CGFloat = 0) -> [Circle] {
        guard !sizes.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }
        let base = sizes.map { CGFloat(max($0, 0)).squareRoot() }
        let largest = base.max() ?? 0
        let floor = max(largest, 1) * 1e-6
        var radii = base.map { max($0, floor) }
        var result: [Circle] = []
        // Alguns passes: o raio mínimo depende da escala final, que depende do empacotamento.
        for _ in 0..<5 {
            let (circles, _) = packed(radii, gap: padding)
            // Escala pela caixa que contém as bolhas (preenche melhor um retângulo que o círculo envolvente).
            let minX = circles.map { $0.x - $0.r }.min()!, maxX = circles.map { $0.x + $0.r }.max()!
            let minY = circles.map { $0.y - $0.r }.min()!, maxY = circles.map { $0.y + $0.r }.max()!
            let scale = min(bounds.width / max(maxX - minX, 1e-9), bounds.height / max(maxY - minY, 1e-9))
            let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
            result = circles.map { c in
                Circle(x: bounds.width / 2 + (c.x - cx) * scale, y: bounds.height / 2 + (c.y - cy) * scale, r: c.r * scale)
            }
            guard minRadius > 0, result.contains(where: { $0.r < minRadius - 1e-6 }) else { break }
            radii = radii.indices.map { i in result[i].r < minRadius ? minRadius / scale * 1.08 : radii[i] }
        }
        return result
    }

    public struct Adaptive: Sendable {
        /// Na ordem de `sizes`; as ocultas têm raio 0.
        public var circles: [Circle]
        /// Itens pequenos demais para aparecer mesmo com o menor expoente.
        public var hidden: Set<Int>
        /// Expoente usado: raio ∝ tamanho^power.
        public var power: Double
    }

    /// Como o CleanMyMac (docs/re/specs/spacelens/ui-and-removal.md §3): raio = tamanho^p, com o maior p em
    /// [0,01; 0,333] (bisseção, 10 passos) que deixa todas as bolhas com pelo menos `minDiameter`. Se nem o menor p
    /// basta, as menores ficam ocultas e o resto é refeito.
    public static func packAdaptive(_ sizes: [Double], in bounds: CGSize, minDiameter: CGFloat, padding: CGFloat = 0,
                                    range: ClosedRange<Double> = 0.01...0.333) -> Adaptive {
        guard !sizes.isEmpty else { return Adaptive(circles: [], hidden: [], power: range.upperBound) }
        func layout(_ indices: [Int], _ p: Double) -> [Circle] {
            pack(indices.map { pow(max(sizes[$0], 0), 2 * p) }, in: bounds, padding: padding)
        }
        func fits(_ circles: [Circle]) -> Bool { circles.allSatisfy { $0.r * 2 >= minDiameter - 0.5 } }
        /// Maior p que cabe para estes índices (ou nil se nem o menor cabe).
        func bestPower(_ indices: [Int]) -> Double? {
            if fits(layout(indices, range.upperBound)) { return range.upperBound }
            guard fits(layout(indices, range.lowerBound)) else { return nil }
            var lo = range.lowerBound, hi = range.upperBound
            for _ in 0..<10 {
                let mid = (lo + hi) / 2
                if fits(layout(indices, mid)) { lo = mid } else { hi = mid }
            }
            return lo
        }
        var visible = Array(sizes.indices).filter { sizes[$0] > 0 }
        var power = bestPower(visible)
        // Esconde a menor de cada vez até caber.
        while power == nil, visible.count > 1 {
            let smallest = visible.min { sizes[$0] < sizes[$1] }!
            visible.removeAll { $0 == smallest }
            power = bestPower(visible)
        }
        let p = power ?? range.lowerBound
        var circles = Array(repeating: Circle(x: bounds.width / 2, y: bounds.height / 2, r: 0), count: sizes.count)
        for (k, c) in zip(visible, layout(visible, p)) { circles[k] = c }
        return Adaptive(circles: circles, hidden: Set(sizes.indices).subtracting(visible), power: p)
    }

    // MARK: - Empacotamento

    private struct Node {
        var x: CGFloat = 0, y: CGFloat = 0, r: CGFloat
        var next = 0, prev = 0
    }

    /// Empacota (maior primeiro) e devolve os círculos na ordem original e o círculo que envolve todos.
    private static func packed(_ radii: [CGFloat], gap: CGFloat) -> ([Circle], Circle) {
        let order = radii.indices.sorted { radii[$0] > radii[$1] }
        var n = order.map { Node(r: radii[$0] + gap / 2) }
        let count = n.count
        if count >= 2 {
            n[0].x = -n[1].r
            n[1].x = n[0].r
        }
        if count >= 3 {
            place(&n, b: 1, a: 0, c: 2)
            var a = 0, b = 1
            n[0].next = 1; n[1].prev = 0
            n[1].next = 2; n[2].prev = 1
            n[2].next = 0; n[0].prev = 2
            var i = 3
            outer: while i < count {
                place(&n, b: a, a: b, c: i)
                // Procura o primeiro círculo da cadeia que cruza o novo, andando pelos dois lados.
                var j = n[b].next, k = n[a].prev
                var sj = n[b].r, sk = n[a].r
                repeat {
                    if sj <= sk {
                        if intersects(n[j], n[i]) {
                            b = j; n[a].next = b; n[b].prev = a
                            continue outer
                        }
                        sj += n[j].r; j = n[j].next
                    } else {
                        if intersects(n[k], n[i]) {
                            a = k; n[a].next = b; n[b].prev = a
                            continue outer
                        }
                        sk += n[k].r; k = n[k].prev
                    }
                } while j != n[k].next
                // Entra na cadeia entre a e b.
                n[i].prev = a; n[i].next = b
                n[a].next = i; n[b].prev = i
                b = i
                // Recomeça pelo par mais perto da origem.
                var best = score(n, a), c = a
                while true {
                    c = n[c].next
                    if c == b { break }
                    let s = score(n, c)
                    if s < best { a = c; best = s }
                }
                b = n[a].next
                i += 1
            }
        }
        var circles = Array(repeating: Circle(x: 0, y: 0, r: 0), count: count)
        for (k, original) in order.enumerated() {
            circles[original] = Circle(x: n[k].x, y: n[k].y, r: max(n[k].r - gap / 2, 0))
        }
        return (circles, enclose(n.map { Circle(x: $0.x, y: $0.y, r: $0.r) }))
    }

    /// Põe `c` encostado em `a` e `b`.
    private static func place(_ n: inout [Node], b: Int, a: Int, c: Int) {
        let dx = n[b].x - n[a].x, dy = n[b].y - n[a].y
        let d2 = dx * dx + dy * dy
        if d2 > 0 {
            let a2 = (n[a].r + n[c].r) * (n[a].r + n[c].r)
            let b2 = (n[b].r + n[c].r) * (n[b].r + n[c].r)
            if a2 > b2 {
                let x = (d2 + b2 - a2) / (2 * d2)
                let y = max(0, b2 / d2 - x * x).squareRoot()
                n[c].x = n[b].x - x * dx - y * dy
                n[c].y = n[b].y - x * dy + y * dx
            } else {
                let x = (d2 + a2 - b2) / (2 * d2)
                let y = max(0, a2 / d2 - x * x).squareRoot()
                n[c].x = n[a].x + x * dx - y * dy
                n[c].y = n[a].y + x * dy + y * dx
            }
        } else {
            n[c].x = n[a].x + n[c].r
            n[c].y = n[a].y
        }
    }

    private static func intersects(_ a: Node, _ b: Node) -> Bool {
        let dr = a.r + b.r - 1e-6
        let dx = b.x - a.x, dy = b.y - a.y
        return dr > 0 && dr * dr > dx * dx + dy * dy
    }

    /// Distância (ao quadrado) da origem ao ponto de contato ponderado entre `i` e o próximo.
    private static func score(_ n: [Node], _ i: Int) -> CGFloat {
        let a = n[i], b = n[a.next]
        let ab = a.r + b.r
        let dx = (a.x * b.r + b.x * a.r) / ab, dy = (a.y * b.r + b.y * a.r) / ab
        return dx * dx + dy * dy
    }

    /// Menor círculo que contém todos (aproximado: refina o centro algumas vezes a partir da caixa envolvente).
    private static func enclose(_ c: [Circle]) -> Circle {
        guard !c.isEmpty else { return Circle(x: 0, y: 0, r: 0) }
        var cx = ((c.map { $0.x - $0.r }.min()!) + (c.map { $0.x + $0.r }.max()!)) / 2
        var cy = ((c.map { $0.y - $0.r }.min()!) + (c.map { $0.y + $0.r }.max()!)) / 2
        func radius() -> (CGFloat, Circle) {
            var worst = c[0], r: CGFloat = 0
            for k in c {
                let d = hypot(k.x - cx, k.y - cy) + k.r
                if d > r { r = d; worst = k }
            }
            return (r, worst)
        }
        var (r, far) = radius()
        // Puxa o centro na direção do círculo mais distante enquanto isso diminuir o raio.
        var step: CGFloat = 0.5
        for _ in 0..<60 {
            let d = hypot(far.x - cx, far.y - cy)
            guard d > 1e-9 else { break }
            let nx = cx + (far.x - cx) / d * r * step * 0.1, ny = cy + (far.y - cy) / d * r * step * 0.1
            let (oldX, oldY) = (cx, cy)
            (cx, cy) = (nx, ny)
            let (r2, far2) = radius()
            if r2 < r { r = r2; far = far2 } else { (cx, cy) = (oldX, oldY); step *= 0.5 }
        }
        return Circle(x: cx, y: cy, r: r)
    }
}
