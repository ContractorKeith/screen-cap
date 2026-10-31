import Foundation

/// An sRGB color with straight (non-premultiplied) alpha. Components are 0...1.
/// A plain value type so the model stays `Sendable` and free of AppKit.
public struct RGBAColor: Sendable, Equatable, Hashable, Codable {
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

    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let red = RGBAColor(red: 1, green: 0.23, blue: 0.19)
    public static let highlightYellow = RGBAColor(red: 1, green: 0.9, blue: 0.2, alpha: 0.5)
}
