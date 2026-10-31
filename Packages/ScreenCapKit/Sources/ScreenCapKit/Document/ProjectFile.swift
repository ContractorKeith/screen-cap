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
    /// - Parameter preview: Flattened render for Quick Look. When nil, a downscaled base image is used.
    public static func write(
        _ document: Document,
        baseImage: CGImage,
        layers: [String: CGImage] = [:],
        preview: CGImage? = nil,
        to url: URL
    ) throws {
        for name in layers.keys where !isValidLayerName(name) { throw ProjectFileError.invalidLayerName(name) }
        for name in document.referencedLayerNames where layers[name] == nil {
            throw ProjectFileError.missingLayer(name)
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
