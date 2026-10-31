import CoreGraphics
import Foundation

/// The editable model behind one screenshot: base image, optional background and annotations.
/// Everything is in image pixels (PLAN §4). Serialized as `document.json` (docs/file-format.md).
public struct Document: Sendable, Equatable, Codable {
    /// The newest `schemaVersion` this build can read and the one it writes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var baseImage: BaseImage
    /// Size of the exported image in pixels. Equals the base image unless a background adds padding.
    public var canvasSize: CGSize
    public var background: Background?
    /// Creation order. Draw order is `zIndex`; see `drawOrder`.
    public var annotations: [Annotation]

    public init(
        baseImage: BaseImage,
        canvasSize: CGSize? = nil,
        background: Background? = nil,
        annotations: [Annotation] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.baseImage = baseImage
        self.canvasSize = canvasSize ?? baseImage.pixelSize
        self.background = background
        self.annotations = annotations
    }

    /// Annotations sorted for drawing: by `zIndex`, ties broken by creation order.
    public var drawOrder: [Annotation] {
        annotations.enumerated()
            .sorted { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }
            .map(\.element)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, baseImage, canvasSize, background, annotations
    }

    /// Checks `schemaVersion` before anything else so a newer file fails with a clear error
    /// instead of tripping over an annotation kind this build doesn't know.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard (1...Self.currentSchemaVersion).contains(version) else {
            throw ProjectFileError.unsupportedSchemaVersion(found: version, supported: Self.currentSchemaVersion)
        }
        schemaVersion = version
        baseImage = try container.decode(BaseImage.self, forKey: .baseImage)
        canvasSize = try container.decode(CGSize.self, forKey: .canvasSize)
        background = try container.decodeIfPresent(Background.self, forKey: .background)
        annotations = try container.decode([Annotation].self, forKey: .annotations)
    }
}

extension Document {
    /// The captured image: pixel dimensions plus the display scale it was captured at.
    public struct BaseImage: Sendable, Equatable, Codable {
        public var pixelWidth: Int
        public var pixelHeight: Int
        /// Backing scale of the source display (2 for Retina, 1 otherwise).
        public var scale: Double

        public init(pixelWidth: Int, pixelHeight: Int, scale: Double) {
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.scale = scale
        }

        public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
    }

    public struct Shadow: Sendable, Equatable, Codable {
        public var color: RGBAColor
        public var radius: Double
        public var offset: CGSize

        public init(color: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.4),
                    radius: Double = 8, offset: CGSize = CGSize(width: 0, height: 4)) {
            self.color = color
            self.radius = radius
            self.offset = offset
        }
    }

    /// Backdrop drawn behind the base image (PLAN §3.3 Background tool).
    public struct Background: Sendable, Equatable, Codable {
        public var fill: BackgroundFill
        /// Space between canvas edge and base image, in pixels.
        public var padding: Double
        /// Corner radius applied to the base image, in pixels.
        public var cornerRadius: Double
        /// Shadow under the base image.
        public var shadow: Shadow?
        public var alignment: Alignment

        public init(fill: BackgroundFill, padding: Double = 64, cornerRadius: Double = 12,
                    shadow: Shadow? = Shadow(), alignment: Alignment = .center) {
            self.fill = fill
            self.padding = padding
            self.cornerRadius = cornerRadius
            self.shadow = shadow
            self.alignment = alignment
        }
    }

    public enum BackgroundFill: Sendable, Equatable, Codable {
        case solid(color: RGBAColor)
        /// `angle` in degrees, 0 = left to right, 90 = bottom to top.
        case linearGradient(stops: [GradientStop], angle: Double)
        /// One of the app's bundled backgrounds, by resource name.
        case bundled(name: String)
        /// A user image stored as `layers/<layerName>.png`.
        case customImage(layerName: String)
    }

    public struct GradientStop: Sendable, Equatable, Codable {
        public var color: RGBAColor
        /// Position along the gradient, 0...1.
        public var location: Double

        public init(color: RGBAColor, location: Double) {
            self.color = color
            self.location = location
        }
    }

    /// Where the base image sits inside the padded canvas.
    public enum Alignment: String, Sendable, Equatable, Codable, CaseIterable {
        case center, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
    }

    /// Every layer file the document references: image layers and a custom background image.
    public var referencedLayerNames: Set<String> {
        var names = Set<String>()
        for annotation in annotations {
            if case let .imageLayer(layerName, _) = annotation.kind { names.insert(layerName) }
        }
        if case let .customImage(layerName) = background?.fill { names.insert(layerName) }
        return names
    }
}
