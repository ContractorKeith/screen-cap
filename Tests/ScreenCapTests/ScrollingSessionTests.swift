import CoreGraphics
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("ScrollingSession")
struct ScrollingSessionTests {
    private func capturing(auto: Bool) -> ScrollingSession {
        var session = ScrollingSession(autoScroll: auto)
        session.beginSelection()
        session.start()
        return session
    }

    @Test func happyPathManual() {
        var session = ScrollingSession()
        #expect(session.phase == .idle)
        session.beginSelection()
        #expect(session.phase == .selecting)
        let result1 = session.start()
        #expect(result1 == .manual)
        #expect(session.phase == .capturing(.manual))
        session.stop()
        #expect(session.phase == .finishing)
        #expect(session.stopReason == .stopped)
        session.delivered(hasImage: true)
        #expect(session.phase == .done)
        #expect(session.isFinal)
    }

    @Test func startUsesAutoToggle() {
        var session = ScrollingSession(autoScroll: true)
        let result2 = session.start() // not selecting yet
        #expect(result2 == nil)
        session.beginSelection()
        let result3 = session.start()
        #expect(result3 == .auto)
        #expect(session.mode == .auto)
    }

    @Test func cancelFromEveryLivePhase() {
        var selecting = ScrollingSession()
        selecting.beginSelection()
        selecting.cancel()
        #expect(selecting.phase == .cancelled)

        var live = capturing(auto: true)
        live.cancel()
        #expect(live.phase == .cancelled)
        live.start()
        #expect(live.phase == .cancelled)
    }

    @Test func stopOrEscapeBeforeStartCancels() {
        var stop = ScrollingSession()
        stop.beginSelection()
        stop.stop()
        #expect(stop.phase == .cancelled)

        var escape = ScrollingSession()
        escape.beginSelection()
        escape.escape()
        #expect(escape.phase == .cancelled)
    }

    @Test func escapeKeepsTheCapture() {
        var session = capturing(auto: false)
        session.escape()
        #expect(session.phase == .finishing)
        #expect(session.stopReason == .escape)
    }

    @Test func deliveringNothingCancels() {
        var session = capturing(auto: false)
        session.stop()
        session.delivered(hasImage: false)
        #expect(session.phase == .cancelled)
    }

    @Test func autoStopsOnTwoConsecutiveStillFrames() {
        var session = capturing(auto: true)
        let result4 = session.record(.started)
        #expect(!result4)
        let result5 = session.record(.noMovement)
        #expect(!result5)
        let result6 = session.record(.appended(lines: 40)) // movement resets the count
        #expect(!result6)
        let result7 = session.record(.noMovement)
        #expect(!result7)
        let result8 = session.record(.unrelated) // a transient neither counts nor resets
        #expect(!result8)
        let result9 = session.record(.noMovement)
        #expect(result9)
        #expect(session.phase == .finishing)
        #expect(session.stopReason == .endReached)
    }

    @Test func manualIgnoresStillFrames() {
        var session = capturing(auto: false)
        for _ in 0..<5 {
            let result10 = session.record(.noMovement)
            #expect(!result10)
        }
        #expect(session.phase == .capturing(.manual))
    }

    @Test(arguments: [false, true])
    func maxLengthStopsEitherMode(auto: Bool) {
        var session = capturing(auto: auto)
        let result11 = session.record(.maxLengthReached)
        #expect(result11)
        #expect(session.stopReason == .maxLengthReached)
    }

    @Test func accessibilityDeniedFallsBackToManual() {
        var session = capturing(auto: true)
        session.accessibilityDenied()
        #expect(session.phase == .capturing(.manual))
        #expect(!session.autoScroll)
        session.record(.noMovement)
        let result12 = session.record(.noMovement)
        #expect(!result12)
    }

    @Test func toggleSwitchesModeMidCapture() {
        var session = capturing(auto: false)
        session.setAutoScroll(true)
        #expect(session.mode == .auto)
        session.setAutoScroll(false)
        #expect(session.mode == .manual)
    }

    @Test func axisLocksOnceCapturing() {
        var session = ScrollingSession()
        session.beginSelection()
        session.setAxis(.horizontal)
        #expect(session.axis == .horizontal)
        session.start()
        session.setAxis(.vertical)
        #expect(session.axis == .horizontal)
    }
}

@Suite("PreviewFit")
struct PreviewFitTests {
    @Test func tallImageFitsHeight() {
        let rect = PreviewFit.rect(for: CGSize(width: 1000, height: 10_000),
                                  in: CGRect(x: 0, y: 0, width: 200, height: 400))
        #expect(rect == CGRect(x: 80, y: 0, width: 40, height: 400))
    }

    @Test func wideImageFitsWidth() {
        let rect = PreviewFit.rect(for: CGSize(width: 4000, height: 1000),
                                  in: CGRect(x: 10, y: 20, width: 200, height: 400))
        #expect(rect == CGRect(x: 10, y: 195, width: 200, height: 50))
    }

    @Test func neverUpscales() {
        let rect = PreviewFit.rect(for: CGSize(width: 50, height: 100), in: CGRect(x: 0, y: 0, width: 200, height: 400))
        #expect(rect == CGRect(x: 75, y: 150, width: 50, height: 100))
    }

    @Test func emptyInputsGiveZeroRect() {
        let rect = PreviewFit.rect(for: .zero, in: CGRect(x: 0, y: 0, width: 200, height: 400))
        #expect(rect == CGRect(x: 100, y: 200, width: 0, height: 0))
    }
}

@Suite("ScrollingPanelLayout")
struct ScrollingPanelLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func prefersRightOfRegion() {
        let region = CGRect(x: 100, y: 100, width: 600, height: 700)
        let frames = ScrollingPanelLayout.frames(region: region, screen: screen)
        #expect(frames.control.minX == region.maxX + ScrollingPanelLayout.gap)
        #expect(frames.control.maxY == region.maxY)
        #expect(frames.preview.maxY == frames.control.minY - ScrollingPanelLayout.gap)
        #expect(frames.preview.minY == region.minY)
    }

    @Test func fallsBackToLeft() {
        let region = CGRect(x: 800, y: 100, width: 600, height: 700)
        let frames = ScrollingPanelLayout.frames(region: region, screen: screen)
        #expect(frames.control.maxX == region.minX - ScrollingPanelLayout.gap)
    }

    @Test func fullScreenRegionStaysOnScreen() {
        let frames = ScrollingPanelLayout.frames(region: screen, screen: screen)
        #expect(screen.contains(frames.control))
        #expect(screen.contains(frames.preview))
    }
}

@Suite("ScrollingLaunchOptions")
struct ScrollingLaunchOptionsTests {
    @Test func parsesRegionAndAutoscroll() {
        let options = ScrollingLaunchOptions.parse(
            ["ScreenCap", "--capture", "scrolling", "--region", "10, 20,300,400.5", "--autoscroll", "on"]
        )
        #expect(options.region == CGRect(x: 10, y: 20, width: 300, height: 400.5))
        #expect(options.autoScroll == true)
    }

    @Test(arguments: ["1,2,3", "a,b,c,d", "0,0,0,10", "0,0,10,-1"])
    func rejectsBadRects(text: String) {
        #expect(ScrollingLaunchOptions.parseRect(text) == nil)
    }

    @Test func absentOptionsAreNil() {
        let options = ScrollingLaunchOptions.parse(["ScreenCap", "--capture", "area"])
        #expect(options == ScrollingLaunchOptions())
    }
}
