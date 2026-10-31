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
    /// Degrees, clockwise from left→right (90 = top→bottom), as in `BackgroundSpec.Fill`.
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

    /// A compositor spec for these options. `image` is the decoded desktop picture or custom
    /// image for `.desktop` / `.image`; without one those styles fall back to the gradient.
    public func backgroundSpec(image: CGImage?) -> BackgroundSpec {
        let clamped = min(max(padding, Self.paddingRange.lowerBound), Self.paddingRange.upperBound)
        return BackgroundSpec(fill: fill(image: image), padding: EffectsInsets(all: CGFloat(clamped)))
    }

    private func fill(image: CGImage?) -> BackgroundSpec.Fill {
        switch style {
        case .solid:
            return .solid(EffectsColor(solidColor))
        case .desktop, .image:
            if let image { return .image(image) }
            return gradientFill
        case .gradient:
            return gradientFill
        }
    }

    private var gradientFill: BackgroundSpec.Fill {
        .linearGradient(stops: [
            EffectsGradientStop(color: EffectsColor(gradientStart), location: 0),
            EffectsGradientStop(color: EffectsColor(gradientEnd), location: 1)
        ], angle: gradientAngle)
    }
}

extension EffectsColor {
    init(_ color: RGBAColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
