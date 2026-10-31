import CoreGraphics

/// Pure thumbnail generation for history and Quick Access.
public enum Thumbnailer {
    /// Default thumbnail width in pixels.
    public static let defaultMaxWidth = 256

    /// Returns `image` scaled to `maxWidth` pixels wide, keeping its aspect ratio.
    /// Images already narrower than `maxWidth` are returned unchanged (never upscaled).
    public static func make(_ image: CGImage, maxWidth: Int = defaultMaxWidth) -> CGImage? {
        guard maxWidth > 0 else { return nil }
        guard image.width > maxWidth else { return image }
        let height = max(1, Int((Double(image.height) * Double(maxWidth) / Double(image.width)).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage()
    }
}
