import CoreGraphics
import ScreenCapKit

/// Hit-tests the cursor against on-screen windows for window capture (PLAN §5.2).
struct WindowPicker {
    /// Capturable windows, front to back.
    let windows: [ShareableWindow]

    /// Keeps normal app windows (layer 0) at least `minimumSide` points in each direction,
    /// so the menu bar, Dock, wallpaper and tiny helper windows are never picked.
    init(windows: [ShareableWindow], minimumSide: CGFloat = 40) {
        self.windows = windows.filter {
            $0.layer == 0 && $0.frame.width >= minimumSide && $0.frame.height >= minimumSide
        }
    }

    /// The frontmost window under a global point.
    func window(at point: CGPoint) -> ShareableWindow? {
        ShareableWindow.topmost(at: point, in: windows)
    }
}
