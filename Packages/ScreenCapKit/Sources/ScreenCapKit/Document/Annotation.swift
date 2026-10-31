import CoreGraphics
import Foundation

/// One editable object on the canvas. All geometry is in image pixels (PLAN §4).
///
/// The document's array order is creation order (used to number counters);
/// `zIndex` is drawing order (higher draws on top).
public struct Annotation: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var zIndex: Int
    public var style: Style
    public var kind: Kind

    public init(id: UUID = UUID(), zIndex: Int = 0, style: Style = Style(), kind: Kind) {
        self.id = id
        self.zIndex = zIndex
        self.style = style
        self.kind = kind
    }

    /// Style shared by every kind. Kinds that don't use a field ignore it.
    public struct Style: Sendable, Equatable, Codable {
        public var strokeColor: RGBAColor
        public var strokeWidth: Double
        public var fillColor: RGBAColor?
        public var shadow: Document.Shadow?
        public var opacity: Double

        public init(
            strokeColor: RGBAColor = .red,
            strokeWidth: Double = 4,
            fillColor: RGBAColor? = nil,
            shadow: Document.Shadow? = nil,
            opacity: Double = 1
        ) {
            self.strokeColor = strokeColor
            self.strokeWidth = strokeWidth
            self.fillColor = fillColor
            self.shadow = shadow
            self.opacity = opacity
        }
    }

    /// What the annotation is, with its geometry.
    public enum Kind: Sendable, Equatable, Codable {
        case arrow(start: CGPoint, end: CGPoint, style: ArrowStyle)
        case rectangle(rect: CGRect, filled: Bool, cornerRadius: Double)
        case ellipse(rect: CGRect)
        case line(start: CGPoint, end: CGPoint)
        /// `preset` is one of the seven text styles, 1...7.
        case text(string: String, preset: Int, fontSize: Double, rect: CGRect)
        case counter(number: Int, center: CGPoint, radius: Double)
        case path(points: [CGPoint], smoothed: Bool)
        case highlight(region: HighlightRegion, color: RGBAColor)
        case blur(rect: CGRect, mode: BlurMode, radius: Double)
        case pixelate(rect: CGRect, blockSize: Int, randomize: Bool)
        case spotlight(shapes: [SpotlightShape])
        /// `layerName` refers to `layers/<layerName>.png` in the project package.
        case imageLayer(layerName: String, rect: CGRect)
    }

    public enum ArrowStyle: Sendable, Equatable, Codable {
        case straight
        case tapered
        case doubleHeaded
        case curved(control: CGPoint)
    }

    public enum HighlightRegion: Sendable, Equatable, Codable {
        case rect(rect: CGRect)
        case path(points: [CGPoint])
    }

    public enum BlurMode: String, Sendable, Equatable, Codable {
        /// Pixelate first, then blur, so the original can't be recovered (PLAN §5.6).
        case secure
        case smooth
    }

    public enum SpotlightShape: Sendable, Equatable, Codable {
        case rect(rect: CGRect)
        case ellipse(rect: CGRect)
    }
}
