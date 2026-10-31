// Builds DisplayGeometry from the live NSScreen list.
import AppKit

public extension DisplayGeometry {
    /// The current display arrangement from `NSScreen.screens`. The first screen is the primary one.
    @MainActor
    static func fromCurrentScreens() -> DisplayGeometry {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let displays = NSScreen.screens.compactMap { screen -> DisplayInfo? in
            guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
            return DisplayInfo(id: number.uint32Value, frame: screen.frame, backingScale: screen.backingScaleFactor)
        }
        return DisplayGeometry(displays: displays)
    }
}
