import AppKit
import ScreenCapKit

/// Saves and copies captures using the current settings. Encoding runs off the main actor.
@MainActor
final class CaptureOutput {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Writes the capture into the save folder with the filename template; returns the file URL.
    func save(_ result: CaptureResult) async throws -> URL {
        let options = settings.saveOptions
        try FileManager.default.createDirectory(at: options.folder, withIntermediateDirectories: true)
        let url = options.template().uniqueURL(in: options.folder, context: result.context)
        let data = try await Self.encode(result.image, as: ExportFormat(options.format, quality: options.jpegQuality))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Puts the capture on the pasteboard as PNG data, or as a file per `CopyMode`.
    func copy(_ result: CaptureResult) async throws {
        let pasteboard = NSPasteboard.general
        switch settings.copyMode {
        case .image:
            let data = try await Self.encode(result.image, as: .png)
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
        case .file:
            let url = try await writeTemporaryFile(result)
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        }
    }

    /// Copy-as-file needs a real file even when the user doesn't save; it goes to a temp folder.
    private func writeTemporaryFile(_ result: CaptureResult) async throws -> URL {
        let options = settings.saveOptions
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenCap", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = options.template().uniqueURL(in: folder, context: result.context)
        let data = try await Self.encode(result.image, as: ExportFormat(options.format, quality: options.jpegQuality))
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func encode(_ image: CapturedImage, as format: ExportFormat) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Exporter(image: image.cgImage, format: format, scale: Double(image.scale)).data()
        }.value
    }
}

/// Output-scale conversion: 2x keeps Retina pixels, 1x downsamples to one pixel per point.
enum OutputScaler {
    /// Returns `image` at no more than `scale` pixels per point. Never upsamples.
    static func scaled(_ image: CapturedImage, to scale: RetinaScale) -> CapturedImage {
        let target = scale.factor
        guard image.scale > target else { return image }
        let width = max(Int((CGFloat(image.cgImage.width) * target / image.scale).rounded()), 1)
        let height = max(Int((CGFloat(image.cgImage.height) * target / image.scale).rounded()), 1)
        let space = image.cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image.cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return image }
        return CapturedImage(cgImage: scaled, scale: target, pointRect: image.pointRect, displayID: image.displayID)
    }
}
