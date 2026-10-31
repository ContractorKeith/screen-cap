import Foundation
import ScreenCapKit

/// VoiceOver labels in one place (#117), so tests can check that none read as SF Symbol names.
enum A11y {
    // MARK: Editor toolbar

    /// Spoken name for a toolbar tool. Uses the same title as the tooltip, never `tool.symbol`.
    static func toolLabel(_ tool: EditorTool) -> String { tool.title }

    /// "Shortcut: V" for the tool's single-key shortcut.
    static func toolHint(_ tool: EditorTool) -> String {
        tool.key.map { "Shortcut: \(String($0).uppercased())" } ?? ""
    }

    static let arrowStyle = "Arrow style"
    static let textStyle = "Text style"
    static let cropAspect = "Crop aspect ratio"
    static let inspectorPanel = "Inspector panel"

    // MARK: Inspector

    static let pickScreenColor = "Pick color from screen"
    static let addToPalette = "Add current color to palette"
    static let swatchHint = "Applies this color. Right-click to remove it from the palette."
    static let selected = "Selected"

    /// Spoken name for a color: a plain color word, plus opacity when it isn't opaque.
    static func colorName(_ color: RGBAColor) -> String {
        let name = baseColorName(color)
        guard color.alpha < 0.995 else { return name }
        return "\(name), \(Int((color.alpha * 100).rounded()))% opacity"
    }

    private static func baseColorName(_ color: RGBAColor) -> String {
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        let saturation = high == 0 ? 0 : (high - low) / high
        if saturation < 0.15 {
            return grays.first { high < $0.below }?.name ?? "White"
        }
        let hue = hueDegrees(color, high: high, low: low)
        let name = hue >= 345 ? "Red" : hues.first { hue < $0.below }?.name ?? "Red"
        return high < 0.45 ? "Dark \(name)" : name
    }

    /// Upper bounds (exclusive) for gray brightness and hue in degrees.
    private static let grays: [(below: Double, name: String)] = [
        (0.15, "Black"), (0.45, "Dark Gray"), (0.75, "Gray"), (0.95, "Light Gray")
    ]
    private static let hues: [(below: Double, name: String)] = [
        (15, "Red"), (40, "Orange"), (70, "Yellow"), (170, "Green"), (200, "Teal"), (260, "Blue"),
        (300, "Purple"), (345, "Pink")
    ]

    private static func hueDegrees(_ color: RGBAColor, high: Double, low: Double) -> Double {
        let delta = high - low
        guard delta > 0 else { return 0 }
        let hue: Double
        if high == color.red {
            hue = (color.green - color.blue) / delta
        } else if high == color.green {
            hue = (color.blue - color.red) / delta + 2
        } else {
            hue = (color.red - color.green) / delta + 4
        }
        let degrees = hue * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// "Background: Dusk" for a bundled background thumbnail.
    static func background(_ name: String) -> String { "Background: \(name)" }

    /// "Align top left" for the background alignment grid.
    static func alignment(_ alignment: Document.Alignment) -> String {
        let words: String = switch alignment {
        case .center: "center"
        case .top: "top"
        case .bottom: "bottom"
        case .left: "left"
        case .right: "right"
        case .topLeft: "top left"
        case .topRight: "top right"
        case .bottomLeft: "bottom left"
        case .bottomRight: "bottom right"
        }
        return "Align \(words)"
    }

    // MARK: Settings

    /// "After capture: Area" for each row's action popup.
    static func afterCaptureLabel(_ row: String) -> String { "After capture: \(row)" }

    // MARK: History

    static let historySearch = "Search captures"
    static let historyKindFilter = "Capture kind filter"

    /// "Area capture, Oct 31, 4:08 PM, Google Chrome".
    static func historyThumbnail(kind: String, date: Date, source: String?, closed: Bool) -> String {
        let when = date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        var parts = ["\(kind) capture", when]
        if let source, !source.isEmpty { parts.append(source) }
        if closed { parts.append("closed from Quick Access") }
        return parts.joined(separator: ", ")
    }

    // MARK: Shortcuts

    /// Spells out modifier glyphs so VoiceOver reads "Control Shift 4" instead of "⌃⇧4".
    static func spokenShortcut(_ glyphs: String) -> String {
        let names: [Character: String] = ["⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command",
                                          "⇥": "Tab", "⏎": "Return", "↩": "Return", "⌫": "Delete",
                                          "⎋": "Escape", "←": "Left Arrow", "→": "Right Arrow",
                                          "↑": "Up Arrow", "↓": "Down Arrow", " ": "Space"]
        var words: [String] = []
        var rest = ""
        for character in glyphs {
            if let name = names[character] { words.append(name) } else { rest.append(character) }
        }
        if !rest.isEmpty { words.append(rest) }
        return words.joined(separator: " ")
    }
}
