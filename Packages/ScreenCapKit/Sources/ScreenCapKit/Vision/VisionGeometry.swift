import CoreGraphics
import Foundation

/// Converts between Vision's coordinate space and image pixels.
///
/// Vision reports boxes normalized to 0...1 with a bottom-left origin. The rest of the app works in
/// image pixels with a top-left origin, so every Vision result passes through here.
public enum VisionGeometry {
    /// Normalized, bottom-left-origin rect -> pixel rect with a top-left origin.
    public static func imageRect(fromNormalized rect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * imageSize.width,
            y: (1 - rect.maxY) * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        )
    }

    /// Pixel size of a CGImage.
    static func size(of image: CGImage) -> CGSize {
        CGSize(width: image.width, height: image.height)
    }

    /// Runs blocking Vision work off the Swift concurrency pool so callers don't stall it.
    static func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
