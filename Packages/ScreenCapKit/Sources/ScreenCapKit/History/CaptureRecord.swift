import Foundation

/// What produced a capture. A string-backed struct rather than an enum so new kinds
/// (screen recordings in phase 2, PLAN §10) decode in older builds instead of failing.
public struct CaptureKind: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let area = CaptureKind(rawValue: "area")
    public static let window = CaptureKind(rawValue: "window")
    public static let fullscreen = CaptureKind(rawValue: "fullscreen")
    public static let scrolling = CaptureKind(rawValue: "scrolling")
    public static let text = CaptureKind(rawValue: "text")
    public static let pinnedImport = CaptureKind(rawValue: "pinned-import")
    /// Used when a record is rebuilt from a file on disk with no index entry.
    public static let unknown = CaptureKind(rawValue: "unknown")

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Optional facts about a capture supplied by the caller when it is added to history.
public struct CaptureMetadata: Sendable, Equatable {
    /// Backing scale of the display the capture came from (2 on Retina).
    public var scale: Double
    public var ocrText: String?
    public var appName: String?
    public var windowTitle: String?

    public init(scale: Double = 1, ocrText: String? = nil, appName: String? = nil, windowTitle: String? = nil) {
        self.scale = scale
        self.ocrText = ocrText
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

/// One entry in capture history (PLAN §3.4). Media-type-agnostic: `kind` says what it is.
public struct CaptureRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: CaptureKind
    public var createdAt: Date
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var scale: Double
    /// The stored image, or a `.screencap` project package.
    public var fileURL: URL
    public var thumbnailURL: URL
    public var ocrText: String?
    public var appName: String?
    public var windowTitle: String?
    /// When the Quick Access overlay was dismissed; nil while open or once restored (PLAN §3.2).
    public var closedAt: Date?
    /// True on a record returned from `HistoryStore.delete(id:)`; its files are gone.
    public var isDeleted: Bool

    public init(
        id: UUID = UUID(),
        kind: CaptureKind,
        createdAt: Date,
        pixelWidth: Int,
        pixelHeight: Int,
        scale: Double = 1,
        fileURL: URL,
        thumbnailURL: URL,
        ocrText: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        closedAt: Date? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.ocrText = ocrText
        self.appName = appName
        self.windowTitle = windowTitle
        self.closedAt = closedAt
        self.isDeleted = isDeleted
    }

    /// Case- and diacritic-insensitive match against OCR text, app name and window title.
    func matches(query: String) -> Bool {
        [ocrText, appName, windowTitle].contains { field in
            guard let field else { return false }
            return field.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
