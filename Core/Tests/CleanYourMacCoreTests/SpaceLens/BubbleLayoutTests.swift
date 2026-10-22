import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct BubbleLayoutTests {
    func overlaps(_ c: [BubbleLayout.Circle]) -> Bool {
        for i in c.indices { for j in c.indices where j > i {
            let d = hypot(c[i].x - c[j].x, c[i].y - c[j].y)
            if d < c[i].r + c[j].r - 1e-6 { return true }
        } }
        return false
    }

    @Test func noOverlapAndInsideBounds() {
        let sizes: [Double] = [183, 19.9, 15.8, 8.2, 6.3, 3.8, 0.83, 0.0049, 0.0025, 5]
        let out = BubbleLayout.pack(sizes, in: CGSize(width: 600, height: 400))
        #expect(out.count == sizes.count)
        #expect(!overlaps(out))
        for c in out {
            #expect(c.x - c.r >= -0.5 && c.x + c.r <= 600.5 && c.y - c.r >= -0.5 && c.y + c.r <= 400.5)
        }
    }

    @Test func areaProportionalToSize() {
        let out = BubbleLayout.pack([100, 25], in: CGSize(width: 500, height: 500))
        #expect(abs(out[0].r / out[1].r - 2) < 1e-6)
    }

    @Test func fillsTheSmallerSide() {
        let out = BubbleLayout.pack([1], in: CGSize(width: 800, height: 300))
        #expect(abs(out[0].r - 150) < 1)
        #expect(abs(out[0].x - 400) < 1 && abs(out[0].y - 150) < 1)
    }

    @Test func tinyItemsStillVisible() {
        let out = BubbleLayout.pack([1_000_000, 1], in: CGSize(width: 400, height: 400), minRadius: 4)
        #expect(out[1].r >= 4)
        #expect(!overlaps(out))
    }

    @Test func emptyAndZero() {
        #expect(BubbleLayout.pack([], in: CGSize(width: 100, height: 100)).isEmpty)
        #expect(BubbleLayout.pack([0, 0], in: CGSize(width: 100, height: 100)).count == 2)
    }

    @Test func manyItemsStayFast() {
        let sizes = (1...400).map { Double($0 * $0) }
        let start = Date()
        let out = BubbleLayout.pack(sizes, in: CGSize(width: 900, height: 700))
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(!overlaps(out))
    }
}
