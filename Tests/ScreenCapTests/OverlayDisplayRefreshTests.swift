import CoreGraphics
@testable import ScreenCap
import ScreenCapKit
import Testing

/// #131: when the displays change under the selection overlay, it re-lays out on the new
/// arrangement, drops frozen stills that no longer match, and keeps nothing selectable off-screen.
@Suite("Overlay display refresh")
struct OverlayDisplayRefreshTests {
    /// The issue's 13" Air at its default mode.
    static let air = DisplayGeometry(displays: [
        DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1470, height: 956), backingScale: 2)
    ])
    /// The same display switched to 1280 × 832 HiDPI.
    static let airScaled = DisplayGeometry(displays: [
        DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1280, height: 832), backingScale: 2)
    ])
    /// The Air plus an external 1920 × 1080 at 1x to its left.
    static let withExternal = DisplayGeometry(displays: air.displays + [
        DisplayInfo(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), backingScale: 1)
    ])

    /// One still per display of `geometry`, as `captureAllDisplays` returns them.
    static func stills(of geometry: DisplayGeometry) throws -> [CapturedImage] {
        try geometry.displays.map { display in
            let image = try #require(CaptureLogicTests.solidImage(width: Int(display.pixelSize.width),
                                                                  height: Int(display.pixelSize.height)))
            return CapturedImage(cgImage: image, scale: display.backingScale, pointRect: display.frame,
                                 displayID: display.id)
        }
    }

    @Test func unchangedLayoutKeepsEverything() throws {
        let stills = try Self.stills(of: Self.air)
        let rect = CGRect(x: 1200, y: 700, width: 200, height: 200)
        let refresh = OverlayDisplayRefresh.make(stills: stills, rect: rect, previousRect: rect, geometry: Self.air)
        #expect(refresh.stills.count == 1)
        #expect(refresh.rect == rect)
        #expect(refresh.previousRect == rect)
    }

    // The issue: 1470 × 956 → 1280 × 832. The old still would show stretched and its right 190 pt
    // and top 124 pt couldn't be reached, so frozen mode ends; a selection past the new edge goes.
    @Test func resolutionChangeEndsFrozenModeAndDropsOffScreenSelections() throws {
        let stills = try Self.stills(of: Self.air)
        #expect(OverlayDisplayRefresh.stillsMatch(stills, Self.air))
        let offScreen = CGRect(x: 1200, y: 700, width: 200, height: 200) // past 1280 × 832
        let onScreen = CGRect(x: 100, y: 100, width: 300, height: 200)
        let refresh = OverlayDisplayRefresh.make(stills: stills, rect: offScreen, previousRect: onScreen,
                                                 geometry: Self.airScaled)
        #expect(refresh.geometry == Self.airScaled)
        #expect(refresh.stills.isEmpty)
        #expect(refresh.rect == nil)
        #expect(refresh.previousRect == onScreen)
    }

    // A display added: the new one has no still, so stills can't cover it; a selection spanning
    // both displays is fully on-screen and stays.
    @Test func addedDisplayEndsFrozenModeButKeepsASpanningSelection() throws {
        let stills = try Self.stills(of: Self.air)
        let spanning = CGRect(x: -100, y: 100, width: 300, height: 200)
        let refresh = OverlayDisplayRefresh.make(stills: stills, rect: nil, previousRect: spanning,
                                                 geometry: Self.withExternal)
        #expect(refresh.stills.isEmpty)
        #expect(refresh.previousRect == spanning)
        #expect(refresh.geometry.displays.count == 2)
    }

    // A display removed: stills of the one left still match it; a selection on the removed one goes.
    @Test func removedDisplayKeepsMatchingStills() throws {
        let stills = try Self.stills(of: Self.withExternal)
        let onExternal = CGRect(x: -1000, y: 100, width: 300, height: 200)
        let refresh = OverlayDisplayRefresh.make(stills: stills, rect: onExternal, previousRect: nil,
                                                 geometry: Self.air)
        #expect(refresh.stills.count == 2)
        #expect(OverlayDisplayRefresh.stillsMatch(refresh.stills, Self.air))
        #expect(refresh.rect == nil)
    }

    // Same display ID and size but moved in the arrangement: the still's frame no longer matches.
    @Test func movedDisplayDropsItsStill() throws {
        let stills = try Self.stills(of: Self.withExternal)
        let moved = DisplayGeometry(displays: Self.air.displays + [
            DisplayInfo(id: 2, frame: CGRect(x: 1470, y: 0, width: 1920, height: 1080), backingScale: 1)
        ])
        #expect(!OverlayDisplayRefresh.stillsMatch(stills, moved))
    }

    // Live mode has no stills to begin with and stays live.
    @Test func liveModeStaysLive() {
        let refresh = OverlayDisplayRefresh.make(stills: [], rect: nil, previousRect: nil, geometry: Self.airScaled)
        #expect(refresh.stills.isEmpty)
        #expect(refresh.geometry == Self.airScaled)
    }
}
