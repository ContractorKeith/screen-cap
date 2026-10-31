import CoreGraphics
import ScreenCapKit

/// Converts a URL `Region` (points, lower-left origin of a 1-based display) to the global
/// AppKit rect the coordinator uses. Pure, so it is unit-tested.
enum RegionMapper {
    /// - Parameter displayFrames: Display frames in global AppKit points, in `NSScreen.screens`
    ///   order (display 1 is the primary display, the one with the menu bar).
    /// - Returns: nil when the display doesn't exist or the region doesn't lie fully inside it
    ///   (a partly-off region would otherwise be clipped silently).
    static func globalRect(for region: Region, displayFrames: [CGRect]) -> CGRect? {
        guard displayFrames.indices.contains(region.display - 1) else { return nil }
        let frame = displayFrames[region.display - 1]
        let rect = CGRect(x: frame.minX + region.x, y: frame.minY + region.y,
                          width: region.width, height: region.height)
        guard frame.contains(rect) else { return nil }
        return rect
    }
}
