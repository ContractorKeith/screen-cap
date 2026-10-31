import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// Hands out scripted frames, then throws (#76). Frames are 300 px tall bands of a 1200 px page.
private actor FakeFrameSource: ScrollingFrameSource {
    struct Lost: LocalizedError {
        var errorDescription: String? { "The display was disconnected." }
    }

    private var tops: [Int]
    private let page: CGImage

    init(tops: [Int]) {
        self.tops = tops
        // Random opaque rows so every frame aligns exactly; one row of pixels per page line.
        var random = SystemRandomNumberGenerator()
        let width = 120
        let height = 1200
        let pixels = (0..<width * height).map { _ in
            UInt32.random(in: 0...UInt32.max, using: &random) | 0xff00_0000
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        // Fixture sizes are always valid. swiftlint:disable force_unwrapping
        page = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
        // swiftlint:enable force_unwrapping
    }

    func captureArea(pointRect: CGRect) async throws -> CapturedImage {
        guard !tops.isEmpty else { throw Lost() }
        let top = tops.removeFirst()
        guard let crop = page.cropping(to: CGRect(x: 0, y: top, width: page.width, height: 300)) else { throw Lost() }
        return CapturedImage(cgImage: crop, scale: 1, pointRect: pointRect, displayID: nil)
    }
}

@MainActor
@Suite("Scrolling capture failures")
struct ScrollingFailureTests {
    private let region = CGRect(x: 10, y: 20, width: 120, height: 300)

    private func collector(_ tops: [Int], maxLength: Int = 10_000) -> ScrollingFrameCollector {
        ScrollingFrameCollector(source: FakeFrameSource(tops: tops), region: region, axis: .vertical,
                                maxLength: maxLength)
    }

    @Test func failureOnTheFirstFrameReportsTheCause() async {
        let frames = collector([])
        #expect(await frames.grab { _ in nil } == nil)
        #expect(frames.failure != nil)
        guard case let .failed(problem) = await frames.finish() else {
            Issue.record("expected .failed")
            return
        }
        #expect(problem == "The display was disconnected.")
    }

    @Test func failurePartwayDeliversWhatWasStitched() async throws {
        let frames = collector([0, 100, 200])
        for _ in 0..<3 { #expect(await frames.grab { _ in nil } != nil) }
        #expect(await frames.grab { _ in nil } == nil)
        #expect(await frames.grab { _ in nil } == nil) // no more frames after a failure
        guard case let .image(image, problem, gapMarked) = await frames.finish() else {
            Issue.record("expected an image")
            return
        }
        #expect(image.cgImage.height == 500)
        #expect(image.pointRect == CGRect(x: 10, y: 320 - 500, width: 120, height: 500))
        #expect(problem == "The display was disconnected.")
        #expect(!gapMarked)
    }

    @Test func cleanStopHasNoProblem() async {
        let frames = collector([0, 100])
        _ = await frames.grab { _ in nil }
        _ = await frames.grab { _ in nil }
        guard case let .image(image, problem, _) = await frames.finish() else {
            Issue.record("expected an image")
            return
        }
        #expect(image.cgImage.height == 400)
        #expect(problem == nil)
    }

    // #71: a flick past the region, then Stop: the held frame is kept and flagged for the HUD.
    @Test func stopAfterAFlickKeepsTheLastScreen() async {
        let frames = collector([0, 600])
        #expect(await frames.grab { _ in nil } == .started)
        #expect(await frames.grab { _ in nil } == .unrelated)
        guard case let .image(image, problem, gapMarked) = await frames.finish() else {
            Issue.record("expected an image")
            return
        }
        #expect(gapMarked)
        #expect(problem == nil)
        #expect(image.cgImage.height == 300 + 2 + 300)
    }

    @Test func nothingCapturedIsNothingToReport() async {
        #expect(await collector([0]).finish() == nil)
    }

    @Test func sessionFailureKeepsTheCapture() {
        var session = ScrollingSession()
        session.beginSelection()
        session.start()
        session.fail()
        #expect(session.phase == .finishing)
        #expect(session.stopReason == .failed)

        var waiting = ScrollingSession()
        waiting.beginSelection()
        waiting.fail()
        #expect(waiting.phase == .cancelled)
    }
}
