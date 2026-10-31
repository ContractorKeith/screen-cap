import CoreGraphics
import Foundation

/// Saved image format.
public enum ImageFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg, heic, tiff

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .tiff: "tiff"
        }
    }
}

/// Output scale: keep Retina pixels (2x) or downsample to points (1x).
public enum RetinaScale: Int, Codable, CaseIterable, Sendable {
    case standard = 1
    case retina = 2

    public var factor: CGFloat { CGFloat(rawValue) }
}

/// What "Copy" puts on the pasteboard.
public enum CopyMode: String, Codable, CaseIterable, Sendable {
    case file, image
}

/// What happens right after a capture. Matches the URL scheme's `action` values.
public enum AfterCaptureAction: String, Codable, CaseIterable, Sendable {
    case overlay, copy, save, annotate, pin
}

/// Capture shortcuts that each get their own after-capture action.
public enum CaptureShortcut: String, Codable, CaseIterable, Sendable {
    case area, previousArea, window, fullscreen, scrolling, selfTimer
}

/// Screen corner for the Quick Access overlay.
public enum ScreenCorner: String, Codable, CaseIterable, Sendable {
    case bottomLeft, bottomRight, topLeft, topRight
}

/// Thumbnail size for the Quick Access overlay.
public enum QuickAccessSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large
}

/// Which display shows the Quick Access overlay.
public enum QuickAccessDisplay: String, Codable, CaseIterable, Sendable {
    case withCursor, main
}

/// Quick Access overlay options.
public struct QuickAccessOptions: Codable, Equatable, Sendable {
    public var position: ScreenCorner
    public var size: QuickAccessSize
    /// Seconds before the overlay closes itself; nil means never.
    public var autoCloseSeconds: Int?
    public var display: QuickAccessDisplay

    public init(
        position: ScreenCorner = .bottomLeft,
        size: QuickAccessSize = .medium,
        autoCloseSeconds: Int? = nil,
        display: QuickAccessDisplay = .withCursor
    ) {
        self.position = position
        self.size = size
        self.autoCloseSeconds = autoCloseSeconds
        self.display = display
    }
}

/// A palette color, 0...1 per channel.
public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
