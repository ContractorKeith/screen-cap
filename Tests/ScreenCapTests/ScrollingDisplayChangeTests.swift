import AppKit
import CoreGraphics
@testable import ScreenCap
import ScreenCapKit
import Testing

/// #127: a display change mid-capture ends a scrolling capture cleanly instead of running forever.
@MainActor
@Suite("Scrolling capture and display changes")
struct ScrollingDisplayChangeTests {
    /// Frames of fresh noise: nothing ever lines up or stays still, like frames taken over stale
    /// geometry after a resolution change, so auto-scroll never ends on its own. On capture
    /// `changeAt` it posts the screen-parameter change to `center` (a private center, so other
    /// suites' observers don't see it).
    private actor NoisePage: ScrollingFrameSource {
        let center: NotificationCenter
        let changeAt: Int?
        private(set) var captures = 0

        init(center: NotificationCenter, changeAt: Int?) {
            self.center = center
            self.changeAt = changeAt
        }

        func captureArea(pointRect: CGRect) async throws -> CapturedImage {
            captures += 1
            if captures == changeAt {
                center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            }
            var random = SystemRandomNumberGenerator()
            let (width, height) = (60, 120)
            let pixels = (0..<width * height).map { _ in
                UInt32.random(in: 0...UInt32.max, using: &random) | 0xff00_0000
            }
            let data = pixels.withUnsafeBytes { Data($0) }
            // Fixture sizes are always valid. swiftlint:disable force_unwrapping
            let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: CGDataProvider(data: data as CFData)!, decode: nil,
                                shouldInterpolate: false, intent: .defaultIntent)!
            // swiftlint:enable force_unwrapping
            return CapturedImage(cgImage: image, scale: 1, pointRect: pointRect, displayID: nil)
        }
    }

    private struct TrustedPoster: ScrollEventPosting {
        var isTrusted: Bool { true }
        func postScroll(at point: CGPoint, axis: ScrollAxis, delta: Int) {}
    }

    private struct Setup {
        let coordinator: CaptureCoordinator
        let controller: ScrollingCaptureController
        let sink: CaptureCoordinatorTests.RecordingSink
        let page: NoisePage
    }

    private func setup(changeAt: Int?, defaults: TemporaryDefaults) -> Setup {
        let settings = AppSettings(store: InMemorySettingsStore())
        let coordinator = CaptureCoordinator(settings: settings, source: CaptureCoordinatorTests.FakeSource(),
                                             history: nil, hasPermission: { true }, showOnboarding: {})
        let sink = CaptureCoordinatorTests.RecordingSink()
        coordinator.sink = sink
        let scrolling = ScrollingSettings(defaults: defaults.store)
        scrolling.frameRate = 30
        let center = NotificationCenter()
        let page = NoisePage(center: center, changeAt: changeAt)
        let controller = ScrollingCaptureController(
            coordinator: coordinator, settings: scrolling, poster: TrustedPoster(),
            launch: ScrollingLaunchOptions(region: nil, autoScroll: true), frameSource: page,
            notificationCenter: center
        )
        coordinator.scrollingHandler = { [controller] rect, context, action in
            await controller.run(region: rect, context: context, action: action)
        }
        return Setup(coordinator: coordinator, controller: controller, sink: sink, page: page)
    }

    // The change arrives on the 6th frame: the capture stops at once, delivers what was stitched,
    // and the outcome is a failure, so `--quit` exits (1) instead of hanging until Stop.
    @Test func displayChangeStopsTheCaptureAndDeliversWhatWasStitched() async throws {
        let defaults = TemporaryDefaults()
        defer { defaults.remove() }
        let setup = setup(changeAt: 6, defaults: defaults)
        setup.coordinator.scrollingRegion = CGRect(x: 100, y: 100, width: 60, height: 120)
        setup.controller.startsImmediately = true
        let task = try #require(setup.coordinator.capture(.scrolling, action: .pin))
        await task.value

        #expect(setup.controller.session.stopReason == .displayChanged)
        #expect(setup.controller.session.phase == .done)
        #expect(await setup.page.captures <= 7, "the frame loop stopped right after the change")
        #expect(setup.sink.delivered.map(\.action) == [.pin])
        let outcome = try #require(setup.coordinator.lastOutcome)
        #expect(outcome == .failed(ScrollingCaptureController.displayChangedProblem))
        #expect(outcome.exitStatus == 1)
    }

    // Before Start (still selecting) a display change cancels: nothing to keep yet.
    @Test func displayChangeWhileSelectingCancels() async throws {
        let defaults = TemporaryDefaults()
        defer { defaults.remove() }
        let setup = setup(changeAt: nil, defaults: defaults)
        setup.coordinator.scrollingRegion = CGRect(x: 100, y: 100, width: 60, height: 120)
        let task = try #require(setup.coordinator.capture(.scrolling, action: .pin))
        // Let the controller show its panels and wait for Start.
        while setup.controller.session.phase != .selecting { await Task.yield() }
        setup.controller.displaysChanged()
        await task.value
        #expect(setup.controller.session.phase == .cancelled)
        #expect(setup.sink.delivered.isEmpty)
        #expect(await setup.page.captures == 0)
    }

    @Test func sessionStopsOnlyWhileCapturing() {
        var capturing = ScrollingSession(autoScroll: true)
        capturing.beginSelection()
        capturing.start()
        capturing.displayChanged()
        #expect(capturing.phase == .finishing)
        #expect(capturing.stopReason == .displayChanged)

        var selecting = ScrollingSession()
        selecting.beginSelection()
        selecting.displayChanged()
        #expect(selecting.phase == .cancelled)
    }
}
