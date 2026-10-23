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
}

public struct SimilarGroup: Hashable, Sendable, Identifiable {
    public let images: [SimilarImage]
    public var id: String { images.map(\.id).joined(separator: "|") }
    /// Título do grupo: a data mais antiga.
    public var date: Date? { images.compactMap(\.date).min() }
    public var totalSize: Int64 { images.reduce(0) { $0 + $1.size } }
    /// Marcação automática: todas menos a melhor.
    public var autoselected: [SimilarImage] { images.filter { !$0.isBest } }
}

/// Imagens similares (docs/re/specs/clutter/similar-images.md): hash perceptual de 64 bits (DCT) e distância de Hamming.
public struct SimilarImageFinder: Sendable {
    /// Bits diferentes aceitos entre duas imagens "praticamente idênticas".
    public let threshold: Int

    public init(threshold: Int = 10) { self.threshold = threshold }

    /// Arquivos que entram (regras próprias de Similares): imagem, ≥ 100 KiB, sem psd/psb/xcassets.
    public static func accepts(_ file: ClutterFile) -> Bool {
        guard file.size >= 102_400, !["psd", "psb", "xcassets"].contains(file.url.pathExtension.lowercased()) else { return false }
        return file.type?.conforms(to: .image) == true
    }

    public func groups(from candidates: [SimilarCandidate], isCancelled: @Sendable () -> Bool = { Task.isCancelled }) throws -> [SimilarGroup] {
        let n = candidates.count
        let results = ConcurrentResults<(UInt64, Double, Int)>(count: n)
        let cancelled = Flag()
        DispatchQueue.concurrentPerform(iterations: n) { i in
            guard !cancelled.isSet else { return }
            if isCancelled() { cancelled.set(); return }
            guard let image = candidates[i].load() else { return }
            results[i] = (ImageHasher.pHash(image), ImageHasher.sharpness(image), image.width * image.height)
        }
        if cancelled.isSet || isCancelled() { throw CancellationError() }
        // Componentes conexas dos pares parecidos (union-find).
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        let hashes = (0..<n).map { results[$0]?.0 }
        for i in 0..<n {
            guard let hi = hashes[i] else { continue }
            if i & 0xFF == 0, isCancelled() { throw CancellationError() }
            for j in (i + 1)..<n {
                guard let hj = hashes[j], (hi ^ hj).nonzeroBitCount <= threshold else { continue }
                let (ri, rj) = (find(i), find(j))
                if ri != rj { parent[rj] = ri }
            }
        }
        var members: [Int: [Int]] = [:]
        for i in 0..<n where hashes[i] != nil { members[find(i), default: []].append(i) }
        return members.values.filter { $0.count > 1 }.map { idx in
            let sharp = idx.map { results[$0]!.1 }, pixels = idx.map { results[$0]!.2 }
            func norm(_ v: Double, _ values: [Double]) -> Double {
                let lo = values.min()!, hi = values.max()!
                return hi > lo ? (v - lo) / (hi - lo) : 1
            }
            let px = pixels.map(Double.init)
            let scores = idx.indices.map { 0.5 * norm(px[$0], px) + 0.5 * norm(sharp[$0], sharp) }
            let best = scores.indices.max { scores[$0] != scores[$1] ? scores[$0] < scores[$1] : candidates[idx[$0]].size < candidates[idx[$1]].size }!
            let maxSharp = sharp.max() ?? 0
            let images = idx.indices.map { k -> SimilarImage in
                let c = candidates[idx[k]]
                return SimilarImage(id: c.id, url: c.url, date: c.date, size: c.size, pixels: pixels[k], sharpness: sharp[k], isBest: k == best,
                                    flaws: sharp[k] < 0.25 * maxSharp ? [.blur] : [])
            }
            return SimilarGroup(images: images.sorted { $0.size != $1.size ? $0.size > $1.size : $0.id < $1.id })
        }
        .sorted { $0.totalSize != $1.totalSize ? $0.totalSize > $1.totalSize : $0.id < $1.id }
    }
}

/// Hash perceptual e nitidez, em miniaturas em tons de cinza.
public enum ImageHasher {
    static func gray(_ image: CGImage, side: Int) -> [Double] {
        var pixels = [UInt8](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return pixels.map(Double.init)
    }

    private static let cosines: [[Double]] = (0..<8).map { u in (0..<32).map { x in cos(Double(2 * x + 1) * Double(u) * .pi / 64) } }

    /// pHash: DCT 2D de 32×32, os 8×8 coeficientes de baixa frequência comparados com a mediana (sem o termo DC).
    public static func pHash(_ image: CGImage) -> UInt64 {
        let g = gray(image, side: 32)
        var coeffs = [Double](repeating: 0, count: 64)
        for u in 0..<8 {
            for v in 0..<8 {
                var sum = 0.0
                for y in 0..<32 {
                    let cy = cosines[v][y]
                    for x in 0..<32 { sum += g[y * 32 + x] * cosines[u][x] * cy }
                }
                coeffs[v * 8 + u] = sum
            }
        }
        let median = coeffs.dropFirst().sorted()[31]
        var hash: UInt64 = 0
        for (i, c) in coeffs.enumerated() where i > 0 && c > median { hash |= 1 << UInt64(i) }
        return hash
    }

    /// Nitidez: variância do Laplaciano numa miniatura de 128×128.
    public static func sharpness(_ image: CGImage) -> Double {
        let s = 128, g = gray(image, side: s)
        var values: [Double] = []
        values.reserveCapacity((s - 2) * (s - 2))
        for y in 1..<(s - 1) {
            for x in 1..<(s - 1) {
                let c = g[y * s + x]
                values.append(g[(y - 1) * s + x] + g[(y + 1) * s + x] + g[y * s + x - 1] + g[y * s + x + 1] - 4 * c)
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }
}
