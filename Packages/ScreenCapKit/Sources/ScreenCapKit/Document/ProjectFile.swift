import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Errors from reading or writing a `.screencap` package.
public enum ProjectFileError: Error, Equatable {
    /// `document.json` was written by a newer (or invalid) schema this build can't read.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// A required file is missing from the package (path relative to the package root).
    case missingFile(String)
    /// A layer name is empty or contains path characters.
    case invalidLayerName(String)
    /// The document references a layer with no image.
    case missingLayer(String)
    case imageEncodingFailed(String)
    case imageDecodingFailed(String)
    case invalidGeometry(String)
}

/// Contents of a `.screencap` package once read.
public struct ProjectContents: Sendable {
    public var document: Document
    public var baseImage: CGImage
    /// Layer images keyed by layer name (file name without `.png`).
    public var layers: [String: CGImage]
    public var preview: CGImage?
}

/// Reads and writes `.screencap` document packages (PLAN §5.3, docs/file-format.md).
public enum ProjectFile {
    public static let fileExtension = "screencap"
    public static let documentFileName = "document.json"
    public static let baseFileName = "base.png"
    public static let previewFileName = "preview.png"
    public static let layersDirectoryName = "layers"
    /// Longest edge of the generated preview, in pixels.
    public static let previewMaxPixels = 512

    /// Writes the package atomically: everything goes into a temporary directory on the same
    /// volume, which then replaces (or becomes) `url`. A failed write leaves `url` untouched.
    /// - Parameters:
    ///   - preview: Flattened render for Quick Look. When nil, a downscaled base image is used.
    ///   - bakeRedactions: Flatten blur, pixelate and objects marked `redaction == true` into
    ///     `base.png` first (see `bakingRedactions`),
    ///     so the package never holds the pixels they hide. On by default; only tests turn it off.
    public static func write(
        _ document: Document,
        baseImage: CGImage,
        layers: [String: CGImage] = [:],
        preview: CGImage? = nil,
        bakeRedactions: Bool = true,
        to url: URL
    ) throws {
        for name in layers.keys where !isValidLayerName(name) { throw ProjectFileError.invalidLayerName(name) }
        for name in document.referencedLayerNames where layers[name] == nil {
            throw ProjectFileError.missingLayer(name)
        }
        var document = document
        var baseImage = baseImage
        var layers = layers
        if bakeRedactions {
            let baked = try bakingRedactions(document, baseImage: baseImage, layers: layers)
            document = baked.document
            baseImage = baked.baseImage
            layers = baked.layers
        }

        let fileManager = FileManager.default
        let staging = try fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true
        )
        defer { try? fileManager.removeItem(at: staging) }
        let package = staging.appendingPathComponent(url.lastPathComponent, isDirectory: true)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(document).write(to: package.appendingPathComponent(documentFileName))
        try writePNG(baseImage, to: package.appendingPathComponent(baseFileName))
        try writePNG(preview ?? downscaled(baseImage, maxPixels: previewMaxPixels),
                     to: package.appendingPathComponent(previewFileName))
        if !layers.isEmpty {
            let layersURL = package.appendingPathComponent(layersDirectoryName, isDirectory: true)
            try fileManager.createDirectory(at: layersURL, withIntermediateDirectories: true)
            for (name, image) in layers {
                try writePNG(image, to: layersURL.appendingPathComponent("\(name).png"))
            }
        }

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: package)
        } else {
            try fileManager.moveItem(at: package, to: url)
        }
    }

    /// Reads a package. Throws `ProjectFileError.unsupportedSchemaVersion` for newer files.
    public static func read(from url: URL) throws -> ProjectContents {
        let data: Data
        do {
            data = try Data(contentsOf: url.appendingPathComponent(documentFileName))
        } catch {
            throw ProjectFileError.missingFile(documentFileName)
        }
        let document = try decodeDocument(data)
        let base = try readPNG(url.appendingPathComponent(baseFileName), name: baseFileName)

        var layers: [String: CGImage] = [:]
        let layersURL = url.appendingPathComponent(layersDirectoryName, isDirectory: true)
        let layerFiles = (try? FileManager.default.contentsOfDirectory(at: layersURL, includingPropertiesForKeys: nil))
            ?? []
        for file in layerFiles where file.pathExtension.lowercased() == "png" {
            let name = file.deletingPathExtension().lastPathComponent
            layers[name] = try readPNG(file, name: "\(layersDirectoryName)/\(file.lastPathComponent)")
        }
        for name in document.referencedLayerNames where layers[name] == nil {
            throw ProjectFileError.missingLayer(name)
        }

        let previewURL = url.appendingPathComponent(previewFileName)
        let preview = try? readPNG(previewURL, name: previewFileName)
        return ProjectContents(document: document, baseImage: base, layers: layers, preview: preview)
    }

    // MARK: - Redaction baking

    /// True if `document` has a blur, pixelate or object marked as a redaction that saving will
    /// bake into `base.png`. Automatic flags (`redaction == nil`) don't count; resolve them first
    /// with `Document.resolvingRedactions(textLines:)`.
    public static func containsRedactions(_ document: Document) -> Bool {
        document.annotations.contains(where: \.isBakedRedaction)
    }

    /// Flattens every blur, pixelate and object marked as a redaction into the base image,
    /// together with any object drawn beneath one and overlapping it (directly or through another
    /// baked object), so neither
    /// the hidden pixels nor a hidden object's data survive in the package. Objects above the
    /// redactions stay editable. Layers no longer referenced are dropped.
    ///
    /// Trade-off: baked objects can't be moved or removed after the project is reopened, and
    /// parts of them outside the base image (over background padding) are clipped.
    public static func bakingRedactions(
        _ document: Document,
        baseImage: CGImage,
        layers: [String: CGImage],
        renderer: Renderer = Renderer()
    ) throws -> ProjectContents {
        guard containsRedactions(document) else {
            return ProjectContents(document: document, baseImage: baseImage, layers: layers, preview: nil)
        }

        // Walk top to bottom, growing the covered region from each redaction downward.
        var covered: [CGRect] = []
        var baked = Set<UUID>()
        for annotation in document.drawOrder.reversed() {
            let reach = annotation.paintedBounds
            if annotation.isBakedRedaction || covered.contains(where: { $0.intersects(reach) }) {
                baked.insert(annotation.id)
                covered.append(reach)
            }
        }

        var flattened = document
        flattened.background = nil
        flattened.canvasSize = document.baseImage.pixelSize
        flattened.annotations = document.annotations.filter { baked.contains($0.id) }
        let image = try renderer.image(for: flattened, baseImage: baseImage, layers: layers,
                                       options: RenderOptions(scale: 1, includeBackground: false))

        var remaining = document
        remaining.annotations.removeAll { baked.contains($0.id) }
        let names = remaining.referencedLayerNames
        return ProjectContents(document: remaining, baseImage: image, layers: layers.filter { names.contains($0.key) },
                               preview: nil)
    }

    /// Decodes `document.json`, rejecting schema versions newer than `Document.currentSchemaVersion`.
    public static func decodeDocument(_ data: Data) throws -> Document {
        try JSONDecoder().decode(Document.self, from: data)
    }

    /// Layer names become file names, so keep them to one safe path component.
    public static func isValidLayerName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":")
    }

    // MARK: - PNG helpers

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw ProjectFileError.imageEncodingFailed(url.lastPathComponent) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ProjectFileError.imageEncodingFailed(url.lastPathComponent)
        }
    }

    static func readPNG(_ url: URL, name: String) throws -> CGImage {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProjectFileError.missingFile(name) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ProjectFileError.imageDecodingFailed(name) }
        return image
    }

    /// Returns `image` scaled so its longest edge is at most `maxPixels`.
    static func downscaled(_ image: CGImage, maxPixels: Int) throws -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixels else { return image }
        let factor = Double(maxPixels) / Double(longest)
        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ProjectFileError.imageEncodingFailed(previewFileName) }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw ProjectFileError.imageEncodingFailed(previewFileName) }
        return scaled
    }
}

private extension Annotation {
    var isBakedRedaction: Bool {
        switch kind {
        case .blur, .pixelate: true
        default: redaction == true
        }
    }

    /// Geometry bounds grown by stroke and shadow, roughly what the object paints.
    var paintedBounds: CGRect {
        let bounds = kind.bounds
        guard !bounds.isNull else { return bounds }
        var grow = style.strokeWidth + 2
        if let shadow = style.shadow {
            grow += shadow.radius * 2 + max(abs(shadow.offset.width), abs(shadow.offset.height))
        }
        return bounds.insetBy(dx: -grow, dy: -grow)
    }
}
