// Sizing and trimming for window captures that keep the system shadow.
import CoreGraphics

/// ScreenCaptureKit reports a window's frame without its shadow, and scales window plus
/// shadow to fit whatever output size is configured. To keep the window pixel-exact, capture
/// once, measure the opaque window body, then capture again at the enlarged size. The result
/// is then trimmed so the shadow margins are symmetric (#100).
public enum WindowShadow {
    /// The window body: bounding box of every fully opaque pixel, in pixels with a top-left
    /// origin. Nil if no pixel is fully opaque.
    ///
    /// A full scan, not a line through the center: translucent sidebars and toolbars on that
    /// line would shrink the body and inflate the re-capture canvas (#100).
    public static func opaqueBounds(of image: CGImage) -> CGRect? {
        AlphaMap(image)?.bounds { $0 == 255 }
    }

    /// Everything the shadow touches: bounding box of every pixel with any alpha.
    public static func shadowBounds(of image: CGImage) -> CGRect? {
        AlphaMap(image)?.bounds { $0 > 0 }
    }

    /// Output size that renders the body at `bodyPixels` given a capture of `canvas` whose body
    /// measured `body`. Returns nil when no enlargement is needed (no shadow, or already 1:1).
    public static func fullSize(canvas: CGSize, body: CGRect, bodyPixels: CGSize) -> CGSize? {
        guard body.width > 0, body.height > 0 else { return nil }
        let scaleX = bodyPixels.width / body.width
        let scaleY = bodyPixels.height / body.height
        guard scaleX > 1.002 || scaleY > 1.002 else { return nil }
        // Even sizes: ScreenCaptureKit can leave the last row of an odd-height image unfilled.
        func even(_ value: CGFloat) -> CGFloat { (value / 2).rounded(.up) * 2 }
        return CGSize(width: even(canvas.width * scaleX), height: even(canvas.height * scaleY))
    }

    /// The body with equal margins on both sides of each axis: per axis, the larger of the two
    /// measured shadow spreads. May extend past the image (that side is padded transparent).
    public static func symmetricFrame(body: CGRect, shadow: CGRect) -> CGRect {
        let dx = max(body.minX - shadow.minX, shadow.maxX - body.maxX, 0)
        let dy = max(body.minY - shadow.minY, shadow.maxY - body.maxY, 0)
        return body.insetBy(dx: -dx, dy: -dy)
    }

    /// `image` cropped (or padded) to `symmetricFrame`, dropping empty canvas past the shadow so
    /// the window sits centered. Nil when there's no opaque body or nothing would change.
    public static func trimmed(_ image: CGImage) -> CGImage? {
        guard let map = AlphaMap(image), let body = map.bounds({ $0 == 255 }),
              let shadow = map.bounds({ $0 > 0 }) else { return nil }
        let frame = symmetricFrame(body: body, shadow: shadow)
        guard frame != CGRect(x: 0, y: 0, width: image.width, height: image.height) else { return nil }
        let width = Int(frame.width), height = Int(frame.height)
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // CG y is bottom-up: image row frame.minY (top-down) lands on the canvas's top row.
        let origin = CGPoint(x: -frame.minX, y: frame.height + frame.minY - CGFloat(image.height))
        context.draw(image, in: CGRect(origin: origin, size: CGSize(width: image.width, height: image.height)))
        return context.makeImage()
    }
}

/// An image's alpha channel, rows top to bottom.
private struct AlphaMap {
    let width: Int
    let height: Int
    let alpha: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        alpha = (0..<(width * height)).map { bytes[$0 * 4 + 3] }
    }

    /// Bounding box (top-left pixels) of the pixels whose alpha passes `test`.
    func bounds(_ test: (UInt8) -> Bool) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for row in 0..<height {
            for column in 0..<width where test(alpha[row * width + column]) {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
