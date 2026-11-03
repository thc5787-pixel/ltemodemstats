// Draws the app icon and writes an .iconset directory for `iconutil`.
// Usage: swift Packaging/make_icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Rounded tile with a blue gradient and four signal bars, the last one dimmed.
func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: the tile is ~80% of the canvas, centred.
    let inset = size * 0.1
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = tile.width * 0.225
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.55, blue: 0.95, alpha: 1),
               ending: NSColor(srgbRed: 0.09, green: 0.30, blue: 0.75, alpha: 1))!
        .draw(in: path, angle: -90)

    let barCount = 4
    let area = tile.insetBy(dx: tile.width * 0.2, dy: tile.height * 0.22)
    let gap = area.width * 0.08
    let barWidth = (area.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
    for index in 0 ..< barCount {
        let height = area.height * CGFloat(index + 1) / CGFloat(barCount)
        let rect = NSRect(x: area.minX + CGFloat(index) * (barWidth + gap), y: area.minY,
                          width: barWidth, height: height)
        NSColor.white.withAlphaComponent(index == barCount - 1 ? 0.45 : 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: barWidth * 0.18, yRadius: barWidth * 0.18).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(points * scale)
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(size: pixels).representation(using: .png, properties: [:])!
        try png.write(to: output.appendingPathComponent(name))
    }
}
print(output.path)
