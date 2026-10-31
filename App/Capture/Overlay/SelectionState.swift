import CoreGraphics
import ScreenCapKit

/// Area drag or window hover. Space toggles between them.
enum SelectionMode: Equatable {
    case area, window
}

/// The All-In-One toolbar's buttons, shown under a fresh selection.
enum AllInOneChoice: String, CaseIterable {
    case area, window, fullscreen, scrolling, text, timer

    var title: String {
        switch self {
        case .area: "Area"
        case .window: "Window"
        case .fullscreen: "Fullscreen"
        case .scrolling: "Scrolling"
        case .text: "Text"
        case .timer: "Timer"
        }
    }

    /// Whether this choice's rect becomes the new "previous area". OCR and scrolling regions don't.
    var remembersArea: Bool {
        switch self {
        case .area, .window, .fullscreen, .timer: true
        case .scrolling, .text: false
        }
    }

    var symbolName: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .fullscreen: "display"
        case .scrolling: "arrow.up.and.down.text.horizontal"
        case .text: "text.viewfinder"
        case .timer: "timer"
        }
    }
}

/// How a selection session ended. Rects are global AppKit points.
enum SelectionOutcome: Equatable {
    case area(CGRect)
    case window(ShareableWindow)
    case allInOne(AllInOneChoice, CGRect)
    case cancelled
}

/// Overlay appearance and behavior for one session.
struct SelectionOptions {
    /// Show the frozen still behind the overlay. Off means live mode: dim only.
    var showsStill = true
    var showsCrosshair = true
    var showsMagnifier = true
    /// After a selection, show the All-In-One toolbar instead of finishing.
    var allInOne = false
    var startMode: SelectionMode = .area
    /// Last area; Return confirms it when nothing is selected.
    var previousRect: CGRect?
}

/// Shared, mutable state of one session, drawn by every display's view.
@MainActor
final class SelectionState {
    var mode: SelectionMode
    /// Current selection (dragging, fixed-size or confirmed).
    var rect: CGRect?
    var previousRect: CGRect?
    /// Cursor position in global points.
    var mouse: CGPoint = .zero
    /// Drag anchor; nil when not dragging.
    var dragStart: CGPoint?
    /// The last confirmed selection (or the previous area); ⇧ falls back to its ratio.
    var lastSelection: CGRect?
    /// Width ÷ height while ⇧ is held during a drag.
    var lockedAspect: CGFloat?
    /// Typed W×H; while set the rect follows the cursor.
    var fixedSize: CGSize?
    var hoveredWindow: ShareableWindow?
    var toolbarVisible = false

    init(mode: SelectionMode, previousRect: CGRect?) {
        self.mode = mode
        self.previousRect = previousRect
        self.lastSelection = previousRect
    }

    var isDragging: Bool { dragStart != nil }
}
