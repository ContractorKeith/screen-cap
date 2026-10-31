import AppKit
import ScreenCapKit

/// Saves and copies captures using the current settings. Encoding runs off the main actor.
///
/// The output scale (Retina 2x / 1x) applies here only: files and the clipboard. History, the
/// editor, Quick Access and pins keep the full-resolution capture.
@MainActor
final class CaptureOutput {
    private let settings: AppSettings
    /// Saves run one at a time, in the order they were asked for.
    private var lastSave: Task<Void, Never>?
    /// Where copy-as-file writes; its files are removed when no longer needed (#114).
    let temp: TempFiles

    init(settings: AppSettings, temp: TempFiles? = nil) {
        self.settings = settings
        self.temp = temp ?? .shared
    }

    /// Where `save` writes, for messages.
    var saveFolder: URL { settings.saveOptions.folder }

    /// Writes the capture into the save folder with the filename template; returns the file URL.
    ///
    /// The name is claimed with an exclusive create before encoding, and saves are serialized,
    /// so two saves in the same second get two files.
    func save(_ result: CaptureResult) async throws -> URL {
        let previous = lastSave
        let task = Task { @MainActor [settings] in
            await previous?.value
            let options = settings.saveOptions
            try FileManager.default.createDirectory(at: options.folder, withIntermediateDirectories: true)
            return try await Self.write(result, options: options, in: options.folder)
        }
        lastSave = Task { _ = await task.result }
        return try await task.value
    }

    /// Puts the capture on the pasteboard as PNG data, or as a file per `CopyMode`.
    func copy(_ result: CaptureResult) async throws {
        let pasteboard = NSPasteboard.general
        switch settings.copyMode {
        case .image:
            let image = try OutputScaler.scaled(result.image, to: settings.retinaScale)
            let data = try await Self.encode(image, as: .png)
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
        case .file:
            let url = try await writeTemporaryFile(result)
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        }
    }

    /// Copy-as-file needs a real file even when the user doesn't save. It's tracked as the
    /// clipboard file: the next copy-as-file replaces it, and deleting the capture's history
    /// record or quitting removes it (#114).
    func writeTemporaryFile(_ result: CaptureResult) async throws -> URL {
        let folder = try temp.makeFolder()
        do {
            let url = try await Self.write(result, options: settings.saveOptions, in: folder)
            temp.release(.clipboard)
            temp.track(folder, owner: .clipboard, record: result.historyRecordID)
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Reserves a name, scales, encodes and writes over the placeholder; removes it on failure.
    private static func write(_ result: CaptureResult, options: SaveOptions, in folder: URL)
        async throws -> URL {
        let url = try options.template().reserveUniqueURL(in: folder, context: result.context)
        do {
            let image = try OutputScaler.scaled(result.image, to: options.scale)
            let data = try await encode(image, as: ExportFormat(options.format, quality: options.jpegQuality))
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func encode(_ image: CapturedImage, as format: ExportFormat) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Exporter(image: image.cgImage, format: format, scale: Double(image.scale)).data()
        }.value
    }
}

/// Output-scale conversion: 2x keeps Retina pixels, 1x downsamples to one pixel per point.
enum OutputScaler {
    struct ScalingFailed: LocalizedError {
        var errorDescription: String? { "Couldn't scale the image to 1x." }
    }

    /// Returns `image` at no more than `scale` pixels per point. Never upsamples.
    /// Throws rather than silently keeping the full-size image.
    static func scaled(_ image: CapturedImage, to scale: RetinaScale) throws -> CapturedImage {
        let target = scale.factor
        guard image.scale > target else { return image }
        let width = max(Int((CGFloat(image.cgImage.width) * target / image.scale).rounded()), 1)
        let height = max(Int((CGFloat(image.cgImage.height) * target / image.scale).rounded()), 1)
        guard let space = image.cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw ScalingFailed() }
        context.interpolationQuality = .high
        context.draw(image.cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw ScalingFailed() }
        return CapturedImage(cgImage: scaled, scale: target, pointRect: image.pointRect, displayID: image.displayID)
    }
}
