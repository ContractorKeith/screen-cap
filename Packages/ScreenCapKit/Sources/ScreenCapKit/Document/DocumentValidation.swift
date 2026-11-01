import CoreGraphics
import Foundation

/// Limits shared by file decoding and rendering, before any floating-point to integer conversion.
enum DocumentLimits {
    static let maximumDimension = 65_536.0
    static let maximumPixels = 100_000_000.0

    static func length(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= maximumDimension
    }

    static func coordinate(_ value: Double) -> Bool {
        value.isFinite && abs(value) <= maximumDimension
    }

    static func scale(_ value: Double) -> Bool {
        value.isFinite && ((1 / maximumDimension)...16).contains(value)
    }

    static func size(_ size: CGSize) -> Bool {
        length(size.width) && length(size.height) && size.width > 0 && size.height > 0
            && size.width * size.height <= maximumPixels
    }

    static func point(_ point: CGPoint) -> Bool { coordinate(point.x) && coordinate(point.y) }

    static func rect(_ rect: CGRect) -> Bool {
        point(rect.origin) && length(rect.size.width) && length(rect.size.height)
    }

    static func shadow(_ shadow: Document.Shadow?) -> Bool {
        guard let shadow else { return true }
        return length(shadow.radius) && coordinate(shadow.offset.width) && coordinate(shadow.offset.height)
    }
}

extension Document {
    /// Also used for mutable, in-memory documents at the rendering boundary.
    func validateGeometry() throws {
        guard DocumentLimits.size(canvasSize) else { throw ProjectFileError.invalidGeometry("canvas size") }
        guard DocumentLimits.size(baseImage.pixelSize), DocumentLimits.scale(baseImage.scale) else {
            throw ProjectFileError.invalidGeometry("base image size or scale")
        }
        if let background {
            let pad = background.resolvedPadding
            guard [background.padding, background.cornerRadius, pad.top, pad.left, pad.bottom, pad.right]
                .allSatisfy(DocumentLimits.length), DocumentLimits.shadow(background.shadow),
                  DocumentLimits.size(CGSize(width: baseImage.pixelSize.width + pad.left + pad.right,
                                             height: baseImage.pixelSize.height + pad.top + pad.bottom)) else {
                throw ProjectFileError.invalidGeometry("background geometry")
            }
        }
        guard annotations.allSatisfy({ annotation in
            DocumentLimits.length(annotation.style.strokeWidth) && DocumentLimits.shadow(annotation.style.shadow)
                && annotation.kind.hasValidGeometry
        }) else { throw ProjectFileError.invalidGeometry("annotation geometry") }
    }
}

private extension Annotation.Kind {
    var hasValidGeometry: Bool {
        switch self {
        case let .arrow(start, end, style):
            var points = [start, end]
            if case let .curved(control) = style { points.append(control) }
            return points.allSatisfy(DocumentLimits.point)
        case let .line(start, end):
            return DocumentLimits.point(start) && DocumentLimits.point(end)
        case let .rectangle(rect, _, radius), let .blur(rect, _, radius):
            return DocumentLimits.rect(rect) && DocumentLimits.length(radius)
        case let .ellipse(rect), let .imageLayer(_, rect):
            return DocumentLimits.rect(rect)
        case let .text(_, _, fontSize, rect):
            return DocumentLimits.rect(rect) && DocumentLimits.length(fontSize) && fontSize > 0
        case let .counter(_, center, radius):
            return DocumentLimits.point(center) && DocumentLimits.length(radius) && radius > 0
        case let .path(points, _):
            return points.allSatisfy(DocumentLimits.point)
        case let .highlight(region, _):
            switch region {
            case let .rect(rect): return DocumentLimits.rect(rect)
            case let .path(points): return points.allSatisfy(DocumentLimits.point)
            }
        case let .pixelate(rect, blockSize, _):
            return DocumentLimits.rect(rect) && blockSize > 0 && Double(blockSize) <= DocumentLimits.maximumDimension
        case let .spotlight(shapes):
            return shapes.allSatisfy { shape in
                switch shape {
                case let .rect(rect), let .ellipse(rect): return DocumentLimits.rect(rect)
                }
            }
        }
    }
}
