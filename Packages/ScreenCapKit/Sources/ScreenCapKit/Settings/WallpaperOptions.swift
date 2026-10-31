import CoreGraphics
import Foundation

/// The background drawn behind "window with background" captures (PLAN §3.1, Settings → Wallpaper).
public struct WallpaperOptions: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        /// The current desktop picture.
        case desktop
        case solid, gradient, image
    }

    public var style: Style
    public var solidColor: RGBAColor
    public var gradientStart: RGBAColor
    public var gradientEnd: RGBAColor
    /// Degrees, clockwise from left→right (90 = top→bottom), as in `Document.BackgroundFill`.
    public var gradientAngle: Double
    /// Custom image for `.image`.
    public var imageURL: URL?
    /// Points of background around the window on every side.
    public var padding: Double

    public static let paddingRange: ClosedRange<Double> = 0...200

    public init(
        style: Style = .gradient,
        solidColor: RGBAColor = RGBAColor(red: 0.13, green: 0.59, blue: 0.95),
        gradientStart: RGBAColor = RGBAColor(red: 0.42, green: 0.27, blue: 0.93),
        gradientEnd: RGBAColor = RGBAColor(red: 0.98, green: 0.45, blue: 0.55),
        gradientAngle: Double = 45,
        imageURL: URL? = nil,
        padding: Double = 64
    ) {
        self.style = style
        self.solidColor = solidColor
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.gradientAngle = gradientAngle
        self.imageURL = imageURL
        self.padding = padding
    }

    /// Layer name the compositor looks up for `.desktop` / `.image` fills.
    public static let imageLayerName = "wallpaper"

    /// The `Document.Background` for these options. `hasImage` says whether the caller will
    /// supply the decoded desktop picture or custom image under `imageLayerName` in `layers`;
    /// without one the `.desktop` / `.image` styles fall back to the gradient.
    public func background(hasImage: Bool) -> Document.Background {
        let clamped = min(max(padding, Self.paddingRange.lowerBound), Self.paddingRange.upperBound)
        return Document.Background(fill: fill(hasImage: hasImage), padding: clamped)
    }

    private func fill(hasImage: Bool) -> Document.BackgroundFill {
        switch style {
        case .solid:
            return .solid(color: solidColor)
        case .desktop, .image:
            return hasImage ? .customImage(layerName: Self.imageLayerName) : gradientFill
        case .gradient:
            return gradientFill
        }
    }

    private var gradientFill: Document.BackgroundFill {
        .linearGradient(stops: [
            Document.GradientStop(color: gradientStart, location: 0),
            Document.GradientStop(color: gradientEnd, location: 1)
        ], angle: gradientAngle)
    }
}
