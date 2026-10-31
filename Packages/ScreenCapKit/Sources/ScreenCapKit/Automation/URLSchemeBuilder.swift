// Automation: renders an AutomationCommand back to a screencap:// URL.
// Output always parses back to the same command (see the round-trip tests).

import Foundation

public enum URLSchemeBuilder {
    /// The canonical URL for a command: lowercase name, only the parameters that differ from "not given".
    public static func url(for command: AutomationCommand) -> URL {
        var components = URLComponents()
        components.scheme = ScreenCapKit.urlScheme
        components.host = command.name
        let items = queryItems(for: command).map { item in
            URLQueryItem(name: item.name, value: item.value.map(encode))
        }
        components.percentEncodedQueryItems = items.isEmpty ? nil : items
        // A fixed scheme, a known host and fully encoded query items always form a URL.
        guard let url = components.url else { preconditionFailure("Unbuildable URL for \(command.name)") }
        return url
    }

    /// Query-value characters left unencoded: `URLComponents` keeps `&`, `=` and `+` literal,
    /// which would split or alter a value, so those are encoded too (`#` and `%` already are).
    static let valueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#%"))

    /// Percent-encodes a query value so it parses back unchanged.
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? value
    }

    private static func queryItems(for command: AutomationCommand) -> [URLQueryItem] {
        switch command {
        case .allInOne(let region):
            return items(region)
        case let .captureArea(region, action):
            return items(region) + items(action)
        case .capturePreviousArea(let action), .captureFullscreen(let action),
             .captureWindow(let action), .selfTimer(let action):
            return items(action)
        case let .scrollingCapture(region, start, autoscroll):
            return items(region) + [
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "autoscroll", value: String(autoscroll))
            ]
        case let .captureText(source, lineBreaks):
            return items(source) + [URLQueryItem(name: "linebreaks", value: String(lineBreaks))]
        case .openAnnotate(let url), .pin(let url):
            return url.map { [file($0)] } ?? []
        case .addQuickAccessOverlay(let url):
            return [file(url)]
        case .openSettings(let tab):
            return tab.map { [URLQueryItem(name: "tab", value: $0.rawValue)] } ?? []
        case .openFromClipboard, .openHistory, .restoreRecentlyClosed,
             .toggleDesktopIcons, .hideDesktopIcons, .showDesktopIcons:
            return []
        }
    }

    private static func items(_ region: Region?) -> [URLQueryItem] {
        guard let region else { return [] }
        return [
            URLQueryItem(name: "x", value: format(region.x)),
            URLQueryItem(name: "y", value: format(region.y)),
            URLQueryItem(name: "width", value: format(region.width)),
            URLQueryItem(name: "height", value: format(region.height)),
            URLQueryItem(name: "display", value: String(region.display))
        ]
    }

    private static func items(_ source: AutomationCommand.TextSource?) -> [URLQueryItem] {
        switch source {
        case .file(let url): [file(url)]
        case .region(let region): items(region)
        case nil: []
        }
    }

    private static func items(_ action: AfterCaptureAction?) -> [URLQueryItem] {
        action.map { [URLQueryItem(name: "action", value: $0.rawValue)] } ?? []
    }

    private static func file(_ url: URL) -> URLQueryItem {
        URLQueryItem(name: "filepath", value: url.path)
    }

    /// Whole numbers print without a trailing ".0" so URLs stay readable.
    private static func format(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
