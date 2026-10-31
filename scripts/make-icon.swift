// Draws the placeholder ScreenCap app icon (original artwork) and writes an .iconset.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Rounded teal tile with white viewfinder corners and a center dot.
func drawIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.1
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.22, yRadius: tile.width * 0.22)
    NSGradient(
        starting: NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.66, alpha: 1),
        ending: NSColor(calibratedRed: 0.06, green: 0.30, blue: 0.45, alpha: 1)
    )!.draw(in: tilePath, angle: -90)

    NSColor.white.setStroke()
    let frame = tile.insetBy(dx: tile.width * 0.2, dy: tile.width * 0.2)
    let arm = frame.width * 0.28
    let corners = NSBezierPath()
    corners.lineWidth = max(1, size * 0.05)
    corners.lineCapStyle = .round
    corners.lineJoinStyle = .round
    for (x, y, dx, dy) in [
        (frame.minX, frame.minY, arm, arm), (frame.maxX, frame.minY, -arm, arm),
        (frame.minX, frame.maxY, arm, -arm), (frame.maxX, frame.maxY, -arm, -arm)
    ] {
        corners.move(to: NSPoint(x: x, y: y + dy))
        corners.line(to: NSPoint(x: x, y: y))
        corners.line(to: NSPoint(x: x + dx, y: y))
    }
    corners.stroke()

    NSColor.white.setFill()
    let dot = size * 0.09
    NSBezierPath(ovalIn: NSRect(x: size / 2 - dot, y: size / 2 - dot, width: dot * 2, height: dot * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try drawIcon(pixels: points * scale).write(to: outDir.appendingPathComponent(name))
    }
}
