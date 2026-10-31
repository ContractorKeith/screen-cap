import CoreGraphics
import ScreenCapKit

/// What the selection overlay keeps after the displays change under it (#131): a resolution or
/// scale change, a display added or removed, clamshell. Pure, so it's tested with synthetic layouts.
struct OverlayDisplayRefresh {
    /// The arrangement to lay the panels out on.
    let geometry: DisplayGeometry
    /// Frozen stills that still match their displays exactly; empty ends frozen mode (the overlay
    /// dims the live screen and the capture is taken live), since a still of a mode that's gone
    /// would show stretched and shifted, and cutting it would capture a screen that no longer exists.
    let stills: [CapturedImage]
    /// The selection, if it still lies entirely on a display.
    let rect: CGRect?
    /// The previous area, if it still lies entirely on a display.
    let previousRect: CGRect?

    /// Whether frozen stills are still usable: one per display, each the display's exact frame and pixel size.
    static func stillsMatch(_ stills: [CapturedImage], _ geometry: DisplayGeometry) -> Bool {
        geometry.displays.allSatisfy { display in
            stills.contains { still in
                still.displayID == display.id && still.pointRect == display.frame
                    && CGSize(width: still.cgImage.width, height: still.cgImage.height) == display.pixelSize
            }
        }
    }

    static func make(stills: [CapturedImage], rect: CGRect?, previousRect: CGRect?,
                     geometry: DisplayGeometry) -> OverlayDisplayRefresh {
        // Every part of the rect must lie on some display (it may span several).
        func onScreen(_ rect: CGRect?) -> CGRect? {
            guard let rect, !rect.isEmpty else { return nil }
            let covered = geometry.slices(forGlobalPoints: rect)
                .reduce(0) { $0 + $1.pointRect.width * $1.pointRect.height }
            return covered >= rect.width * rect.height - 0.5 ? rect : nil
        }
        return OverlayDisplayRefresh(geometry: geometry, stills: stillsMatch(stills, geometry) ? stills : [],
                                     rect: onScreen(rect), previousRect: onScreen(previousRect))
    }
}
