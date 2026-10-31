import Foundation

/// Renders a filename template such as `ScreenCap {date} at {time}` into a safe, unique filename.
///
/// Tokens: `{date}` yyyy-MM-dd, `{time}` HH.mm.ss, `{datetime}` both, `{app}` frontmost app,
/// `{window}` window title, `{counter}` first number that doesn't collide, `{kind}` capture kind.
/// Unknown tokens are left as typed.
public struct FilenameTemplate: Sendable {
    /// Capture kind for the `{kind}` token.
    public enum Kind: String, Sendable, CaseIterable {
        case area, window, fullscreen, scrolling
    }

    /// Per-capture values for the app, window and kind tokens. Missing values render empty.
    public struct Context: Equatable, Sendable {
        public var app: String?
        public var window: String?
        public var kind: Kind?

        public init(app: String? = nil, window: String? = nil, kind: Kind? = nil) {
            self.app = app
            self.window = window
            self.kind = kind
        }
    }

    /// Max filename length in characters, excluding the extension.
    public static let maxLength = 200
    /// Used when the template renders to nothing.
    public static let fallbackName = "ScreenCap"
    /// Characters macOS (or common sync targets like SMB and FAT) reject in filenames.
    static let illegalCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        .union(.controlCharacters)
        .union(.newlines)
    /// Stop probing for a free name after this many attempts.
    static let maxAttempts = 10_000

    public let template: String
    public let format: ImageFormat
    private let clock: @Sendable () -> Date
    private let timeZone: TimeZone

    public init(
        _ template: String,
        format: ImageFormat,
        clock: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        self.template = template
        self.format = format
        self.clock = clock
        self.timeZone = timeZone
    }

    /// Filename with extension, ignoring collisions. `{counter}` renders as `counter`.
    public func filename(context: Context = Context(), counter: Int = 1) -> String {
        filename(stem: render(context: context, date: clock(), counter: counter), suffix: "")
    }

    /// First URL in `folder` that `fileExists` reports free. With `{counter}` in the template the
    /// counter increments; otherwise ` 2`, ` 3`, ... is appended before the extension.
    public func uniqueURL(
        in folder: URL,
        context: Context = Context(),
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let date = clock()
        let usesCounter = template.contains("{counter}")
        let baseStem = render(context: context, date: date, counter: 1)

        for attempt in 1...Self.maxAttempts {
            let name = usesCounter
                ? filename(stem: render(context: context, date: date, counter: attempt), suffix: "")
                : filename(stem: baseStem, suffix: attempt == 1 ? "" : " \(attempt)")
            let url = folder.appendingPathComponent(name, isDirectory: false)
            if !fileExists(url) { return url }
        }
        // Pathological folder: fall back to a name that can't collide.
        return folder.appendingPathComponent(filename(stem: baseStem, suffix: " \(UUID().uuidString)"))
    }

    // MARK: - Rendering

    /// Substitutes tokens and sanitizes; returns the stem without extension or truncation.
    func render(context: Context, date: Date, counter: Int) -> String {
        let dateText = stamp(date, "yyyy-MM-dd")
        let timeText = stamp(date, "HH.mm.ss")
        let tokens: [String: String] = [
            "{date}": dateText,
            "{time}": timeText,
            "{datetime}": "\(dateText) \(timeText)",
            "{app}": context.app ?? "",
            "{window}": context.window ?? "",
            "{counter}": String(counter),
            "{kind}": context.kind?.rawValue ?? ""
        ]
        // Single pass, so a token-like app or window name is never expanded again.
        var result = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result += rest[..<open]
            if let value = tokens[String(rest[open...close])] {
                result += value
                rest = rest[rest.index(after: close)...]
            } else {
                result += "{"
                rest = rest[rest.index(after: open)...]
            }
        }
        result += rest
        return Self.sanitize(result)
    }

    /// Turns tabs and newlines into spaces, strips illegal characters, collapses whitespace,
    /// and drops leading dots (hidden files).
    static func sanitize(_ name: String) -> String {
        let scalars = name.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return " " }
            return illegalCharacters.contains(scalar) ? nil : scalar
        }
        let stripped = String(String.UnicodeScalarView(scalars))
        var cleaned = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }
        return cleaned
    }

    /// Truncates the stem so stem + suffix fits `maxLength`, then adds the extension.
    private func filename(stem: String, suffix: String) -> String {
        let base = stem.isEmpty ? Self.fallbackName : stem
        let room = max(Self.maxLength - suffix.count, 1)
        let truncated = String(base.prefix(room)).trimmingCharacters(in: .whitespaces)
        return "\(truncated)\(suffix).\(format.fileExtension)"
    }

    private func stamp(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
