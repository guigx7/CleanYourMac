// Gera o AppIcon (gradiente verde + lente de vidro + brilho), sem arte de terceiros.
// Uso: swift scripts/make-icon.swift
import AppKit

let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.055, green: 0.227, blue: 0.122, alpha: 1),
                        NSColor(srgbRed: 0.184, green: 0.42, blue: 0.165, alpha: 1),
                        NSColor(srgbRed: 0.561, green: 0.702, blue: 0.224, alpha: 1)])!.draw(in: shape, angle: 45)
    let lens = NSRect(x: s * 0.26, y: s * 0.26, width: s * 0.48, height: s * 0.48)
    NSColor.white.withAlphaComponent(0.16).setFill()
    NSBezierPath(ovalIn: lens).fill()
    NSColor.white.withAlphaComponent(0.55).setStroke()
    let ring = NSBezierPath(ovalIn: lens); ring.lineWidth = s * 0.012; ring.stroke()
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: s * 0.22, weight: .medium)) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
        }
        let size = tinted.size
        tinted.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(points * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
try! #"{"info":{"version":1,"author":"xcode"}}"#.write(to: out.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("ok")
