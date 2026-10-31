import AppKit

/// Keeps app windows (Settings, Welcome) fully on screen (#115). The math is pure; `place`
/// applies it to a window whose SwiftUI content has been sized first.
enum WindowPlacement {
    /// `size` centered in `visible`, shrunk to fit it.
    static func centered(_ size: CGSize, in visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        return CGRect(x: (visible.midX - width / 2).rounded(), y: (visible.midY - height / 2).rounded(),
                      width: width, height: height)
    }

    /// `frame` moved (and shrunk to no less than `minSize`) to lie inside `visible`. A window
    /// that can't shrink enough keeps its title bar on screen (top-left aligned).
    static func clamped(_ frame: CGRect, to visible: CGRect, minSize: CGSize = .zero) -> CGRect {
        let width = max(min(frame.width, visible.width), minSize.width)
        let height = max(min(frame.height, visible.height), minSize.height)
        let x = max(min(frame.minX, visible.maxX - width), visible.minX)
        let y = min(max(frame.minY, visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// First show: size the window to its content, restore the saved position (else center it),
    /// clamp to the screen, then remember the position under `autosaveName`.
    @MainActor
    static func placeNew(_ window: NSWindow, autosaveName: String, contentSize: CGSize? = nil) {
        if let contentSize {
            window.setContentSize(contentSize)
        } else if let content = window.contentViewController?.view {
            content.layoutSubtreeIfNeeded()
            let fitting = content.fittingSize
            if fitting.width > 0, fitting.height > 0 { window.setContentSize(fitting) }
        }
        let restored = window.setFrameUsingName(autosaveName)
        if !restored || window.screen == nil, let visible = screen(for: window)?.visibleFrame {
            window.setFrame(centered(window.frame.size, in: visible), display: false)
        }
        clampOnScreen(window)
        window.setFrameAutosaveName(autosaveName)
    }

    /// Every show: pull the window back inside its screen's visible frame (displays and the
    /// Dock change while the app runs).
    @MainActor
    static func clampOnScreen(_ window: NSWindow) {
        guard let visible = screen(for: window)?.visibleFrame else { return }
        let minSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: window.contentMinSize)).size
        let frame = clamped(window.frame, to: visible, minSize: minSize)
        if frame != window.frame { window.setFrame(frame, display: true) }
    }

    @MainActor
    private static func screen(for window: NSWindow) -> NSScreen? {
        window.screen ?? NSScreen.main ?? NSScreen.screens.first
    }
}
