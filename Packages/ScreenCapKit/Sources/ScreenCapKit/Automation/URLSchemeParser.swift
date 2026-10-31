// Automation: parses screencap:// URLs into AutomationCommand values.
// Command names and parameter keys are case-insensitive; values are case-sensitive.

import Foundation
import UniformTypeIdentifiers

/// Why a URL couldn't be turned into a command.
public enum URLSchemeParseError: Error, Equatable, Sendable {
    case wrongScheme(String)
    case unknownCommand(String)
    case missingParameter(String)
    case invalidParameter(name: String, value: String)
    case unreadableFile(path: String)
    case notAnImage(path: String)
    case unknownParameter(String)
}

extension URLSchemeParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .wrongScheme(let scheme): "Expected a screencap:// URL, got \"\(scheme):\"."
        case .unknownCommand(let name): "Unknown command \"\(name)\"."
        case .missingParameter(let name): "Missing parameter \"\(name)\"."
        case .invalidParameter(let name, let value): "Invalid value \"\(value)\" for \"\(name)\"."
        case .unreadableFile(let path): "Can't read file at \(path)."
        case .notAnImage(let path): "File at \(path) is not an image."
        case .unknownParameter(let name): "Unknown parameter \"\(name)\"."
        }
    }
}

/// Turns a `screencap://<command>?<params>` URL into an `AutomationCommand`.
public struct URLSchemeParser: Sendable {
    public typealias ParseError = URLSchemeParseError

    private let files: any FileChecker

    public init(fileChecker: any FileChecker = DiskFileChecker()) {
        self.files = fileChecker
    }

    /// Parse with the real filesystem.
    public static func parse(_ url: URL) throws -> AutomationCommand {
        try URLSchemeParser().parse(url)
    }

    /// Parse a URL, or throw a `ParseError` describing the first problem found.
    public func parse(_ url: URL) throws -> AutomationCommand {
        guard let scheme = url.scheme, scheme.lowercased() == ScreenCapKit.urlScheme else {
            throw ParseError.wrongScheme(url.scheme ?? "")
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let name = (components?.host ?? "").lowercased()
        let path = components?.path ?? ""
        guard let spec = Self.specs[name], path.isEmpty || path == "/" else {
            throw ParseError.unknownCommand((components?.host ?? "") + path)
        }
        let params = try Params(items: components?.queryItems ?? [], allowed: spec.keys)
        return try spec.build(params, self)
    }

    // MARK: - Command table

    private struct Spec: Sendable {
        let keys: Set<String>
        let build: @Sendable (Params, URLSchemeParser) throws -> AutomationCommand
    }

    private static let regionKeys: Set<String> = ["x", "y", "width", "height", "display"]

    private static let specs: [String: Spec] = [
        "all-in-one": Spec(keys: regionKeys) { params, _ in .allInOne(region: try params.region()) },
        "capture-area": Spec(keys: regionKeys.union(["action"])) { params, _ in
            .captureArea(region: try params.region(), action: try params.action())
        },
        "capture-previous-area": Spec(keys: ["action"]) { params, _ in
            .capturePreviousArea(action: try params.action())
        },
        "capture-fullscreen": Spec(keys: ["action"]) { params, _ in .captureFullscreen(action: try params.action()) },
        "capture-window": Spec(keys: ["action"]) { params, _ in .captureWindow(action: try params.action()) },
        "self-timer": Spec(keys: ["action"]) { params, _ in .selfTimer(action: try params.action()) },
        "scrolling-capture": Spec(keys: regionKeys.union(["start", "autoscroll"])) { params, _ in
            .scrollingCapture(
                region: try params.region(),
                start: try params.bool("start") ?? false,
                autoscroll: try params.bool("autoscroll") ?? false
            )
        },
        "capture-text": Spec(keys: regionKeys.union(["filepath", "linebreaks"])) { params, parser in
            try parser.captureText(params)
        },
        "open-annotate": Spec(keys: ["filepath"]) { params, parser in
            .openAnnotate(file: try parser.imageFile(params))
        },
        "pin": Spec(keys: ["filepath"]) { params, parser in .pin(file: try parser.imageFile(params)) },
        "open-from-clipboard": Spec(keys: []) { _, _ in .openFromClipboard },
        "open-history": Spec(keys: []) { _, _ in .openHistory },
        "restore-recently-closed": Spec(keys: []) { _, _ in .restoreRecentlyClosed },
        "add-quick-access-overlay": Spec(keys: ["filepath"]) { params, parser in
            guard let file = try parser.imageFile(params) else { throw ParseError.missingParameter("filepath") }
            return .addQuickAccessOverlay(file: file)
        },
        "toggle-desktop-icons": Spec(keys: []) { _, _ in .toggleDesktopIcons },
        "hide-desktop-icons": Spec(keys: []) { _, _ in .hideDesktopIcons },
        "show-desktop-icons": Spec(keys: []) { _, _ in .showDesktopIcons },
        "open-settings": Spec(keys: ["tab"]) { params, _ in
            .openSettings(tab: try params.enumValue("tab", AutomationCommand.SettingsTab.self))
        }
    ]

    // MARK: - Shared parameter rules

    private func captureText(_ params: Params) throws -> AutomationCommand {
        let lineBreaks = try params.bool("linebreaks") ?? true
        let region = try params.region()
        let file = try imageFile(params)
        switch (file, region) {
        case let (file?, nil): return .captureText(source: .file(file), lineBreaks: lineBreaks)
        case let (nil, region?): return .captureText(source: .region(region), lineBreaks: lineBreaks)
        case (nil, nil): return .captureText(source: nil, lineBreaks: lineBreaks)
        case (.some, .some):
            // filepath and a region are mutually exclusive.
            throw ParseError.invalidParameter(name: "filepath", value: params["filepath"] ?? "")
        }
    }

    /// Reads `filepath`, expands `~`, and checks it is an absolute path to a readable image.
    private func imageFile(_ params: Params) throws -> URL? {
        guard let raw = params["filepath"] else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            throw ParseError.invalidParameter(name: "filepath", value: raw)
        }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard files.isReadableFile(at: url) else { throw ParseError.unreadableFile(path: url.path) }
        guard let type = files.contentType(of: url), type.conforms(to: .image) else {
            throw ParseError.notAnImage(path: url.path)
        }
        return url
    }
}

/// Query parameters keyed by lowercased name, validated against a command's allowed keys.
private struct Params {
    private let values: [String: String]

    init(items: [URLQueryItem], allowed: Set<String>) throws {
        var values: [String: String] = [:]
        for item in items {
            let key = item.name.lowercased()
            guard allowed.contains(key) else { throw URLSchemeParseError.unknownParameter(item.name) }
            let value = item.value ?? ""
            // Empty and repeated values are always a mistake in a hand-written URL.
            guard !value.isEmpty, values[key] == nil else {
                throw URLSchemeParseError.invalidParameter(name: key, value: value)
            }
            values[key] = value
        }
        self.values = values
    }

    subscript(key: String) -> String? { values[key] }

    func action() throws -> AfterCaptureAction? {
        try enumValue("action", AfterCaptureAction.self)
    }

    func enumValue<T: RawRepresentable>(_ key: String, _ type: T.Type) throws -> T? where T.RawValue == String {
        guard let raw = values[key] else { return nil }
        guard let value = T(rawValue: raw) else { throw URLSchemeParseError.invalidParameter(name: key, value: raw) }
        return value
    }

    func bool(_ key: String) throws -> Bool? {
        guard let raw = values[key] else { return nil }
        switch raw {
        case "true", "1": return true
        case "false", "0": return false
        default: throw URLSchemeParseError.invalidParameter(name: key, value: raw)
        }
    }

    /// All of x, y, width, height or none of them. `display` defaults to 1 and needs a region.
    func region() throws -> Region? {
        let rectKeys = ["x", "y", "width", "height"]
        let present = rectKeys.filter { values[$0] != nil }
        if present.isEmpty {
            if values["display"] != nil { throw URLSchemeParseError.missingParameter("x") }
            return nil
        }
        if let missing = rectKeys.first(where: { values[$0] == nil }) {
            throw URLSchemeParseError.missingParameter(missing)
        }
        let x = try number("x", minimum: 0, inclusive: true)
        let y = try number("y", minimum: 0, inclusive: true)
        // Under a point there's nothing to capture; say so here rather than as "off screen" later.
        let width = try number("width", minimum: 1, inclusive: true)
        let height = try number("height", minimum: 1, inclusive: true)
        var display = 1
        if let raw = values["display"] {
            guard Self.decimal(raw) != nil, !raw.contains("."), let value = Int(raw), value >= 1 else {
                throw URLSchemeParseError.invalidParameter(name: "display", value: raw)
            }
            display = value
        }
        return Region(x: x, y: y, width: width, height: height, display: display)
    }

    private func number(_ key: String, minimum: Double, inclusive: Bool) throws -> Double {
        let raw = values[key] ?? ""
        guard let value = Self.decimal(raw), inclusive ? value >= minimum : value > minimum else {
            throw URLSchemeParseError.invalidParameter(name: key, value: raw)
        }
        return value
    }

    /// Plain decimals only (`12`, `12.5`, `.5`): no sign, hex, exponent, `_`, `inf`/`nan` or
    /// whitespace, all of which `Double(_:)` accepts (#102).
    static func decimal(_ raw: String) -> Double? {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.contains(where: { !$0.isEmpty }),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        return Double(raw).flatMap { $0.isFinite ? $0 : nil }
    }
}
