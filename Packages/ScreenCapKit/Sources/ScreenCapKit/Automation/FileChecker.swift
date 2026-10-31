// Automation: filesystem seam for validating `filepath` parameters. Tests inject a stub.

import Foundation
import UniformTypeIdentifiers

/// Answers the two questions the parser asks about a `filepath`.
public protocol FileChecker: Sendable {
    /// True if `url` is an existing regular file the app can read.
    func isReadableFile(at url: URL) -> Bool
    /// The file's content type, or nil if it can't be determined.
    func contentType(of url: URL) -> UTType?
}

/// Real filesystem implementation.
public struct DiskFileChecker: FileChecker {
    public init() {}

    public func isReadableFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return manager.isReadableFile(atPath: url.path)
    }

    public func contentType(of url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        return UTType(filenameExtension: url.pathExtension)
    }
}
