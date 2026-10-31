import CoreGraphics
import CoreText
import Foundation
@testable import ScreenCapKit
import Testing

/// Auto-scroll over repeating Terminal output (#112): the stitched rows must be exactly the page's
/// rows, in order, with no seam. Frames carry ±1 dither fixed to the screen, like live captures, so
/// moved content never matches byte for byte; the comparison here ignores that low bit.
@Suite("Auto-scroll on repetitive content")
struct AutoScrollStitchTests {
    typealias Line = ScrollFixtures.Line

    /// Keeps alpha and the top 6 bits of each channel: the dither only flips the lowest two.
    static func rowHash(_ line: Line) -> Int {
        line.withUnsafeBufferPointer { pixels in
            var hasher = Hasher()
            for pixel in pixels { hasher.combine(pixel & 0xfffc_fcfc) }
            return hasher.finalize()
        }
    }

    struct Run {
        let outcomes: [Stitcher.AppendOutcome]
        let lines: [Line]
        let seams: Int
        let measuredScale: Double?
    }

    /// Scrolls `page` (lines) through a `viewport`-line region: each frame the scroller posts
    /// `posted` pixels and the page moves `moved` (or `jumps[frame]` into that frame, or the next of
    /// `pattern` when given: live Terminal moves unevenly), clamped at the end. Posted distance
    /// carries over frames the stitcher doesn't place, as in `ScrollingFrameLoop`. `noise` is the
    /// dither mask XORed into every frame.
    static func autoScroll(_ page: [Line], viewport: Int, posted: Int, moved: Int, jumps: [Int: Int] = [:],
                           pattern: [Int] = [], noise: UInt32 = 0x0001_0101, knob: Bool = false,
                           usesVision: Bool = true) async throws -> Run {
        let stitcher = Stitcher(axis: .vertical, scale: 2, aligner: FrameAligner(usesVision: usesVision))
        let end = page.count - viewport
        var top = 0
        var distance = 0
        var outcomes: [Stitcher.AppendOutcome] = []
        var stillFrames = 0
        while stillFrames < 2 {
            await stitcher.setExpectedStep(distance > 0 ? distance : nil, unit: posted)
            let outcome = await stitcher.append(frame: Self.frame(page, top: top, viewport: viewport, noise: noise,
                                                                  knob: knob))
            outcomes.append(outcome)
            switch outcome {
            case .started, .appended, .gapDetected: distance = 0
            default: break
            }
            stillFrames = top == end ? stillFrames + 1 : 0
            let step = pattern.isEmpty ? moved : pattern[(outcomes.count - 1) % pattern.count]
            top = min(end, top + (jumps[outcomes.count] ?? step))
            distance += posted
        }
        let image = try #require(await stitcher.finish())
        let lines = ScrollFixtures.lines(of: image, axis: .vertical)
        let seamRed = ScrollFixtures.pixel(230, 40, 40)
        let seams = zip(lines, lines.dropFirst()).filter { $0.1[0] == seamRed && $0.0[0] != seamRed }.count
            + (lines.first?[0] == seamRed ? 1 : 0)
        return Run(outcomes: outcomes, lines: lines, seams: seams, measuredScale: await stitcher.measuredScale)
    }

    /// The region at `top` with screen-fixed dither: each pixel's low bits flip by its position on
    /// the screen (a 64×64 tile, like the live captures), not by the content under it.
    /// `knob` draws an overlay scroll-bar knob at the right edge, fixed on screen and creeping
    /// down as the page scrolls, like Terminal's while it scrolls (#126).
    static func frame(_ page: [Line], top: Int, viewport: Int, noise: UInt32 = 0x0001_0101,
                      knob: Bool = false) -> CGImage {
        let width = page[0].count
        var pixels = [UInt32](repeating: 0, count: width * viewport)
        let knobLength = viewport / 3
        let knobTop = (viewport - knobLength) * top / max(1, page.count - viewport)
        pixels.withUnsafeMutableBufferPointer { output in
            dither.withUnsafeBufferPointer { dither in
                for row in 0..<viewport {
                    page[top + row].withUnsafeBufferPointer { line in
                        let tile = (row % 64) * 64
                        for column in 0..<width {
                            let inKnob = knob && column >= width - 22 && column < width - 6
                                && (knobTop..<knobTop + knobLength).contains(row)
                            let pixel = inKnob ? ScrollFixtures.pixel(110, 110, 110) : line[column]
                            output[row * width + column] = pixel ^ (dither[tile + column % 64] & noise)
                        }
                    }
                }
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        // Fixture sizes are always valid, so these force unwraps cannot fail.
        // swiftlint:disable force_unwrapping
        return CGImage(
            width: width, height: viewport, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
        // swiftlint:enable force_unwrapping
    }

    static let dither: [UInt32] = {
        var random = SeededGenerator(seed: 64)
        return (0..<64 * 64).map { _ in UInt32(truncatingIfNeeded: random.next()) & 0x0003_0303 }
    }()

    /// Expects the stitched rows to be the page's rows, in order: nothing dropped, nothing twice.
    static func expectExact(_ run: Run, page: [Line], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(run.seams == 0, "\(run.outcomes)", sourceLocation: sourceLocation)
        #expect(run.lines.count == page.count, "\(run.outcomes)", sourceLocation: sourceLocation)
        let stitched = run.lines.map(rowHash)
        let source = page.map(rowHash)
        let firstWrong = zip(stitched, source).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        #expect(stitched == source, "first wrong row \(firstWrong.map(String.init) ?? "-")",
                sourceLocation: sourceLocation)
    }

    // MARK: - The issue's fixture

    // #112: period-25 output, 120 pt auto-scroll step (240 px posted at 2x) that Terminal turns
    // into 360 px, 780 pt region at 2x. Before the fix: 16 and 8 lines between markers with no
    // seam, and blocks repeated after seams (1000 × 10252 px instead of the page's height).
    @Test func issueFixtureStitchesEveryRowOnce() async throws {
        let page = TerminalPage.issue
        let run = try await Self.autoScroll(page, viewport: 1560, posted: 240, moved: 360)
        #expect(run.measuredScale == 1.5)
        #expect(!run.outcomes.contains(.ambiguous) && !run.outcomes.contains(.unrelated), "\(run.outcomes)")
        Self.expectExact(run, page: page)

        // Each `== build n ==` marker comes out exactly once, 24 output lines after the one before.
        let stitched = run.lines.map(Self.rowHash)
        var starts: [Int] = []
        for row in TerminalPage.markerRows {
            let block = page[row * 30..<(row + 1) * 30].map(Self.rowHash)
            let found = stitched.indices.filter { start in
                stitched[start] == block[0] && start + 30 <= stitched.count
                    && stitched[start..<start + 30].elementsEqual(block)
            }
            #expect(found.count == 1, "marker at row \(row) found \(found.count) times")
            starts += found
        }
        #expect(starts.count == 12)
        #expect(zip(starts, starts.dropFirst()).allSatisfy { $1 - $0 == 25 * 30 }, "\(starts)")
    }

    // A page that once jumps further than the measured step, over rows that all repeat, can't be
    // placed. It's kept after a seam, but only from where the image ends: rows may be missing at
    // the seam, but none repeat. Before, the whole frame followed the seam and repeated ~19 lines.
    @Test(arguments: [(15, false), (12, true)])
    func jumpIsNeverRepeated(frame: Int, overlapHasMarker: Bool) async throws {
        let page = TerminalPage.issue
        let run = try await Self.autoScroll(page, viewport: 1560, posted: 240, moved: 360, jumps: [frame: 1000])
        let source = page.map(Self.rowHash)
        let seamRed = ScrollFixtures.pixel(230, 40, 40)
        let parts = run.lines.split { $0[0] == seamRed }.map { $0.map(Self.rowHash) }
        if overlapHasMarker {
            // A marker in the overlap lines the jump up exactly: no seam.
            #expect(run.seams == 0)
            #expect(parts.flatMap { $0 } == source)
            return
        }
        #expect(run.seams == 1, "\(run.outcomes)")
        try #require(parts.count == 2)
        let before = parts[0]
        let after = parts[1]
        #expect(Array(source.prefix(before.count)) == before, "before the seam: the page's start")
        #expect(Array(source.suffix(after.count)) == after, "after the seam: the page's end")
        #expect(before.count + after.count <= source.count, "rows after the seam repeat rows before it")
    }

    // MARK: - Property: any step on a repeating page

    // Seeded random steps of 50–400 px, the page moving 1×, 1.5× or 2× the posted distance, over
    // output that repeats for longer than the 600 px region: most frames see only `$ make test`.
    @Test(arguments: 0..<12)
    func randomStepsStitchExactly(seed: Int) async throws {
        var random = SeededGenerator(seed: UInt64(seed) &+ 1000)
        let ratio = [(1, 1), (3, 2), (2, 1)][Int(random.next() % 3)]
        let posted = Int.random(in: (50 * ratio.1 + ratio.0 - 1) / ratio.0...400 * ratio.1 / ratio.0,
                                using: &random)
        let moved = posted * ratio.0 / ratio.1
        let page = TerminalPage.repeating
        let run = try await Self.autoScroll(page, viewport: 600, posted: posted, moved: moved)
        #expect((50...400).contains(moved))
        Self.expectExact(run, page: page)
    }
}

/// Terminal pages rendered as lines: light Menlo on #1e1e1e, 30 px rows, at 2x.
enum TerminalPage {
    static let rowHeight = 30
    static let header = ["Last login: Sat Oct 31 14:58:02 on ttys004", "", "~  v3.11.8",
                         "> clear; for i in $(seq 1 300); do if (( i % 25 == 0 )); then echo \"== build $i ==\"; "
                             + "else echo \"\\$ make test\"; fi; done"]
        + Array(repeating: "", count: 20)

    /// The issue's page: the command, blank lines, 300 lines of output, the prompt.
    static let issue: [Line] = render(header + output(1...300) + ["", "~  v3.11.8", "> "], width: 1000)

    /// Text rows of `issue` holding a `== build n ==` marker.
    static let markerRows: [Int] = (1...300).filter { $0 % 25 == 0 }.map { header.count + $0 - 1 }

    /// 20 unique lines, 80 lines of period-25 output, 20 unique lines; 400 px wide.
    static let repeating: [Line] = render(
        (0..<20).map { "Session \($0): \($0 * 7919 % 1000) ok" } + output(1...80)
            + (0..<20).map { "Summary \($0): \($0 * 104_729 % 1000)" },
        width: 400
    )

    typealias Line = ScrollFixtures.Line

    static func output(_ range: ClosedRange<Int>) -> [String] {
        range.map { $0 % 25 == 0 ? "== build \($0) ==" : "$ make test" }
    }

    static func render(_ lines: [String], width: Int) -> [Line] {
        let height = lines.count * rowHeight
        // Fixture sizes are always valid, so these force unwraps cannot fail.
        // swiftlint:disable force_unwrapping
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // swiftlint:enable force_unwrapping
        context.setFillColor(CGColor(red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Menlo" as CFString, 24, nil)
        let ink = CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        for (index, text) in lines.enumerated() where !text.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 20, y: CGFloat(height - (index + 1) * rowHeight) + 8)
            CTLineDraw(line, context)
        }
        // swiftlint:disable:next force_unwrapping
        return ScrollFixtures.lines(of: context.makeImage()!, axis: .vertical)
    }
}
