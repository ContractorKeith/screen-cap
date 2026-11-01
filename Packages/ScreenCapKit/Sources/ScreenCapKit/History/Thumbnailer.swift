import CoreGraphics

/// Pure thumbnail generation for history and Quick Access.
public enum Thumbnailer {
    /// Default thumbnail width in pixels.
    public static let defaultMaxWidth = 256
    /// Width ÷ height of the crop for very long captures, close to a History grid cell (#133).
    public static let cellAspect = 4.0 / 3.0
    /// Long side ÷ short side beyond which a capture is cropped instead of scaled whole.
    public static let longAspect = 3.0

    /// The axis a very long capture runs along, or nil when it's thumbnailed whole.
    public enum Elongation: Equatable, Sendable { case tall, wide }

    /// Whether a `width` × `height` image is long enough to be cropped (scrolling captures).
    public static func elongation(width: Int, height: Int) -> Elongation? {
        guard width > 0, height > 0 else { return nil }
        if Double(height) / Double(width) > longAspect { return .tall }
        if Double(width) / Double(height) > longAspect { return .wide }
        return nil
    }

    /// The part of the image the thumbnail shows, in pixel coordinates with y down. Ordinary
    /// images keep everything; tall ones keep the top at `cellAspect`, wide ones the leading
    /// edge, so a scrolling capture shows its first screenful instead of a sliver.
    public static func cropRect(width: Int, height: Int) -> CGRect {
        switch elongation(width: width, height: height) {
        case .tall:
            let cropHeight = min(height, max(1, Int((Double(width) / cellAspect).rounded())))
            return CGRect(x: 0, y: 0, width: width, height: cropHeight)
        case .wide:
            let cropWidth = min(width, max(1, Int((Double(height) * cellAspect).rounded())))
            return CGRect(x: 0, y: 0, width: cropWidth, height: height)
        case nil:
            return CGRect(x: 0, y: 0, width: width, height: height)
        }
    }

    /// Returns the `cropRect` of `image` scaled to at most `maxWidth` pixels wide, keeping its
    /// aspect ratio. Never upscales; an uncropped image already narrow enough comes back as is.
    public static func make(_ image: CGImage, maxWidth: Int = defaultMaxWidth) -> CGImage? {
        guard maxWidth > 0 else { return nil }
        let crop = cropRect(width: image.width, height: image.height)
        let isWhole = crop.width == CGFloat(image.width) && crop.height == CGFloat(image.height)
        if isWhole, image.width <= maxWidth { return image }
        guard let source = isWhole ? image : image.cropping(to: crop) else { return nil }
        let width = min(maxWidth, source.width)
        let height = max(1, Int((Double(source.height) * Double(width) / Double(source.width)).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
