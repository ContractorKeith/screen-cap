// Sizing for window captures that keep the system shadow.
import CoreGraphics

/// ScreenCaptureKit reports a window's frame without its shadow, and scales window plus
/// shadow to fit whatever output size is configured. To keep the window pixel-exact, capture
/// once, measure the opaque window body, then capture again at the enlarged size.
public enum WindowShadow {
    /// The window body: the fully opaque run through the image center along the middle row and
    /// column, in pixels with a top-left origin. Nil if the center pixel isn't opaque.
    ///
    /// Scanning only through the center ignores stray opaque pixels elsewhere in the shadow.
    public static func opaqueBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        // Bitmap memory rows run top to bottom.
        func opaque(_ column: Int, _ row: Int) -> Bool { bytes[(row * width + column) * 4 + 3] == 255 }
        let midX = width / 2, midY = height / 2
        guard opaque(midX, midY) else { return nil }
        var minX = midX, maxX = midX, minY = midY, maxY = midY
        while minX > 0, opaque(minX - 1, midY) { minX -= 1 }
        while maxX < width - 1, opaque(maxX + 1, midY) { maxX += 1 }
        while minY > 0, opaque(midX, minY - 1) { minY -= 1 }
        while maxY < height - 1, opaque(midX, maxY + 1) { maxY += 1 }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
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
}
