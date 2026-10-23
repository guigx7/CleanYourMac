import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Uma imagem para comparar: arquivo solto ou foto da fototeca (o app fornece as da fototeca pelo PhotoKit).
public struct SimilarCandidate: Sendable {
    public let id: String
    public let url: URL?
    public let date: Date?
    public let size: Int64
    /// Imagem (ou miniatura) para o hash e a nitidez.
    public let load: @Sendable () -> CGImage?

    public init(id: String, url: URL?, date: Date?, size: Int64, load: @escaping @Sendable () -> CGImage?) {
        self.id = id
        self.url = url
        self.date = date
        self.size = size
        self.load = load
    }

    /// Arquivo de imagem: miniatura de até 256 px pelo ImageIO.
    public static func file(_ file: ClutterFile) -> SimilarCandidate {
        let url = file.url
        return SimilarCandidate(id: url.path, url: url, date: file.created ?? file.modified, size: file.size) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }
    }
}

public struct SimilarImage: Hashable, Sendable, Identifiable {
    public enum Flaw: String, Sendable { case blur }
    public let id: String
    public let url: URL?
    public let date: Date?
    public let size: Int64
    public let pixels: Int
    public let sharpness: Double
    /// "Uma das melhores para manter".
    public let isBest: Bool
    public let flaws: Set<Flaw>

    public init(id: String, url: URL?, date: Date?, size: Int64, pixels: Int, sharpness: Double, isBest: Bool, flaws: Set<Flaw>) {
        self.id = id
        self.url = url
        self.date = date
        self.size = size
        self.pixels = pixels
        self.sharpness = sharpness
        self.isBest = isBest
        self.flaws = flaws
    }
}

public struct SimilarGroup: Hashable, Sendable, Identifiable {
    public let images: [SimilarImage]

    public init(images: [SimilarImage]) { self.images = images }

    public var id: String { images.map(\.id).joined(separator: "|") }
    /// Título do grupo: a data mais antiga.
    public var date: Date? { images.compactMap(\.date).min() }
    public var totalSize: Int64 { images.reduce(0) { $0 + $1.size } }
    /// Marcação automática: todas menos a melhor.
    public var autoselected: [SimilarImage] { images.filter { !$0.isBest } }
}

/// Imagens similares (docs/re/specs/clutter/similar-images.md §2–3): hash de gradientes em 4 orientações (4 × 64 bits),
/// soma das distâncias de Hamming ≤ 15, agrupamento guloso pela ordem (sem juntar grupos) e "melhor para manter" pela
/// qualidade (ruído, nitidez, faixa dinâmica, tamanho).
public struct SimilarImageFinder: Sendable {
    /// Soma máxima de bits diferentes nas 4 palavras.
    public let threshold: Int

    public static let defaultThreshold = 15

    public init(threshold: Int = SimilarImageFinder.defaultThreshold) { self.threshold = threshold }

    /// Arquivos que entram (regras próprias de Similares): imagem, ≥ 100 KiB, sem psd/psb nem nada dentro de `.xcassets`.
    public static func accepts(_ file: ClutterFile) -> Bool {
        guard file.size >= 102_400, !["psd", "psb"].contains(file.url.pathExtension.lowercased()),
              !ClutterRules.isInsideXcassets(file.url) else { return false }
        return file.type?.conforms(to: .image) == true
    }

    struct Analysis {
        let hash: [UInt64]
        let quality: ImageQuality
    }

    /// Ordem fixa (a do CleanMyMac depende da concorrência): arquivos por caminho, depois fotos por data.
    static func ordered(_ candidates: [SimilarCandidate]) -> [SimilarCandidate] {
        candidates.sorted { a, b in
            switch (a.url, b.url) {
            case let (ua?, ub?): return ua.path < ub.path
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return (a.date ?? .distantPast, a.id) < (b.date ?? .distantPast, b.id)
            }
        }
    }

    public func groups(from input: [SimilarCandidate], isCancelled: @Sendable () -> Bool = { Task.isCancelled }) throws -> [SimilarGroup] {
        let candidates = Self.ordered(input)
        let n = candidates.count
        let results = ConcurrentResults<Analysis>(count: n)
        let cancelled = Flag()
        DispatchQueue.concurrentPerform(iterations: n) { i in
            guard !cancelled.isSet else { return }
            if isCancelled() { cancelled.set(); return }
            // Sem hash ou sem métricas, a imagem sai da análise.
            guard let image = candidates[i].load(), let hash = ImageHasher.hash(image), let q = ImageQuality.measure(image) else { return }
            results[i] = Analysis(hash: hash, quality: q)
        }
        if cancelled.isSet || isCancelled() { throw CancellationError() }
        let analyses = (0..<n).map { results[$0] }
        return Self.greedyGroups(analyses.map { $0?.hash }, threshold: threshold).map { idx in
            let qualities = idx.map { analyses[$0]!.quality }
            let best = Set(ImageQuality.best(qualities))
            let maxBlur = qualities.compactMap(\.blur).max() ?? 0
            let images = idx.enumerated().map { k, i -> SimilarImage in
                let c = candidates[i], q = qualities[k]
                // Selo de desfoque: regra nossa provisória (o critério do CleanMyMac não foi lido).
                return SimilarImage(id: c.id, url: c.url, date: c.date, size: c.size, pixels: q.width * q.height, sharpness: q.blur ?? 0,
                                    isBest: best.contains(k), flaws: maxBlur > 0 && (q.blur ?? 0) < 0.25 * maxBlur ? [.blur] : [])
            }
            return SimilarGroup(images: images.sorted { $0.size != $1.size ? $0.size > $1.size : $0.id < $1.id })
        }
        .sorted { $0.totalSize != $1.totalSize ? $0.totalSize > $1.totalSize : $0.id < $1.id }
    }

    /// Cada imagem entra no primeiro grupo (na ordem de criação) que tem algum membro parecido; senão abre um grupo.
    /// Grupos não se juntam. Saem os grupos de um só.
    static func greedyGroups(_ hashes: [[UInt64]?], threshold: Int) -> [[Int]] {
        var groups: [[Int]] = []
        for (i, h) in hashes.enumerated() {
            guard let h else { continue }
            if let g = groups.firstIndex(where: { $0.contains { ImageHasher.distance(hashes[$0]!, h) <= threshold } }) {
                groups[g].append(i)
            } else {
                groups.append([i])
            }
        }
        return groups.filter { $0.count > 1 }
    }

    /// Quantas ficam com o selo "melhor para manter": 1 em grupos de 2–3, 2 em 4–6, 3 a partir de 7.
    static func bestCount(_ groupSize: Int) -> Int { groupSize >= 7 ? 3 : groupSize >= 4 ? 2 : 1 }
}

/// Hash de gradientes (docs/re/specs/clutter/similar-images.md §2), sobre a miniatura de até 256 px.
public enum ImageHasher {
    static let side = 32

    /// Linha 0: (1/√32)·cos((2n+1)π/64); demais: 0,25·cos(k(2n+1)π/64).
    private static let dct: [Float] = (0..<32).flatMap { k in
        (0..<32).map { n in
            let c = Float(cos(Double(k * (2 * n + 1)) * .pi / 64))
            return k == 0 ? c / Float(32).squareRoot() : 0.25 * c
        }
    }

    /// 4 palavras: orientações 0°, 90°, 180°, 270°. `nil` se a miniatura for pequena demais ou não converter.
    public static func hash(_ image: CGImage) -> [UInt64]? {
        guard max(image.width, image.height) >= 128, min(image.width, image.height) >= 32,
              var plane = gradientPlane(image) else { return nil }
        var out: [UInt64] = []
        for turn in 0..<4 {
            if turn > 0 { plane = rotated(plane) }
            out.append(word(plane))
        }
        return out
    }

    public static func distance(_ a: [UInt64], _ b: [UInt64]) -> Int {
        zip(a, b).reduce(0) { $0 + ($1.0 ^ $1.1).nonzeroBitCount }
    }

    /// Luminância (709 em ponto fixo), gradiente horizontal 3×3 saturado, ×√2, em float de 0 a 1, reduzido para 32×32.
    static func gradientPlane(_ image: CGImage) -> [Float]? {
        guard let format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue)),
              var argb = try? vImage_Buffer(cgImage: image, format: format) else { return nil }
        defer { argb.free() }
        let w = Int(argb.width), h = Int(argb.height)
        guard var luma = try? vImage_Buffer(width: w, height: h, bitsPerPixel: 8),
              var grad = try? vImage_Buffer(width: w, height: h, bitsPerPixel: 8) else { return nil }
        defer { luma.free(); grad.free() }
        let matrix: [Int16] = [0, 54, 183, 18]
        guard vImageMatrixMultiply_ARGB8888ToPlanar8(&argb, &luma, matrix, 256, nil, 0, vImage_Flags(kvImageDoNotTile)) == kvImageNoError
        else { return nil }
        let kernel: [Int16] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        guard vImageConvolve_Planar8(&luma, &grad, nil, 0, 0, kernel, 3, 3, 8, 0,
                                     vImage_Flags(kvImageBackgroundColorFill | kvImageDoNotTile)) == kvImageNoError else { return nil }
        var full = [Float](repeating: 0, count: w * h)
        let root2 = Float(2).squareRoot()
        for y in 0..<h {
            let row = grad.data.advanced(by: y * grad.rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w { full[y * w + x] = min(255, (root2 * Float(row[x])).rounded(.towardZero)) / 255 }
        }
        var small = [Float](repeating: 0, count: side * side)
        let ok = full.withUnsafeMutableBytes { src -> Bool in
            small.withUnsafeMutableBytes { dst -> Bool in
                var s = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
                var d = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(side), width: vImagePixelCount(side), rowBytes: side * 4)
                return vImageScale_PlanarF(&s, &d, nil, vImage_Flags(kvImageDoNotTile)) == kvImageNoError
            }
        }
        return ok ? small : nil
    }

    /// 90° no sentido anti-horário, fundo 0.
    static func rotated(_ plane: [Float]) -> [Float] {
        var src = plane, out = [Float](repeating: 0, count: plane.count)
        src.withUnsafeMutableBytes { s in
            out.withUnsafeMutableBytes { d in
                var a = vImage_Buffer(data: s.baseAddress, height: vImagePixelCount(side), width: vImagePixelCount(side), rowBytes: side * 4)
                var b = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(side), width: vImagePixelCount(side), rowBytes: side * 4)
                _ = vImageRotate90_PlanarF(&a, &b, UInt8(kRotate90DegreesCounterClockwise), 0, vImage_Flags(kvImageNoFlags))
            }
        }
        return out
    }

    /// D = M·I·Mᵀ; bloco 8×8 do canto comparado com a média dele (bit 8u+v = D[u][v] ≥ média).
    static func word(_ plane: [Float]) -> UInt64 {
        let n = side
        var mi = [Float](repeating: 0, count: 8 * n)      // linhas 0…7 de M·I
        for k in 0..<8 {
            for x in 0..<n {
                var sum: Float = 0
                for y in 0..<n { sum += dct[k * n + y] * plane[y * n + x] }
                mi[k * n + x] = sum
            }
        }
        var block = [Float](repeating: 0, count: 64)
        for u in 0..<8 {
            for v in 0..<8 {
                var sum: Float = 0
                for x in 0..<n { sum += mi[u * n + x] * dct[v * n + x] }
                block[u * 8 + v] = sum
            }
        }
        let mean = block.reduce(0, +) / 64
        var word: UInt64 = 0
        for (i, c) in block.enumerated() where c >= mean { word |= 1 << UInt64(i) }
        return word
    }
}

/// Métricas de qualidade da miniatura em cinza (docs/re/specs/clutter/similar-images.md §3).
struct ImageQuality: Sendable {
    let width: Int
    let height: Int
    /// Variância dos detalhes da transformada de Haar: maior = mais nítida.
    let blur: Double?
    /// Menor autovalor positivo da covariância dos blocos 8×8 mais lisos.
    let noise: Double?
    /// 20·log10(máx/mín) dos níveis de cinza.
    let dynamicRange: Double?

    static func gray(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? px : nil
    }

    static func measure(_ image: CGImage) -> ImageQuality? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let g = gray(image) else { return nil }
        let lo = g.min()!, hi = g.max()!
        let dr = lo > 0 ? 20 * log10(Double(hi) / Double(lo)) : nil
        return ImageQuality(width: w, height: h, blur: haarDetail(g.map(Double.init), w, h), noise: noise(g, w, h), dynamicRange: dr)
    }

    /// Haar 1D em vários níveis sobre os primeiros `count` valores (média na primeira metade, diferença na segunda).
    static func haar(_ v: inout [Double], count: Int) {
        var len = count
        var tmp = v
        while len > 3 {
            let half = len / 2
            for i in 0..<half {
                tmp[i] = (v[2 * i] + v[2 * i + 1]) / 2
                tmp[half + i] = (v[2 * i] - v[2 * i + 1]) / 2
            }
            for i in 0..<(2 * half) { v[i] = tmp[i] }
            len = half
        }
    }

    /// Haar 2D (linhas, depois colunas); variância da segunda metade do vetor achatado.
    static func haarDetail(_ pixels: [Double], _ w: Int, _ h: Int) -> Double? {
        var m = pixels
        for y in 0..<h {
            var row = Array(m[(y * w)..<(y * w + w)])
            haar(&row, count: w)
            m.replaceSubrange((y * w)..<(y * w + w), with: row)
        }
        for x in 0..<w {
            var col = (0..<h).map { m[$0 * w + x] }
            haar(&col, count: h)
            for y in 0..<h { m[y * w + x] = col[y] }
        }
        let tail = m[(m.count / 2)...]
        guard !tail.isEmpty else { return nil }
        let mean = tail.reduce(0, +) / Double(tail.count)
        return tail.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(tail.count)
    }

    /// Blocos 8×8 a cada 7 px; os de variância até o 10º percentil; menor autovalor positivo da covariância 64×64.
    static func noise(_ g: [UInt8], _ w: Int, _ h: Int) -> Double? {
        guard w >= 8, h >= 8 else { return nil }
        var blocks: [[Double]] = [], vars: [Double] = []
        for y in stride(from: 0, through: h - 8, by: 7) {
            for x in stride(from: 0, through: w - 8, by: 7) {
                var b = [Double](repeating: 0, count: 64)
                for dy in 0..<8 { for dx in 0..<8 { b[dy * 8 + dx] = Double(g[(y + dy) * w + x + dx]) } }
                let mean = b.reduce(0, +) / 64
                vars.append(b.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 64)
                blocks.append(b)
            }
        }
        let sorted = vars.sorted()
        var limit = sorted[sorted.count / 10]
        if limit <= 0 { limit = sorted.first { $0 > 0 } ?? 0 }
        let kept = blocks.indices.filter { vars[$0] <= limit }.map { blocks[$0] }
        guard kept.count > 1 else { return nil }
        var mean = [Double](repeating: 0, count: 64)
        for b in kept { for i in 0..<64 { mean[i] += b[i] } }
        for i in 0..<64 { mean[i] /= Double(kept.count) }
        var cov = [Double](repeating: 0, count: 64 * 64)
        for b in kept {
            for i in 0..<64 {
                let di = b[i] - mean[i]
                for j in i..<64 { cov[i * 64 + j] += di * (b[j] - mean[j]) }
            }
        }
        for i in 0..<64 { for j in i..<64 { cov[i * 64 + j] /= Double(kept.count); cov[j * 64 + i] = cov[i * 64 + j] } }
        return eigenvalues(cov, 64).filter { $0 > 1e-9 }.min()
    }

    /// Autovalores de uma matriz simétrica (Jacobi cíclico).
    static func eigenvalues(_ input: [Double], _ n: Int) -> [Double] {
        var a = input
        for _ in 0..<60 {
            var off = 0.0
            for p in 0..<n { for q in (p + 1)..<n { off += a[p * n + q] * a[p * n + q] } }
            if off < 1e-18 { break }
            for p in 0..<n {
                for q in (p + 1)..<n {
                    let apq = a[p * n + q]
                    guard abs(apq) > 1e-15 else { continue }
                    let theta = (a[q * n + q] - a[p * n + p]) / (2 * apq)
                    let t = (theta >= 0 ? 1 : -1) / (abs(theta) + (theta * theta + 1).squareRoot())
                    let c = 1 / (t * t + 1).squareRoot(), s = t * c
                    for k in 0..<n {
                        let akp = a[k * n + p], akq = a[k * n + q]
                        a[k * n + p] = c * akp - s * akq
                        a[k * n + q] = s * akp + c * akq
                    }
                    for k in 0..<n {
                        let apk = a[p * n + k], aqk = a[q * n + k]
                        a[p * n + k] = c * apk - s * aqk
                        a[q * n + k] = s * apk + c * aqk
                    }
                }
            }
        }
        return (0..<n).map { a[$0 * n + $0] }
    }

    /// Índices das melhores: pontuação √((ruído−1)² + nitidez²) + 0,3·faixa + 0,1·largura + 0,1·altura, com cada valor
    /// normalizado no grupo (ausentes: ruído 1, nitidez 0, faixa 0).
    static func best(_ q: [ImageQuality]) -> [Int] {
        func norm(_ values: [Double]) -> [Double] {
            let lo = values.min() ?? 0, hi = values.max() ?? 0
            return values.map { hi > lo ? ($0 - lo) / (hi - lo) : $0 }
        }
        let noise = norm(q.map { $0.noise ?? 1 }), blur = norm(q.map { $0.blur ?? 0 }), dr = norm(q.map { $0.dynamicRange ?? 0 })
        let w = norm(q.map { Double($0.width) }), h = norm(q.map { Double($0.height) })
        let scores = q.indices.map { i in
            ((noise[i] - 1) * (noise[i] - 1) + blur[i] * blur[i]).squareRoot() + 0.3 * dr[i] + 0.1 * w[i] + 0.1 * h[i]
        }
        let order = q.indices.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
        return Array(order.prefix(SimilarImageFinder.bestCount(q.count)))
    }
}
