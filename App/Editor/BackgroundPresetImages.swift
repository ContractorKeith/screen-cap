import CoreGraphics
import Foundation
import ImageIO
import ScreenCapKit

/// Preset bitmaps live outside preferences, keyed only by UUID (never by a layer or user name).
struct BackgroundPresetImages {
    static let maxBytes = 20 * 1_024 * 1_024
    static let maxPixels = 40_000_000
    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ScreenCap/BackgroundPresets", isDirectory: true)) {
        self.directory = directory
    }

    func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).png") }

    func save(_ image: CGImage, for id: UUID) throws {
        guard image.width <= Self.maxPixels / max(image.height, 1) else { throw PresetImageError.tooLarge }
        let data = try Exporter(image: image, format: .png).data()
        guard data.count <= Self.maxBytes else { throw PresetImageError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: id), options: .atomic)
    }

    func load(for id: UUID) throws -> CGImage {
        let url = url(for: id)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maxBytes,
              let data = try? Data(contentsOf: url), data.count <= Self.maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= Self.maxPixels / height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PresetImageError.unavailable
        }
        return image
    }

    func remove(for id: UUID) { try? FileManager.default.removeItem(at: url(for: id)) }
}

enum PresetImageError: LocalizedError {
    case unavailable, tooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "This preset’s image is unavailable; choose the image again and save a new preset."
        case .tooLarge:
            "Preset images must be at most 40 megapixels and 20 MB as PNG."
        }
    }
}
