import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An export file format. Lossy formats carry their quality, 0...1.
public enum ExportFormat: Sendable, Equatable {
    case png
    case jpeg(quality: Double)
    case heic(quality: Double)
    case tiff
    /// Single-page PDF with the image as the page.
    case pdf

    /// Maps a saved setting to an export format.
    public init(_ format: ImageFormat, quality: Double) {
        switch format {
        case .png: self = .png
        case .jpeg: self = .jpeg(quality: quality)
        case .heic: self = .heic(quality: quality)
        case .tiff: self = .tiff
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .tiff: "tiff"
        case .pdf: "pdf"
        }
    }

    var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .pdf: .pdf
        }
    }
}

public enum ExportError: Error, Equatable {
    case invalidScale(Double)
    case encoderUnavailable(String)
    case encodingFailed(String)
}

/// Encodes a rendered image with ImageIO (or Core Graphics for PDF).
///
/// `scale` is the image's pixels per point. It sets the DPI metadata (72 × scale, so a 2x
/// export opens at its point size) and the PDF page size (pixels ÷ scale points).
public struct Exporter {
    public var image: CGImage
    public var format: ExportFormat
    public var scale: Double

    public init(image: CGImage, format: ExportFormat, scale: Double = 1) {
        self.image = image
        self.format = format
        self.scale = scale
    }

    /// The encoded file contents.
    public func data() throws -> Data {
        guard scale > 0, scale.isFinite else { throw ExportError.invalidScale(scale) }
        if format == .pdf { return try pdfData() }

        let data = NSMutableData()
        let type = format.type.identifier
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
            throw ExportError.encoderUnavailable(type)
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * scale,
            kCGImagePropertyDPIHeight: 72 * scale
        ]
        switch format {
        case let .jpeg(quality), let .heic(quality):
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1)
        case .png, .tiff, .pdf:
            break
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed(type) }
        return data as Data
    }

    /// Writes `data()` to `url` atomically.
    public func write(to url: URL) throws {
        try data().write(to: url, options: .atomic)
    }

    private func pdfData() throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: Double(image.width) / scale, height: Double(image.height) / scale)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.encoderUnavailable(UTType.pdf.identifier)
        }
        context.beginPDFPage(nil)
        context.interpolationQuality = .high
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
