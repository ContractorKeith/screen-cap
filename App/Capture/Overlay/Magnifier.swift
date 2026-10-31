import AppKit
import ScreenCapKit

/// The loupe next to the cursor: 8x pixel grid, coordinates, selection size, hex color.
@MainActor
enum Magnifier {
    static let zoom: CGFloat = 8
    /// Pixels shown on each side of the center pixel.
    static let radius = 7
    static var side: CGFloat { CGFloat(radius * 2 + 1) * zoom }

    /// Pixels around the cursor plus the center pixel's color.
    struct Sample {
        let image: CGImage
        let hex: String
    }

    /// Draws into the current context of the display's view; `bounds` is that view's bounds.
    static func draw(in bounds: CGRect, global: CGPoint, still: CapturedImage?, display: DisplayInfo,
                     selection: CGSize?) {
        let point = CGPoint(x: global.x - display.frame.minX, y: global.y - display.frame.minY)
        let pixels = still.flatMap { sample($0, at: global) }
        let lines = readoutLines(global: global, display: display, selection: selection, hex: pixels?.hex)
        let loupe = frame(near: point, in: bounds, readoutHeight: CGFloat(lines.count) * 18 + 8)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let clip = CGPath(roundedRect: loupe, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(clip)
        context.clip()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(loupe)
        if let pixels {
            context.interpolationQuality = .none
            context.draw(pixels.image, in: loupe)
        }
        drawGrid(context, in: loupe)
        context.restoreGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.addPath(clip)
        context.strokePath()

        var origin = CGPoint(x: loupe.minX, y: loupe.minY - 22)
        for line in lines {
            OverlayBadge.draw(line, at: origin, in: bounds)
            origin.y -= 18
        }
    }

    private static func readoutLines(global: CGPoint, display: DisplayInfo, selection: CGSize?, hex: String?)
        -> [String] {
        let local = SelectionMath.localTopLeft(global, in: display.frame)
        var lines = ["\(SelectionMath.wholeNumber(local.x)), \(SelectionMath.wholeNumber(local.y)) pt"]
        if let selection { lines.append(SelectionMath.sizeLabel(selection) + " pt") }
        if let hex { lines.append(hex) }
        return lines
    }

    /// Below-right of the cursor, flipped to stay on screen.
    private static func frame(near point: CGPoint, in bounds: CGRect, readoutHeight: CGFloat) -> CGRect {
        let offset: CGFloat = 24
        var x = point.x + offset
        var y = point.y - offset - side
        if x + side > bounds.maxX { x = point.x - offset - side }
        if y - readoutHeight < bounds.minY { y = point.y + offset }
        return CGRect(x: x, y: y, width: side, height: side)
    }

    private static func drawGrid(_ context: CGContext, in rect: CGRect) {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(0.5)
        var segments: [CGPoint] = []
        for step in 1..<(radius * 2 + 1) {
            let offset = CGFloat(step) * zoom
            segments += [CGPoint(x: rect.minX + offset, y: rect.minY), CGPoint(x: rect.minX + offset, y: rect.maxY)]
            segments += [CGPoint(x: rect.minX, y: rect.minY + offset), CGPoint(x: rect.maxX, y: rect.minY + offset)]
        }
        context.strokeLineSegments(between: segments)
        let center = CGRect(x: rect.minX + CGFloat(radius) * zoom, y: rect.minY + CGFloat(radius) * zoom,
                            width: zoom, height: zoom)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(center)
    }

    /// Copies the (2r+1)² pixels around a global point into an sRGB bitmap and reads the center.
    static func sample(_ still: CapturedImage, at global: CGPoint) -> Sample? {
        let info = DisplayInfo(id: still.displayID ?? 0, frame: still.pointRect, backingScale: still.scale)
        let pixel = info.pixelPoint(forGlobalPoint: global)
        let count = radius * 2 + 1
        let originX = Int(pixel.x.rounded(.down)) - radius
        let originY = Int(pixel.y.rounded(.down)) - radius
        let wanted = CGRect(x: originX, y: originY, width: count, height: count)
        let imageBounds = CGRect(x: 0, y: 0, width: still.cgImage.width, height: still.cgImage.height)
        let clipped = wanted.intersection(imageBounds)
        guard !clipped.isNull, let crop = ImageCropper.crop(still.cgImage, pixelRect: clipped),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: count, height: count, bitsPerComponent: 8,
                                      bytesPerRow: count * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: count, height: count))
        // Bitmap y runs up from the bottom; image rows run down from the top.
        let drawX = clipped.minX - wanted.minX
        let drawY = wanted.maxY - clipped.maxY
        context.draw(crop, in: CGRect(x: drawX, y: drawY, width: clipped.width, height: clipped.height))
        guard let data = context.data, let image = context.makeImage() else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let center = (radius * count + radius) * 4
        let hex = SelectionMath.hex(red: bytes[center], green: bytes[center + 1], blue: bytes[center + 2])
        return Sample(image: image, hex: hex)
    }
}
