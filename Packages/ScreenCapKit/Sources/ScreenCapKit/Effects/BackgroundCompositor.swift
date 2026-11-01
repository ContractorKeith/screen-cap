// Background tool: places a screenshot on a padded fill with rounded corners and a shadow.
import CoreGraphics
import Foundation

extension Document.Alignment {
    /// Fraction of extra space placed before the image on each axis (0, 0.5 or 1).
    var factors: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: 0.5, y: 0)
        case .topRight: return CGPoint(x: 1, y: 0)
        case .left: return CGPoint(x: 0, y: 0.5)
        case .center: return CGPoint(x: 0.5, y: 0.5)
        case .right: return CGPoint(x: 1, y: 0.5)
        case .bottomLeft: return CGPoint(x: 0, y: 1)
        case .bottom: return CGPoint(x: 0.5, y: 1)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        }
    }
}

/// Composites a screenshot onto a `Document.Background`, growing the canvas to fit.
///
/// Two inputs the document model doesn't store are render-time options: per-edge `padding`
/// (Auto Balance output; nil uses `background.padding` on every edge) and `aspectRatio`
/// (width / height; the canvas only grows to reach it, never crops).
public enum BackgroundCompositor {
    /// Canvas size and the screenshot's frame (top-left pixels).
    public static func layout(
        imageSize: CGSize, background: Document.Background, padding: EffectsInsets? = nil,
        aspectRatio: CGFloat? = nil
    ) -> (canvas: CGSize, frame: CGRect) {
        let pad = padding ?? EffectsInsets(all: background.padding)
        var width = (imageSize.width + pad.left + pad.right).rounded()
        var height = (imageSize.height + pad.top + pad.bottom).rounded()
        let baseWidth = width
        let baseHeight = height
        if let ratio = aspectRatio, ratio > 0 {
            if width / height < ratio {
                width = (height * ratio).rounded(.up)
            } else {
                height = (width / ratio).rounded(.up)
            }
        }
        let factors = background.alignment.factors
        let origin = CGPoint(
            x: (pad.left + (width - baseWidth) * factors.x).rounded(),
            y: (pad.top + (height - baseHeight) * factors.y).rounded()
        )
        return (CGSize(width: width, height: height), CGRect(origin: origin, size: imageSize))
    }

    /// Composites `image` onto `background`. Bundled and custom image fills are looked up by
    /// name in `layers`; a missing one leaves the canvas transparent behind the screenshot.
    public static func render(
        _ image: CGImage, background: Document.Background, layers: [String: CGImage] = [:],
        padding: EffectsInsets? = nil, aspectRatio: CGFloat? = nil
    ) throws -> CGImage {
        let imageSize = CGSize(width: image.width, height: image.height)
        let (canvas, frame) = layout(imageSize: imageSize, background: background, padding: padding,
                                     aspectRatio: aspectRatio)
        guard DocumentLimits.size(canvas) else { throw ProjectFileError.invalidGeometry("background geometry") }
        let bitmap = try EffectsBitmap(width: Int(canvas.width), height: Int(canvas.height))
        let context = bitmap.context
        let full = CGRect(origin: .zero, size: canvas)

        drawFill(background.fill, layers: layers, in: bitmap, rect: full)

        let target = bitmap.cgRect(frame)
        let radius = min(background.cornerRadius, min(frame.width, frame.height) / 2)
        let path = CGPath(roundedRect: target, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        if let shadow = background.shadow {
            // Shadow offsets are in base space (y up); the model's offset is y down.
            context.setShadow(
                offset: CGSize(width: shadow.offset.width, height: -shadow.offset.height),
                blur: shadow.radius, color: shadow.color.cgColor
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

    private static func drawFill(
        _ fill: Document.BackgroundFill, layers: [String: CGImage], in bitmap: EffectsBitmap, rect: CGRect
    ) {
        let context = bitmap.context
        switch fill {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .linearGradient(let stops, let angle):
            drawGradient(stops: stops, angle: angle, in: context, rect: rect)
        case .bundled(let name), .customImage(let name):
            guard let fillImage = layers[name] else { return }
            let scale = max(rect.width / CGFloat(fillImage.width), rect.height / CGFloat(fillImage.height))
            let size = CGSize(width: CGFloat(fillImage.width) * scale, height: CGFloat(fillImage.height) * scale)
            let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
            context.interpolationQuality = .high
            context.draw(fillImage, in: CGRect(origin: origin, size: size))
        }
    }

    private static func drawGradient(
        stops: [Document.GradientStop], angle: Double, in context: CGContext, rect: CGRect
    ) {
        guard let first = stops.first else { return }
        let sorted = stops.count == 1 ? [first, first] : stops.sorted { $0.location < $1.location }
        guard let gradient = CGGradient(
            colorsSpace: EffectsBitmap.colorSpace,
            colors: sorted.map(\.color.cgColor) as CFArray,
            locations: sorted.map { CGFloat($0.location) }
        ) else { return }
        // Model convention: 0 = left to right, 90 = bottom to top. CG space here is y up.
        let radians = angle * .pi / 180
        let direction = CGVector(dx: cos(radians), dy: sin(radians))
        let half = (abs(rect.width * direction.dx) + abs(rect.height * direction.dy)) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = CGPoint(x: center.x - direction.dx * half, y: center.y - direction.dy * half)
        let end = CGPoint(x: center.x + direction.dx * half, y: center.y + direction.dy * half)
        context.drawLinearGradient(
            gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}
