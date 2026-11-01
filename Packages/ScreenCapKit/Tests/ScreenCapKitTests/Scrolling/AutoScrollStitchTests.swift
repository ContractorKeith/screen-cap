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
        // Masks into a buffer and hashes its bytes in one call: per-pixel `combine` is slow in debug (#140).
        var masked = line
        masked.withUnsafeMutableBufferPointer { pixels in
            for index in pixels.indices { pixels[index] &= 0xfffc_fcfc }
        }
        return masked.withUnsafeBytes { bytes in
            var hasher = Hasher()
            hasher.combine(bytes: bytes)
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
        let knobPixel = ScrollFixtures.pixel(110, 110, 110)
        // The dither tile spread across the frame's width, masked once: 64 rows (#140, debug speed).
        let tiled = (0..<64 * width).map { dither[($0 / width) * 64 + $0 % width % 64] & noise }
        pixels.withUnsafeMutableBufferPointer { output in
            tiled.withUnsafeBufferPointer { tiled in
                for row in 0..<viewport {
                    let out = output.baseAddress! + row * width // swiftlint:disable:this force_unwrapping
                    let mask = tiled.baseAddress! + (row % 64) * width // swiftlint:disable:this force_unwrapping
                    page[top + row].withUnsafeBufferPointer { line in
                        for column in 0..<width { out[column] = line[column] ^ mask[column] }
                    }
                    guard knob, row >= knobTop, row < knobTop + knobLength else { continue }
                    for column in max(0, width - 22)..<(width - 6) { out[column] = knobPixel ^ mask[column] }
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

    // MARK: - Property: any step on a repeating page

    /// Fixed seeds chosen to cover every ratio at small and large steps (#140; seed: ratio, posted
    /// → moved px): 2: 1×, 183; 37: 1×, 345; 8: 1.5×, 40 → 60; 13: 1.5×, 142 → 213; 27: 1.5×, 257 →
    /// 385; 4: 2×, 66 → 132; 24: 2×, 191 → 382. Plus one fresh seed each run, printed on failure.
    static let seeds: [Int] = [2, 37, 8, 13, 27, 4, 24, Int.random(in: 40..<1_000_000)]

    // #112: seeded random steps of 50–400 px, the page moving 1×, 1.5× or 2× the posted distance,
    // over output that repeats for longer than the 600 px region: most frames see only `$ make test`.
    @Test(arguments: seeds)
    func randomStepsStitchExactly(seed: Int) async throws {
        var random = SeededGenerator(seed: UInt64(seed) &+ 1000)
        let ratio = [(1, 1), (3, 2), (2, 1)][Int(random.next() % 3)]
        let posted = Int.random(in: (50 * ratio.1 + ratio.0 - 1) / ratio.0...400 * ratio.1 / ratio.0,
                                using: &random)
        let moved = posted * ratio.0 / ratio.1
        let page = TerminalPage.repeating
        let run = try await Self.autoScroll(page, viewport: 600, posted: posted, moved: moved)
        #expect((50...400).contains(moved), "seed \(seed)")
        Self.expectExact(run, page: page)
    }
}

/// #112 on the issue's own page (1560 px region, 300 output lines), plus the original twelve seeds
/// on the 120-row repeating page (#140). Run with `make test-slow`.
@Suite("Auto-scroll on repetitive content, full pages", .tags(.slow))
struct AutoScrollStitchSlowTests {
    typealias Line = ScrollFixtures.Line

    // MARK: - The issue's fixture

    // #112: period-25 output, 120 pt auto-scroll step (240 px posted at 2x) that Terminal turns
    // into 360 px, 780 pt region at 2x. Before the fix: 16 and 8 lines between markers with no
    // seam, and blocks repeated after seams (1000 × 10252 px instead of the page's height).
    @Test func issueFixtureStitchesEveryRowOnce() async throws {
        let page = TerminalPage.issue
        let run = try await AutoScrollStitchTests.autoScroll(page, viewport: 1560, posted: 240, moved: 360)
        #expect(run.measuredScale == 1.5)
        #expect(!run.outcomes.contains(.ambiguous) && !run.outcomes.contains(.unrelated), "\(run.outcomes)")
        AutoScrollStitchTests.expectExact(run, page: page)

        // Each `== build n ==` marker comes out exactly once, 24 output lines after the one before.
        let stitched = run.lines.map(AutoScrollStitchTests.rowHash)
        var starts: [Int] = []
        for row in TerminalPage.markerRows {
            let block = page[row * 30..<(row + 1) * 30].map(AutoScrollStitchTests.rowHash)
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
        let run = try await AutoScrollStitchTests.autoScroll(page, viewport: 1560, posted: 240, moved: 360,
                                                             jumps: [frame: 1000])
        let source = page.map(AutoScrollStitchTests.rowHash)
        let seamRed = ScrollFixtures.pixel(230, 40, 40)
        let parts = run.lines.split { $0[0] == seamRed }.map { $0.map(AutoScrollStitchTests.rowHash) }
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

    @Test(arguments: 0..<12)
    func randomStepsStitchExactlyOnTheFullPage(seed: Int) async throws {
        var random = SeededGenerator(seed: UInt64(seed) &+ 1000)
        let ratio = [(1, 1), (3, 2), (2, 1)][Int(random.next() % 3)]
        let posted = Int.random(in: (50 * ratio.1 + ratio.0 - 1) / ratio.0...400 * ratio.1 / ratio.0,
                                using: &random)
        let moved = posted * ratio.0 / ratio.1
        let page = TerminalPage.repeatingFull
        let run = try await AutoScrollStitchTests.autoScroll(page, viewport: 600, posted: posted, moved: moved)
        #expect((50...400).contains(moved))
        AutoScrollStitchTests.expectExact(run, page: page)
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

    /// `unique` unique lines, `output` lines of period-25 output, `unique` unique lines; 400 px wide.
    static func repeating(unique: Int, output count: Int) -> [Line] {
        render(
            (0..<unique).map { "Session \($0): \($0 * 7919 % 1000) ok" } + output(1...count)
                + (0..<unique).map { "Summary \($0): \($0 * 104_729 % 1000)" },
            width: 400
        )
    }

    /// 20 + 50 + 20 lines (#140): each run of `$ make test` (24 lines, 720 px) still outlasts the
    /// 600 px region, so frames between markers see nothing else. Keep the 20 unique lines: with 10,
    /// steps near 385 px end in a seam (see the PR for #140).
    static let repeating: [Line] = repeating(unique: 20, output: 50)

    /// The original 20 + 80 + 20 lines, for the slow tier.
    static let repeatingFull: [Line] = repeating(unique: 20, output: 80)

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
