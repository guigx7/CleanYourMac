import CoreGraphics
import Foundation
import Testing
@testable import CleanYourMacCore

/// Imagens geradas no teste: padrão de faixas e círculos; `shift` muda levemente; `blur` desfoca.
func makeImage(pattern: Int, size: Int = 512, brightness: CGFloat = 0, blur: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.1 + brightness, green: 0.2 + brightness, blue: 0.3 + brightness, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let s = CGFloat(size)
    for i in 0..<6 {
        let v = CGFloat((i * 37 + pattern * 53) % 100) / 100
        ctx.setFillColor(CGColor(red: min(1, v + brightness), green: min(1, 1 - v + brightness), blue: min(1, 0.5 + brightness), alpha: 1))
        let x = CGFloat((i * 71 + pattern * 131) % 400) / 400 * s * 0.7
        let y = CGFloat((i * 97 + pattern * 29) % 400) / 400 * s * 0.7
        if pattern % 2 == 0 { ctx.fillEllipse(in: CGRect(x: x, y: y, width: s * 0.3, height: s * 0.25)) }
        else { ctx.fill(CGRect(x: x, y: y, width: s * 0.35, height: s * 0.15)) }
    }
    var image = ctx.makeImage()!
    if blur {
        // Reduz e amplia de volta: perde os detalhes (desfoque).
        let small = CGContext(data: nil, width: size / 16, height: size / 16, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        small.interpolationQuality = .high
        small.draw(image, in: CGRect(x: 0, y: 0, width: size / 16, height: size / 16))
        let big = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        big.interpolationQuality = .high
        big.draw(small.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
        image = big.makeImage()!
    }
    return image
}

func candidate(_ id: String, _ image: CGImage, size: Int64 = 200_000, date: Date = Date(timeIntervalSince1970: 1_725_000_000)) -> SimilarCandidate {
    SimilarCandidate(id: id, url: URL(fileURLWithPath: "/x/\(id).png"), date: date, size: size, load: { image })
}

@Suite struct SimilarImagesTests {
    @Test func nearIdenticalGroupedDifferentNot() throws {
        let a = makeImage(pattern: 1), b = makeImage(pattern: 1, brightness: 0.03), c = makeImage(pattern: 6)
        let groups = try SimilarImageFinder().groups(from: [candidate("a", a), candidate("b", b), candidate("c", c)])
        #expect(groups.count == 1)
        #expect(Set(groups[0].images.map(\.id)) == ["a", "b"])
    }

    @Test func resizedCopyIsSimilar() throws {
        let a = makeImage(pattern: 3), small = makeImage(pattern: 3, size: 256)
        let groups = try SimilarImageFinder().groups(from: [candidate("a", a), candidate("s", small)])
        #expect(groups.count == 1)
    }

    @Test func bestToKeepIsSharperAndBigger() throws {
        let sharp = makeImage(pattern: 4), blurry = makeImage(pattern: 4, blur: true)
        let g = try #require(try SimilarImageFinder().groups(from: [candidate("blurry", blurry), candidate("sharp", sharp)]).first)
        #expect(g.images.first { $0.isBest }?.id == "sharp")
        #expect(g.autoselected.map(\.id) == ["blurry"])
        #expect(g.images.first { $0.id == "blurry" }?.flaws.contains(.blur) == true)
    }

    @Test func hashHasFourOrientationsAndIsStable() throws {
        let a = makeImage(pattern: 2, size: 256)
        let h = try #require(ImageHasher.hash(a))
        #expect(h.count == 4 && h == ImageHasher.hash(a))
        let other = try #require(ImageHasher.hash(makeImage(pattern: 5, size: 256)))
        #expect(ImageHasher.distance(h, other) > SimilarImageFinder.defaultThreshold)
    }

    @Test func tooSmallThumbnailsAreSkipped() {
        #expect(ImageHasher.hash(makeImage(pattern: 2, size: 100)) == nil)
    }

    @Test func distanceSumsWordByWord() {
        #expect(ImageHasher.distance([0b1, 0, 0, 0b11], [0, 0, 0, 0]) == 3)
        #expect(SimilarImageFinder.defaultThreshold == 15)
    }

    /// Guloso: cada imagem entra no primeiro grupo com um membro parecido; grupos já abertos não se juntam.
    @Test func greedyGroupingNeverMerges() {
        let a: [UInt64] = [0, 0, 0, 0]
        let c: [UInt64] = [0xFFFF_FFFF, 0, 0, 0]        // 32 bits de a
        let b: [UInt64] = [0xFFFF, 0, 0, 0]             // 16 bits de a e de c: só com limiar 16
        #expect(SimilarImageFinder.greedyGroups([a, c, b], threshold: 16) == [[0, 2]])  // c abre o próprio grupo e fica só
        #expect(SimilarImageFinder.greedyGroups([a, nil, a], threshold: 15) == [[0, 2]])
    }

    @Test func bestCountGrowsWithGroupSize() {
        #expect([2, 3, 4, 6, 7, 12].map(SimilarImageFinder.bestCount) == [1, 1, 2, 2, 3, 3])
    }

    @Test func groupMetadata() throws {
        let d1 = Date(timeIntervalSince1970: 1_725_400_000), d2 = Date(timeIntervalSince1970: 1_725_500_000)
        let g = try #require(try SimilarImageFinder().groups(from: [
            candidate("a", makeImage(pattern: 1), size: 300_000, date: d2), candidate("b", makeImage(pattern: 1), size: 100_000, date: d1),
        ]).first)
        #expect(g.totalSize == 400_000)
        #expect(g.date == d1)
    }
}
