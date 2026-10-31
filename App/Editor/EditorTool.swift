import Foundation
import ScreenCapKit

/// The editor's tool palette (PLAN §3.3). Raw values are persisted in Annotate settings.
enum EditorTool: String, CaseIterable, Codable, Sendable, Identifiable {
    case select, arrow, rectangle, filledRectangle, ellipse, line, text, counter
    case pencil, highlighter, blur, pixelate, spotlight, crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .filledRectangle: "Filled Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .text: "Text"
        case .counter: "Counter"
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .spotlight: "Spotlight"
        case .crop: "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .filledRectangle: "rectangle.fill"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .text: "textformat"
        case .counter: "1.circle"
        case .pencil: "pencil.tip"
        case .highlighter: "highlighter"
        case .blur: "drop.halffull"
        case .pixelate: "checkerboard.rectangle"
        case .spotlight: "flashlight.on.fill"
        case .crop: "crop"
        }
    }

    /// Single-key shortcut shown in the tooltip and handled by the canvas.
    var key: Character? {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .filledRectangle: "f"
        case .ellipse: "o"
        case .line: "l"
        case .text: "t"
        case .counter: "n"
        case .pencil: "p"
        case .highlighter: "h"
        case .blur: "b"
        case .pixelate: "x"
        case .spotlight: "s"
        case .crop: "c"
        }
    }

    /// Tools that create freehand paths from every drag point.
    var isFreehand: Bool { self == .pencil || self == .highlighter }

    /// Tools that make an object from a single click.
    var acceptsClick: Bool { self == .counter || self == .text }
}

/// The four arrow styles offered in the toolbar. `curved` gets its control point at creation.
enum ArrowChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    case straight, tapered, doubleHeaded, curved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .straight: "Straight"
        case .tapered: "Tapered"
        case .doubleHeaded: "Double-Headed"
        case .curved: "Curved"
        }
    }

    init(_ style: Annotation.ArrowStyle) {
        switch style {
        case .straight: self = .straight
        case .tapered: self = .tapered
        case .doubleHeaded: self = .doubleHeaded
        case .curved: self = .curved
        }
    }
}

extension TextPreset {
    var title: String {
        switch self {
        case .plain: "Plain"
        case .outlined: "Outlined"
        case .filledBackground: "Filled Background"
        case .monospace: "Monospace"
        case .roundedLabel: "Rounded Label"
        case .boldUppercase: "Bold Uppercase"
        case .handwritten: "Handwritten"
        }
    }
}

enum SpotlightChoice: String, CaseIterable, Codable, Sendable {
    case rect, ellipse
}

/// Settings a tool applies to the objects it creates; the inspector edits these.
struct ToolOptions: Equatable, Sendable {
    var style = Annotation.Style()
    var arrow: ArrowChoice = .straight
    var textPreset: TextPreset = .plain
    var fontSize: Double = 28
    var cornerRadius: Double = 0
    var counterRadius: Double = 18
    var blurMode: Annotation.BlurMode = .secure
    var blurRadius: Double = 12
    var pixelateBlockSize = 12
    var pixelateRandomize = true
    var spotlightShape: SpotlightChoice = .rect
    var highlightColor: RGBAColor = .highlightYellow
}
