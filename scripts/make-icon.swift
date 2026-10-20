// Gera o AppIcon a partir de App/Resources/Source/AppIcon-source.png:
// recorta a área desenhada (fundo branco), aplica a máscara arredondada do macOS
// e centraliza numa tela transparente (824/1024, como o template da Apple).
// Uso: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
let source = NSImage(contentsOf: root.appendingPathComponent("App/Resources/Source/AppIcon-source.png"))!
let rep = NSBitmapImageRep(data: source.tiffRepresentation!)!

// Caixa do conteúdo: pixels que não são quase brancos.
var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
    for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if c.redComponent < 0.96 || c.greenComponent < 0.96 || c.blueComponent < 0.96 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
// Margem pequena para não pegar a sombra clara ao redor.
let inset = Int(Double(maxX - minX) * 0.012)
// Quadrado centrado na caixa (evita achatar o desenho).
let side = min(maxX - minX, maxY - minY) - 2 * inset
let centerX = (minX + maxX) / 2, centerY = rep.pixelsHigh - (minY + maxY) / 2
let crop = NSRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
    NSGraphicsContext.current?.imageInterpolation = .high
    let side = s * 824 / 1024
    let rect = NSRect(x: (s - side) / 2, y: (s - side) / 2, width: side, height: side)
    NSBezierPath(roundedRect: rect, xRadius: side * 0.2237, yRadius: side * 0.2237).addClip()
    source.draw(in: rect, from: crop, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return canvas.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(points * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]],
                            options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("Contents.json"))
print("crop:", crop)
