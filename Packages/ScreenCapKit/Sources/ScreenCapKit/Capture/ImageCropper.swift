// Pixel-exact cropping of captured stills.
import CoreGraphics

/// Crops images in pixel space. Pure; no screen access.
public enum ImageCropper {
    /// Crops `image` to `pixelRect` (origin top-left, y down, in pixels).
    ///
    /// The rect is rounded outward to whole pixels and clipped to the image.
    /// Returns nil if nothing is left after clipping.
    public static func crop(_ image: CGImage, pixelRect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = pixelRect.standardized.integral.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        // CGImage.cropping(to:) treats y = 0 as the first (top) row of the image data.
        return image.cropping(to: clipped)
    }
}
