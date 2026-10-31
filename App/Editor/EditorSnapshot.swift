import CoreGraphics
import Foundation
import ImageIO
import ScreenCapKit

/// One undoable editor state. `Document` alone can't undo a crop or rotate, because those
/// replace the base pixels, so the snapshot carries the images with it. CGImages are
/// immutable and shared between snapshots, so a snapshot is cheap to copy.
struct EditorSnapshot: @unchecked Sendable {
    // @unchecked: CGImage is immutable and thread-safe, but not annotated Sendable in every SDK.
    var document: Document
    var baseImage: CGImage
    /// Image layers and a custom background, by layer name. May hold unreferenced layers so
    /// undoing a delete can bring them back; saving writes only the referenced ones.
    var layers: [String: CGImage]
    /// Background canvas aspect ratio (width ÷ height), or nil for padding only.
    var backgroundAspect: Double?

    init(document: Document, baseImage: CGImage, layers: [String: CGImage] = [:], backgroundAspect: Double? = nil) {
        self.document = document
        self.baseImage = baseImage
        self.layers = layers
        self.backgroundAspect = backgroundAspect
    }

    /// A fresh document around `image` at `scale` pixels per point.
    init(image: CGImage, scale: Double) {
        let base = Document.BaseImage(pixelWidth: image.width, pixelHeight: image.height, scale: scale)
        self.init(document: Document(baseImage: base), baseImage: image)
    }

    var imageSize: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }

    var referencedLayers: [String: CGImage] {
        layers.filter { document.referencedLayerNames.contains($0.key) }
    }

    /// Replaces the base image, maps every annotation through `transform`, and refits the canvas.
    mutating func replaceBase(with image: CGImage, scale: Double = 1, mapping transform: (CGPoint) -> CGPoint) {
        baseImage = image
        document.baseImage.pixelWidth = image.width
        document.baseImage.pixelHeight = image.height
        for index in document.annotations.indices {
            var annotation = document.annotations[index]
            annotation.kind = annotation.kind.mapped(scale: scale, transform)
            if case let .text(string, preset, fontSize, rect) = annotation.kind {
                annotation.kind = .text(string: string, preset: preset, fontSize: fontSize * scale, rect: rect)
            }
            document.annotations[index] = annotation
        }
        refitCanvas()
    }

    /// Recomputes `canvasSize` from the base image, background padding and aspect ratio.
    mutating func refitCanvas() {
        document.canvasSize = BackgroundMath.canvasSize(
            imageSize: imageSize, background: document.background, aspect: backgroundAspect
        )
    }
}

/// Canvas sizing and Auto Balance mapping for the Background tool (PLAN §3.3, §5.5).
enum BackgroundMath {
    /// Canvas for `background` around an image: padding on every side, then grown (never
    /// cropped) to `aspect` through the same layout the compositor uses.
    static func canvasSize(imageSize: CGSize, background: Document.Background?, aspect: Double?) -> CGSize {
        guard let background else { return imageSize }
        return BackgroundCompositor.layout(
            imageSize: imageSize, background: background, aspectRatio: aspect.map { CGFloat($0) }
        ).canvas
    }

    /// Where the base image sits on the canvas. Mirrors the renderer's layout so canvas clicks
    /// map into image pixels.
    static func imageFrame(for document: Document) -> CGRect {
        let size = document.baseImage.pixelSize
        guard let background = document.background else { return CGRect(origin: .zero, size: size) }
        let inner = CGRect(origin: .zero, size: document.canvasSize)
            .insetBy(dx: background.padding, dy: background.padding)
        let x: Double = switch background.alignment {
        case .left, .topLeft, .bottomLeft: inner.minX
        case .right, .topRight, .bottomRight: inner.maxX - size.width
        case .center, .top, .bottom: inner.midX - size.width / 2
        }
        let y: Double = switch background.alignment {
        case .top, .topLeft, .topRight: inner.minY
        case .bottom, .bottomLeft, .bottomRight: inner.maxY - size.height
        case .center, .left, .right: inner.midY - size.height / 2
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Fits Auto Balance's per-edge insets to the model's uniform padding plus alignment, for a
    /// canvas of image + insets. Exact when only one axis is unbalanced (the usual window shadow).
    static func balanced(_ insets: EffectsInsets) -> (padding: Double, alignment: Document.Alignment) {
        let horizontal = side(insets.left, insets.right)
        let vertical = side(insets.top, insets.bottom)
        let padding: Double = if vertical != 0 {
            Double(min(insets.top, insets.bottom))
        } else if horizontal != 0 {
            Double(min(insets.left, insets.right))
        } else {
            Double((insets.top + insets.bottom + insets.left + insets.right) / 4)
        }
        let grid: [[Document.Alignment]] = [[.topLeft, .top, .topRight], [.left, .center, .right],
                                            [.bottomLeft, .bottom, .bottomRight]]
        return (padding.rounded(), grid[vertical + 1][horizontal + 1])
    }

    /// -1 when the leading side is tighter, 1 when the trailing side is, 0 within a pixel.
    private static func side(_ leading: CGFloat, _ trailing: CGFloat) -> Int {
        abs(leading - trailing) <= 1 ? 0 : (leading < trailing ? -1 : 1)
    }
}

/// Base-image pixel operations: crop, rotate, flip and resize. Each returns the new image and
/// the point mapping that carries annotations along (top-left image pixels).
enum ImageOps {
    struct Result {
        var image: CGImage
        var scale: Double = 1
        var map: (CGPoint) -> CGPoint
    }

    static func crop(_ image: CGImage, to rect: CGRect) -> Result? {
        let pixels = CropMath.pixelRect(rect, imageSize: CGSize(width: image.width, height: image.height))
        guard pixels.width >= 1, pixels.height >= 1, let cropped = image.cropping(to: pixels) else { return nil }
        return Result(image: cropped) { CGPoint(x: $0.x - pixels.minX, y: $0.y - pixels.minY) }
    }

    /// Quarter turn. Clockwise moves the top-left corner to the top-right.
    static func rotate(_ image: CGImage, clockwise: Bool) -> Result? {
        let width = Double(image.width), height = Double(image.height)
        // Context transforms are in bottom-left coordinates; the map is in top-left ones.
        let transform = clockwise
            ? CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
            : CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        guard let rotated = draw(image, size: CGSize(width: height, height: width), transform: transform) else {
            return nil
        }
        return Result(image: rotated) { point in
            clockwise ? CGPoint(x: height - point.y, y: point.x) : CGPoint(x: point.y, y: width - point.x)
        }
    }

    static func flip(_ image: CGImage, horizontal: Bool) -> Result? {
        let width = Double(image.width), height = Double(image.height)
        let transform = horizontal
            ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
            : CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        guard let flipped = draw(image, size: CGSize(width: width, height: height), transform: transform) else {
            return nil
        }
        return Result(image: flipped) { point in
            horizontal ? CGPoint(x: width - point.x, y: point.y) : CGPoint(x: point.x, y: height - point.y)
        }
    }

    static func resize(_ image: CGImage, to size: CGSize) -> Result? {
        let width = max(1, size.width.rounded()), height = max(1, size.height.rounded())
        let scaleX = width / Double(image.width), scaleY = height / Double(image.height)
        guard let resized = draw(image, size: CGSize(width: width, height: height),
                                 transform: CGAffineTransform(scaleX: scaleX, y: scaleY)) else { return nil }
        return Result(image: resized, scale: min(scaleX, scaleY)) { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
    }

    /// Draws `image` (at its own size) through `transform` into a new sRGB bitmap of `size`.
    static func draw(_ image: CGImage, size: CGSize, transform: CGAffineTransform) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Reads an image file; scale comes from its DPI (144 dpi → 2x), defaulting to 1.
    static func load(_ url: URL) -> (image: CGImage, scale: Double)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? Double) ?? 72
        return (image, max(1, (dpi / 72).rounded()))
    }
}
