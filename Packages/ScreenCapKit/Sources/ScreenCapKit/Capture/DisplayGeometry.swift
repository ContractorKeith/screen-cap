// Display geometry: global AppKit points <-> per-display image pixels (PLAN §4, Coordinates).
import CoreGraphics

/// One display as the capture layer sees it.
///
/// `frame` is in global AppKit points: origin at the bottom-left of the primary display, y up.
/// A display's captured image is `pixelSize` pixels with its origin at the top-left, y down.
public struct DisplayInfo: Sendable, Hashable, Identifiable {
    /// The Quartz display ID (matches `SCDisplay.displayID` and `NSScreenNumber`).
    public let id: CGDirectDisplayID
    /// Display bounds in global AppKit points.
    public let frame: CGRect
    /// Pixels per point (2 on Retina, 1 on most externals).
    public let backingScale: CGFloat

    public init(id: CGDirectDisplayID, frame: CGRect, backingScale: CGFloat) {
        self.id = id
        self.frame = frame
        self.backingScale = backingScale
    }

    /// Size of a full-display capture in pixels.
    public var pixelSize: CGSize {
        CGSize(
            width: (frame.width * backingScale).rounded(),
            height: (frame.height * backingScale).rounded()
        )
    }

    /// Converts a global point rect to a pixel rect in this display's image (top-left origin).
    ///
    /// Not clipped to the display. Edges are rounded to the nearest pixel, so integral point
    /// rects map exactly at any integer scale.
    public func pixelRect(forGlobalPoints rect: CGRect) -> CGRect {
        let rect = rect.standardized
        let minX = ((rect.minX - frame.minX) * backingScale).rounded()
        let maxX = ((rect.maxX - frame.minX) * backingScale).rounded()
        // Flip: AppKit y grows up from the display's bottom; image rows grow down from its top.
        let minY = ((frame.maxY - rect.maxY) * backingScale).rounded()
        let maxY = ((frame.maxY - rect.minY) * backingScale).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Converts a pixel rect in this display's image back to global AppKit points.
    public func globalPointRect(forPixelRect rect: CGRect) -> CGRect {
        let rect = rect.standardized
        let width = rect.width / backingScale
        let height = rect.height / backingScale
        let minX = frame.minX + rect.minX / backingScale
        let minY = frame.maxY - rect.minY / backingScale - height
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Converts a global point to a pixel position in this display's image.
    public func pixelPoint(forGlobalPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - frame.minX) * backingScale,
            y: (frame.maxY - point.y) * backingScale
        )
    }
}

/// The part of a global rect that falls on one display.
public struct DisplaySlice: Sendable, Hashable {
    /// The display this slice lies on.
    public let display: DisplayInfo
    /// The clipped rect in global AppKit points.
    public let pointRect: CGRect
    /// The same area in the display image's pixels (top-left origin).
    public let pixelRect: CGRect
}

/// The arrangement of all displays, and every point/pixel conversion between them.
///
/// Handles mixed DPI, displays above, below or left of the primary one, and negative origins.
public struct DisplayGeometry: Sendable, Hashable {
    /// Displays in the order given; the primary display is the one at origin (0, 0).
    public let displays: [DisplayInfo]

    public init(displays: [DisplayInfo]) {
        self.displays = displays
    }

    /// The primary display (AppKit origin at its bottom-left), or the first one if none sits at zero.
    public var primaryDisplay: DisplayInfo? {
        displays.first { $0.frame.origin == .zero } ?? displays.first
    }

    /// Bounding box of every display, in global AppKit points.
    public var unionFrame: CGRect {
        displays.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// Looks up a display by ID.
    public func display(id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    /// The display under a global point. Frames are half-open, so a shared edge belongs to one display.
    public func display(containing point: CGPoint) -> DisplayInfo? {
        displays.first { $0.frame.contains(point) }
    }

    /// The display holding the largest part of a rect, or nil if it touches none.
    public func display(bestFor rect: CGRect) -> DisplayInfo? {
        slices(forGlobalPoints: rect).max { $0.area < $1.area }?.display
    }

    /// Splits a global point rect into one slice per display it overlaps, in display order.
    public func slices(forGlobalPoints rect: CGRect) -> [DisplaySlice] {
        displays.compactMap { display in
            let clipped = display.frame.intersection(rect.standardized)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
            return DisplaySlice(
                display: display,
                pointRect: clipped,
                pixelRect: display.pixelRect(forGlobalPoints: clipped)
            )
        }
    }

    /// Converts a Quartz global rect (origin top-left of the primary display, y down) to AppKit points.
    ///
    /// `SCWindow.frame`, `SCDisplay.frame` and `CGWindowListCopyWindowInfo` bounds use Quartz space.
    public func appKitRect(fromQuartz rect: CGRect) -> CGRect {
        let primaryHeight = primaryDisplay?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts an AppKit global rect to Quartz global space. Inverse of `appKitRect(fromQuartz:)`.
    public func quartzRect(fromAppKit rect: CGRect) -> CGRect {
        // The flip is its own inverse.
        appKitRect(fromQuartz: rect)
    }
}

private extension DisplaySlice {
    var area: CGFloat { pointRect.width * pointRect.height }
}
