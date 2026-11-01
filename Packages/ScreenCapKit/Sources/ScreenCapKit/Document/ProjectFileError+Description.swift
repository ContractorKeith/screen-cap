import Foundation

/// Readable messages instead of "ProjectFileError error 4" in HUDs and logs (#113).
extension ProjectFileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            "The file uses format version \(found); this version of ScreenCap reads up to \(supported)."
        case let .invalidGeometry(field): "This project’s \(field) is invalid."
        case let .missingFile(name): "\(name) is missing."
        case let .invalidLayerName(name): "“\(name)” isn't a valid layer name."
        case let .missingLayer(name): "The layer “\(name)” has no image."
        case let .imageEncodingFailed(name):
            "Couldn't write \(name). The disk may be full or the folder read-only."
        case let .imageDecodingFailed(name): "Couldn't read the image \(name)."
        }
    }
}
