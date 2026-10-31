// Background tool: places a screenshot on a padded fill with rounded corners and a shadow.
import CoreGraphics
import Foundation

/// One color stop of a linear gradient. `location` is 0...1.
public struct EffectsGradientStop: Equatable, Sendable {
    public var color: EffectsColor
    public var location: Double

    public init(color: EffectsColor, location: Double) {
        self.color = color
        self.location = location
    }
}

/// Where the screenshot sits when the canvas grows beyond its padding (aspect ratio).
public enum EffectsAlignment: Sendable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    /// Fraction of extra space placed before the image on each axis (0, 0.5 or 1).
    var factors: CGPoint {
        switch self {
        case .topLeading: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: 0.5, y: 0)
        case .topTrailing: return CGPoint(x: 1, y: 0)
        case .leading: return CGPoint(x: 0, y: 0.5)
        case .center: return CGPoint(x: 0.5, y: 0.5)
        case .trailing: return CGPoint(x: 1, y: 0.5)
        case .bottomLeading: return CGPoint(x: 0, y: 1)
        case .bottom: return CGPoint(x: 0.5, y: 1)
        case .bottomTrailing: return CGPoint(x: 1, y: 1)
        }
    }
}

public struct BackgroundSpec {
    public enum Fill {
        case solid(EffectsColor)
        /// `angle` in degrees, clockwise from left→right (90 = top→bottom).
        case linearGradient(stops: [EffectsGradientStop], angle: Double)
        /// Drawn aspect-fill across the whole canvas.
        case image(CGImage)
    }

    public var fill: Fill
    public var padding: EffectsInsets
    public var cornerRadius: CGFloat
    public var shadow: EffectsShadow?
    public var alignment: EffectsAlignment
    /// Target width / height. The canvas only grows to reach it, never crops.
    public var aspectRatio: CGFloat?

    public init(
        fill: Fill,
        padding: EffectsInsets = EffectsInsets(all: 64),
        cornerRadius: CGFloat = 0,
        shadow: EffectsShadow? = nil,
        alignment: EffectsAlignment = .center,
        aspectRatio: CGFloat? = nil
    ) {
        self.fill = fill
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.alignment = alignment
        self.aspectRatio = aspectRatio
    }
}

public enum BackgroundCompositor {
    /// Canvas size and the screenshot's frame (top-left pixels) for `spec`.
    public static func layout(imageSize: CGSize, spec: BackgroundSpec) -> (canvas: CGSize, frame: CGRect) {
        let pad = spec.padding
        var width = (imageSize.width + pad.left + pad.right).rounded()
        var height = (imageSize.height + pad.top + pad.bottom).rounded()
        let baseWidth = width
        let baseHeight = height
        if let ratio = spec.aspectRatio, ratio > 0 {
            if width / height < ratio {
                width = (height * ratio).rounded(.up)
            } else {
                height = (width / ratio).rounded(.up)
            }
        }
        let factors = spec.alignment.factors
        let origin = CGPoint(
            x: (pad.left + (width - baseWidth) * factors.x).rounded(),
            y: (pad.top + (height - baseHeight) * factors.y).rounded()
        )
        return (CGSize(width: width, height: height), CGRect(origin: origin, size: imageSize))
    }

    /// Composites `image` onto the background described by `background`.
    public static func render(_ image: CGImage, background: BackgroundSpec) throws -> CGImage {
        let imageSize = CGSize(width: image.width, height: image.height)
        let (canvas, frame) = layout(imageSize: imageSize, spec: background)
        let bitmap = try EffectsBitmap(width: Int(canvas.width), height: Int(canvas.height))
        let context = bitmap.context
        let full = CGRect(origin: .zero, size: canvas)

        drawFill(background.fill, in: bitmap, rect: full)

        let target = bitmap.cgRect(frame)
        let radius = min(background.cornerRadius, min(frame.width, frame.height) / 2)
        let path = CGPath(roundedRect: target, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        if let shadow = background.shadow {
            var color = shadow.color
            color.alpha *= shadow.opacity
            // Shadow offsets are in base space (y up); our offset is y down.
            context.setShadow(
                offset: CGSize(width: shadow.offset.width, height: -shadow.offset.height),
                blur: shadow.blur, color: color.cgColor
            )
        }
        // The transparency layer lets the shadow follow the clipped, rounded image.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(path)
        context.clip()
        context.draw(image, in: target)
        context.endTransparencyLayer()
        context.restoreGState()

        return try bitmap.makeImage()
    }

    private static func drawFill(_ fill: BackgroundSpec.Fill, in bitmap: EffectsBitmap, rect: CGRect) {
        let context = bitmap.context
        switch fill {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .linearGradient(let stops, let angle):
            drawGradient(stops: stops, angle: angle, in: context, rect: rect)
        case .image(let fillImage):
            let scale = max(rect.width / CGFloat(fillImage.width), rect.height / CGFloat(fillImage.height))
            let size = CGSize(width: CGFloat(fillImage.width) * scale, height: CGFloat(fillImage.height) * scale)
            let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
            context.interpolationQuality = .high
            context.draw(fillImage, in: CGRect(origin: origin, size: size))
        }
    }

    private static func drawGradient(
        stops: [EffectsGradientStop], angle: Double, in context: CGContext, rect: CGRect
    ) {
        guard let first = stops.first else { return }
        let sorted = stops.count == 1 ? [first, first] : stops.sorted { $0.location < $1.location }
        guard let gradient = CGGradient(
            colorsSpace: EffectsBitmap.colorSpace,
            colors: sorted.map(\.color.cgColor) as CFArray,
            locations: sorted.map { CGFloat($0.location) }
        ) else { return }
        // Direction in CG space: clockwise in top-left space is clockwise-negative in y-up space.
        let radians = angle * .pi / 180
        let direction = CGVector(dx: cos(radians), dy: -sin(radians))
        let half = (abs(rect.width * direction.dx) + abs(rect.height * direction.dy)) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = CGPoint(x: center.x - direction.dx * half, y: center.y - direction.dy * half)
        let end = CGPoint(x: center.x + direction.dx * half, y: center.y + direction.dy * half)
        context.drawLinearGradient(
            gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}
