// Value types the capture service returns.
import CoreGraphics
import Foundation

/// A captured still plus where it came from.
public struct CapturedImage: @unchecked Sendable {
    // @unchecked: CGImage is immutable and thread-safe, but not annotated Sendable in every SDK.

    /// The pixels. Origin top-left.
    public let cgImage: CGImage
    /// Image size in pixels.
    public let pixelSize: CGSize
    /// Pixels per point.
    public let scale: CGFloat
    /// The area the image covers, in global AppKit points.
    public let pointRect: CGRect
    /// The display the image came from (for windows, the display holding most of it). Nil if none.
    public let displayID: CGDirectDisplayID?

    public init(cgImage: CGImage, scale: CGFloat, pointRect: CGRect, displayID: CGDirectDisplayID?) {
        self.cgImage = cgImage
        self.pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        self.scale = scale
        self.pointRect = pointRect
        self.displayID = displayID
    }

    /// Crops this still to a global point rect, clipped to the area it covers.
    ///
    /// This is how area capture works on a frozen screen (PLAN §5.1): crop the display still.
    /// Returns nil if the rect doesn't overlap this image.
    public func cropped(toGlobalPoints rect: CGRect) -> CapturedImage? {
        let clipped = pointRect.intersection(rect.standardized)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        let local = DisplayInfo(id: displayID ?? 0, frame: pointRect, backingScale: scale)
        let pixelRect = local.pixelRect(forGlobalPoints: clipped)
        guard let image = ImageCropper.crop(cgImage, pixelRect: pixelRect) else { return nil }
        return CapturedImage(cgImage: image, scale: scale, pointRect: clipped, displayID: displayID)
    }
}

/// An on-screen window that can be captured.
public struct ShareableWindow: Sendable, Hashable, Identifiable {
    /// The Quartz window ID.
    public let id: CGWindowID
    /// Window bounds in global AppKit points.
    public let frame: CGRect
    /// Window title, if the owner exposes one.
    public let title: String?
    /// Owning app's display name.
    public let appName: String?
    /// Owning app's bundle identifier.
    public let bundleIdentifier: String?
    /// Owning process.
    public let processID: pid_t
    /// Window layer; 0 is normal app windows, higher is panels, menus and the menu bar.
    public let layer: Int

    public init(
        id: CGWindowID,
        frame: CGRect,
        title: String?,
        appName: String?,
        bundleIdentifier: String?,
        processID: pid_t,
        layer: Int
    ) {
        self.id = id
        self.frame = frame
        self.title = title
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.layer = layer
    }

    /// Orders windows front to back by a z-order list of IDs (frontmost first).
    ///
    /// Windows missing from `zOrder` keep their relative order and go after the ordered ones.
    public static func orderedFrontToBack(_ windows: [ShareableWindow], zOrder: [CGWindowID]) -> [ShareableWindow] {
        let rank = Dictionary(zOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return windows.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element.id] ?? Int.max
                let right = rank[rhs.element.id] ?? Int.max
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// The frontmost window under a global point, from a front-to-back list.
    public static func topmost(at point: CGPoint, in windows: [ShareableWindow]) -> ShareableWindow? {
        windows.first { $0.frame.contains(point) }
    }
}

/// Why a capture failed.
public enum CaptureError: Error, Equatable {
    /// No display with this ID is currently shareable.
    case displayNotFound(CGDirectDisplayID)
    /// No on-screen window with this ID is currently shareable.
    case windowNotFound(CGWindowID)
    /// The requested area doesn't overlap any display.
    case areaOffScreen(CGRect)
}

extension CaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .displayNotFound: "That display is no longer available."
        case .windowNotFound: "That window is no longer on screen."
        case .areaOffScreen: "The selected area isn't on any display."
        }
    }
}
