import CoreGraphics
import Foundation

/// Draws a `Document` with Core Graphics. The editor canvas and the exporter both draw through
/// this one type, so what you see is what gets saved (PLAN §4).
///
/// Model geometry is in image pixels with a top-left origin; the renderer sets up the flip
/// and scale itself, so callers hand it an unflipped context.
public struct Renderer: Sendable {
    /// Pixel effects hook for blur, pixelate and spotlight.
    public var redaction: any RedactionRenderer

    public init(redaction: any RedactionRenderer = NoOpRedactionRenderer()) {
        self.redaction = redaction
    }

    /// Output size in pixels for `document` under `options`.
    public static func pixelSize(for document: Document, options: RenderOptions) -> (width: Int, height: Int) {
        let canvas = layout(for: document, options: options).canvas
        return (Int((canvas.width * options.scale).rounded()), Int((canvas.height * options.scale).rounded()))
    }

    /// Renders `document` into a new sRGB RGBA bitmap of `pixelSize(for:options:)`.
    /// `layers` maps layer names (image layers, custom or bundled backgrounds) to images.
    public func image(
        for document: Document,
        baseImage: CGImage,
        layers: [String: CGImage] = [:],
        options: RenderOptions = RenderOptions()
    ) throws -> CGImage {
        guard options.scale > 0, options.scale.isFinite else { throw RenderError.invalidScale(options.scale) }
        let size = Self.pixelSize(for: document, options: options)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: max(size.width, 1), height: max(size.height, 1),
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw RenderError.contextCreationFailed }
        draw(document, baseImage: baseImage, layers: layers, options: options, in: context)
        guard let image = context.makeImage() else { throw RenderError.contextCreationFailed }
        return image
    }

    /// Draws into a caller-provided context whose base space is `pixelSize(for:options:)` pixels
    /// with the usual bottom-left origin (any bitmap or PDF context). Graphics state is restored.
    /// Redaction effects need pixels to read back, so they only apply in bitmap contexts.
    public func draw(
        _ document: Document,
        baseImage: CGImage,
        layers: [String: CGImage] = [:],
        options: RenderOptions = RenderOptions(),
        in context: CGContext
    ) {
        guard options.scale > 0, options.scale.isFinite else { return }
        let layout = Self.layout(for: document, options: options)
        let scale = options.scale

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: 0, y: layout.canvas.height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.interpolationQuality = .high

        if let background = layout.background {
            BackgroundPainter.draw(background, layout: layout, baseImage: baseImage, layers: layers, in: context)
        } else {
            context.drawUpright(baseImage, in: layout.imageFrame)
        }

        context.translateBy(x: layout.imageFrame.minX, y: layout.imageFrame.minY)
        let origin = layout.imageFrame.origin
        for annotation in document.drawOrder {
            switch annotation.kind {
            case .blur, .pixelate, .spotlight:
                applyRedaction(annotation.kind, origin: origin, scale: scale, in: context)
            default:
                AnnotationPainter.draw(annotation, layers: layers, scale: scale, in: context)
            }
        }
    }

    // MARK: - Layout

    struct Layout {
        var canvas: CGSize
        /// Where the base image (and the annotation coordinate space) sits on the canvas.
        var imageFrame: CGRect
        var background: Document.Background?
        var scale: Double
    }

    static func layout(for document: Document, options: RenderOptions) -> Layout {
        let imageSize = document.baseImage.pixelSize
        guard options.includeBackground, let background = document.background else {
            return Layout(canvas: imageSize, imageFrame: CGRect(origin: .zero, size: imageSize), background: nil,
                          scale: options.scale)
        }
        let canvas = document.canvasSize
        let inner = CGRect(origin: .zero, size: canvas).insetBy(dx: background.padding, dy: background.padding)
        let x: Double
        let y: Double
        switch background.alignment {
        case .left, .topLeft, .bottomLeft: x = inner.minX
        case .right, .topRight, .bottomRight: x = inner.maxX - imageSize.width
        case .center, .top, .bottom: x = inner.midX - imageSize.width / 2
        }
        switch background.alignment {
        case .top, .topLeft, .topRight: y = inner.minY
        case .bottom, .bottomLeft, .bottomRight: y = inner.maxY - imageSize.height
        case .center, .left, .right: y = inner.midY - imageSize.height / 2
        }
        return Layout(canvas: canvas, imageFrame: CGRect(origin: CGPoint(x: x, y: y), size: imageSize),
                      background: background, scale: options.scale)
    }

    // MARK: - Redaction

    /// Snapshots the canvas, lets the hook transform it, and draws the result back 1:1.
    private func applyRedaction(_ kind: Annotation.Kind, origin: CGPoint, scale: Double, in context: CGContext) {
        guard let snapshot = context.makeImage() else { return }
        let mapped = kind.mapped(scale: scale) { point in
            CGPoint(x: (point.x + origin.x) * scale, y: (point.y + origin.y) * scale)
        }
        guard let result = redaction.apply(mapped, to: snapshot, scale: scale) else { return }
        context.saveGState()
        context.concatenate(context.ctm.inverted())
        context.setBlendMode(.copy)
        context.draw(result, in: CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height))
        context.restoreGState()
    }
}

/// Fill, padding, corner radius and shadow behind the base image (PLAN §3.3 Background tool).
enum BackgroundPainter {
    static func draw(_ background: Document.Background, layout: Renderer.Layout, baseImage: CGImage,
                     layers: [String: CGImage], in context: CGContext) {
        let canvasRect = CGRect(origin: .zero, size: layout.canvas)
        let imageFrame = layout.imageFrame
        let scale = layout.scale
        switch background.fill {
        case let .solid(color):
            context.setFillColor(color.cgColor)
            context.fill(canvasRect)
        case let .linearGradient(stops, angle):
            drawGradient(stops: stops, angle: angle, in: canvasRect, context: context)
        case let .bundled(name), let .customImage(name):
            // Bundled backgrounds live in the app, so callers pass them in `layers` too.
            if let image = layers[name] { drawAspectFill(image, in: canvasRect, context: context) }
        }

        let radius = min(max(background.cornerRadius, 0), imageFrame.width / 2, imageFrame.height / 2)
        let clip = CGPath(roundedRect: imageFrame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        if let shadow = background.shadow { AnnotationPainter.setShadow(shadow, scale: scale, in: context) }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(clip)
        context.clip()
        context.drawUpright(baseImage, in: imageFrame)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// `angle` in degrees: 0 = left to right, 90 = bottom to top (model y points down).
    private static func drawGradient(stops: [Document.GradientStop], angle: Double, in rect: CGRect,
                                     context: CGContext) {
        guard !stops.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let sorted = stops.sorted { $0.location < $1.location }
        guard let gradient = CGGradient(colorsSpace: space, colors: sorted.map(\.color.cgColor) as CFArray,
                                        locations: sorted.map { CGFloat($0.location) }) else { return }
        let radians = angle * .pi / 180
        let direction = CGVector(dx: cos(radians), dy: -sin(radians))
        let half = (abs(rect.width * direction.dx) + abs(rect.height * direction.dy)) / 2
        let start = CGPoint(x: rect.midX - direction.dx * half, y: rect.midY - direction.dy * half)
        let end = CGPoint(x: rect.midX + direction.dx * half, y: rect.midY + direction.dy * half)
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func drawAspectFill(_ image: CGImage, in rect: CGRect, context: CGContext) {
        let fill = max(rect.width / Double(image.width), rect.height / Double(image.height))
        let size = CGSize(width: Double(image.width) * fill, height: Double(image.height) * fill)
        let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                            width: size.width, height: size.height)
        context.saveGState()
        context.clip(to: rect)
        context.drawUpright(image, in: target)
        context.restoreGState()
    }
}
