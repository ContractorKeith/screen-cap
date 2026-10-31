import Foundation

/// Save settings snapshot handed to the exporter, so it never touches `AppSettings`.
public struct SaveOptions: Equatable, Sendable {
    public var format: ImageFormat
    public var scale: RetinaScale
    /// Always within 0.0...1.0.
    public var jpegQuality: Double
    public var folder: URL
    public var filenameTemplate: String

    public init(
        format: ImageFormat,
        scale: RetinaScale,
        jpegQuality: Double,
        folder: URL,
        filenameTemplate: String
    ) {
        self.format = format
        self.scale = scale
        self.jpegQuality = min(max(jpegQuality, 0), 1)
        self.folder = folder
        self.filenameTemplate = filenameTemplate
    }

    /// Filename renderer for these options. Pass a clock and time zone in tests.
    public func template(
        clock: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) -> FilenameTemplate {
        FilenameTemplate(filenameTemplate, format: format, clock: clock, timeZone: timeZone)
    }
}
