import CoreGraphics
import CoreText
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// A scrollable page: the scroll poster moves it (clamped to the content) and the frame source
/// shows the viewport at the current position, so a run behaves like a real window (#98).
@MainActor
private final class FakePage: ScrollEventPosting, ScrollingFrameSource {
    enum Event: Equatable {
        case frame(top: Int)
        case scroll(Int)
    }

    let image: CGImage
    let viewport: Int
    private(set) var top = 0
    private(set) var log: [Event] = []
    /// Captures that still show the last drawn position (the app redraws late).
    var staleCaptures = 0
    /// How far the page moves per posted point (Terminal moves about twice as far).
    var moveFactor = 1
    /// A prompt cursor on the last line that blinks on every capture once the page is at the end,
    /// so no two frames there are identical.
    var blinks = false
    private var shown = 0
    private var captures = 0

    init(image: CGImage, viewport: Int) {
        self.image = image
        self.viewport = viewport
    }

    nonisolated var isTrusted: Bool { true }

    func postScroll(at point: CGPoint, axis: ScrollAxis, delta: Int) {
        log.append(.scroll(delta))
        top = min(max(0, top + delta * moveFactor), image.height - viewport)
    }

    nonisolated func captureArea(pointRect: CGRect) async throws -> CapturedImage {
        await shoot(pointRect)
    }

    private func shoot(_ rect: CGRect) -> CapturedImage {
        if staleCaptures > 0 {
            staleCaptures -= 1
        } else {
            shown = top
        }
        log.append(.frame(top: shown))
        captures += 1
        // Fixture geometry is always valid. swiftlint:disable force_unwrapping
        var crop = image.cropping(to: CGRect(x: 0, y: shown, width: image.width, height: viewport))!
        if blinks, shown == image.height - viewport, captures.isMultiple(of: 2) {
            let context = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 40, y: 4, width: 12, height: 22)) // after the "> " prompt
            crop = context.makeImage()!
        }
        // swiftlint:enable force_unwrapping
        return CapturedImage(cgImage: crop, scale: 1, pointRect: rect, displayID: nil)
    }

    var scrolls: [Int] {
        log.compactMap { if case let .scroll(delta) = $0 { delta } else { nil } }
    }
}

/// The issue's Terminal fixture: 200 rows of 30 px, `$ make test` with `== build n ==` every 25 rows,
/// between the command at the top of the scrollback and the prompt at the bottom, as in the live repro.
private enum TerminalFixture {
    static let page: CGImage = render(
        ["Last login: Sat Oct 31 14:58:02 on ttys004", "~ screen-cap  main", "> for i in $(seq 1 300); do",
         ">   if (( i % 25 == 0 )); then echo \"== build $i ==\"", ">   else echo \"$ make test\"; fi", "> done"]
            + (6..<198).map { $0 % 25 == 0 ? "== build \($0) ==" : "$ make test" }
            + ["~ screen-cap  main", "> "]
    )

    private static func render(_ lines: [String]) -> CGImage {
        let width = 600
        let rowHeight = 30
        let height = lines.count * rowHeight
        // Fixture sizes are always valid. swiftlint:disable force_unwrapping
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Menlo" as CFString, 22, nil)
        for (index, text) in lines.enumerated() {
            let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 10, y: CGFloat(height - (index + 1) * rowHeight) + 9)
            CTLineDraw(line, context)
        }
        return context.makeImage()!
        // swiftlint:enable force_unwrapping
    }
}

@MainActor
@Suite("Scrolling frame loop")
struct ScrollingFrameLoopTests {
    private struct Run {
        let session: ScrollingSession
        let end: ScrollingCaptureEnd?
        let frames: [ScrollingFrameLoop.Frame]
    }

    /// Runs an auto-scroll capture the way the controller does, until the session stops.
    private func autoScroll(_ page: FakePage, step: Int = 100, limit: Int = 500,
                            beforeFrame: (Int) -> Void = { _ in }) async -> Run {
        var session = ScrollingSession(autoScroll: true)
        session.beginSelection()
        session.start()
        let collector = ScrollingFrameCollector(source: page, region: CGRect(x: 0, y: 0, width: 600, height: 600),
                                                axis: .vertical, maxLength: 50_000)
        let scroller = AutoScroller(step: step, poster: page)
        let loop = ScrollingFrameLoop(collector: collector, scroller: scroller, settle: .zero)
        var frames: [ScrollingFrameLoop.Frame] = []
        while session.isCapturing, frames.count < limit {
            scroller.start(at: .zero) // the controller's syncScroller: arms, posts nothing
            beforeFrame(frames.count)
            guard let frame = await loop.next(record: { frame in
                session.record(frame.outcome, frameChanged: frame.changed)
                return session.isCapturing
            }) else { break }
            frames.append(frame)
        }
        return Run(session: session, end: await collector.finish(), frames: frames)
    }

    private func pixels(_ image: CGImage) -> Data? {
        // Redraw into a known layout so crops and stitched output compare byte for byte.
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()?.dataProvider?.data as Data?
    }

    // #98 cause 1: the first frame shows the region as the user left it, before any scroll.
    @Test func firstFrameIsCapturedBeforeTheFirstScroll() async {
        let page = FakePage(image: TerminalFixture.page, viewport: 600)
        _ = await autoScroll(page, limit: 3)
        #expect(Array(page.log.prefix(4)) == [.frame(top: 0), .scroll(100), .frame(top: 100), .scroll(100)])
    }

    // #98 cause 2: repeating Terminal output auto-scrolls to the real end and stitches the whole page.
    @Test func repetitiveTerminalStitchesTheWholePage() async throws {
        let page = FakePage(image: TerminalFixture.page, viewport: 600)
        let run = await autoScroll(page)
        #expect(run.session.stopReason == .endReached)
        #expect(page.top == 5400) // the end of the content, not one screen in
        guard case let .image(image, problem, gapMarked) = run.end else {
            Issue.record("expected an image")
            return
        }
        #expect(problem == nil)
        #expect(!gapMarked)
        #expect(image.cgImage.height == 6000)
        #expect(try #require(pixels(image.cgImage)) == pixels(TerminalFixture.page))
    }

    // A page that redraws late shows the same pixels twice mid-scroll. That isn't the end: the
    // probe sees it still moving, and the run goes on to the bottom.
    @Test func lateRedrawIsNotTheEnd() async throws {
        let page = FakePage(image: TerminalFixture.page, viewport: 600)
        let run = await autoScroll(page) { index in
            if index == 4 { page.staleCaptures = 2 } // frames 4 and 5 repeat frame 3
        }
        #expect(run.session.stopReason == .endReached)
        #expect(page.top == 5400)
        #expect(page.scrolls.prefix(7).contains(-100)) // the probe ran mid-page
        guard case let .image(image, _, gapMarked) = run.end else {
            Issue.record("expected an image")
            return
        }
        #expect(!gapMarked)
        #expect(try #require(pixels(image.cgImage)) == pixels(TerminalFixture.page))
    }

    // A blinking cursor means no two frames are byte-identical, even at the end. Frames found in
    // place still count as still, so the run ends instead of polling forever.
    @Test func blinkingCursorStillEnds() async {
        let page = FakePage(image: TerminalFixture.page, viewport: 600)
        page.blinks = true
        let run = await autoScroll(page)
        #expect(run.session.stopReason == .endReached)
        #expect(page.top == 5400)
        #expect(run.frames.count < 70, "\(run.frames.prefix(80).map { "\($0.outcome) \($0.changed)" })")
        guard case let .image(image, _, _) = run.end else {
            Issue.record("expected an image")
            return
        }
        #expect(image.cgImage.height == 6000)
    }

    // At the real end the probe scrolls back one step and returns to the same pixels.
    @Test func endIsConfirmedByAProbe() async {
        let page = FakePage(image: TerminalFixture.page, viewport: 600)
        let run = await autoScroll(page)
        #expect(run.session.stopReason == .endReached)
        #expect(page.scrolls.suffix(2) == [-100, 100])
        #expect(page.top == 5400)
        #expect(run.frames.suffix(2).allSatisfy { !$0.changed })
    }

    // A page that doesn't scroll at all ends after the probe instead of running forever.
    @Test func pageThatNeverMovesEnds() async {
        let page = FakePage(image: TerminalFixture.prefixPage, viewport: 600)
        let run = await autoScroll(page)
        #expect(run.session.stopReason == .endReached)
        #expect(run.frames.count == 3)
        guard case let .image(image, _, _) = run.end else {
            Issue.record("expected an image")
            return
        }
        #expect(image.cgImage.height == 600)
    }
}

extension TerminalFixture {
    // Exactly one viewport of the page: nothing to scroll. Fixture geometry is always valid.
    // swiftlint:disable:next force_unwrapping
    fileprivate static let prefixPage = page.cropping(to: CGRect(x: 0, y: 0, width: 600, height: 600))!
}
