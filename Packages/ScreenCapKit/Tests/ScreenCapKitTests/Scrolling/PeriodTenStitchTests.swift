import CoreGraphics
@testable import ScreenCapKit
import Testing

/// #126: period-10 Terminal output (`-- step n --` every 10th line) in a 330 pt region at 2x. Live,
/// this repeated blocks, dropped 20 lines with no seam and stopped early. Every step size must
/// stitch the page's rows exactly: the right height, each marker once, nothing dropped.
@Suite("Auto-scroll on period-10 output")
struct PeriodTenStitchTests {
    typealias Line = ScrollFixtures.Line

    /// The 660 px region of the issue (330 pt at 2x).
    static let viewport = 660

    /// Live dither: two low bits per channel, fixed to the screen.
    static let liveNoise: UInt32 = 0x0003_0303

    // (posted px per frame, page px moved per frame). 240 → 360 is the issue's run (120 pt step,
    // Terminal moves 1.5×); 200 → 300 moves exactly one period per frame; 330 is the largest step
    // a 330 pt region allows.
    @Test(arguments: [(240, 360), (120, 180), (200, 300), (240, 240), (330, 330), (160, 240), (100, 150)])
    func stitchesExactly(posted: Int, moved: Int) async throws {
        let page = TerminalPage.periodTen
        let run = try await AutoScrollStitchTests.autoScroll(page, viewport: Self.viewport, posted: posted,
                                                             moved: moved, noise: Self.liveNoise)
        AutoScrollStitchTests.expectExact(run, page: page)
        Self.expectEachMarkerOnce(run, page: page)
    }

    // Live, Terminal's overlay scroll knob sits inside the region's right edge: fixed on screen and
    // creeping a little every step, so with it in, no row matched its moved copy and no offset
    // lined up (the capture then ran on unplaced). The knob strip is left out of matching.
    @Test func scrollKnobAtTheEdgeIsIgnored() async throws {
        let page = TerminalPage.periodTen
        let run = try await AutoScrollStitchTests.autoScroll(page, viewport: Self.viewport, posted: 240, moved: 360,
                                                             noise: Self.liveNoise, knob: true)
        #expect(run.seams == 0, "\(run.outcomes)")
        #expect(run.lines.count == page.count)
        // The knob is kept in the image as drawn; compare the text left of it.
        let text = { (lines: [Line]) in lines.map { Array($0.prefix(900)) } }
        let trimmed = AutoScrollStitchTests.Run(outcomes: run.outcomes, lines: text(run.lines), seams: run.seams,
                                                measuredScale: run.measuredScale)
        Self.expectEachMarkerOnce(trimmed, page: text(page))
    }

    // Live Terminal doesn't always move a constant multiple of the posted step. Where a move other
    // than the measured step leaves only `ok` rows in the overlap, pixels can't place it: a seam is
    // marked there. Rows are never dropped silently nor repeated, and the capture reaches the end.
    @Test(arguments: [[360, 480], [360, 330, 390], [300, 360, 420, 360]])
    func unevenMovesNeverDropOrRepeatSilently(pattern: [Int]) async throws {
        let page = TerminalPage.periodTen
        let run = try await AutoScrollStitchTests.autoScroll(page, viewport: Self.viewport, posted: 240, moved: 360,
                                                             pattern: pattern, noise: Self.liveNoise)
        try Self.expectFaithful(run, page: page)
    }

    // A jump one period further than the measured step (180 + 300 px) lines up with the step's
    // offset everywhere but the marker rows. It must never be dropped silently: either stitched
    // exactly or marked with a seam.
    @Test(arguments: [9, 14, 20])
    func periodJumpIsSeamedNotDropped(frame: Int) async throws {
        let page = TerminalPage.periodTen
        let run = try await AutoScrollStitchTests.autoScroll(page, viewport: Self.viewport, posted: 120, moved: 180,
                                                             jumps: [frame: 480], noise: Self.liveNoise)
        try Self.expectFaithful(run, page: page)
    }

    /// No seam: exactly the page. Seams: each part is a later run of the page's rows, in order (no
    /// row repeats across a seam), and the last part ends where the page ends.
    static func expectFaithful(_ run: AutoScrollStitchTests.Run, page: [Line],
                               sourceLocation: SourceLocation = #_sourceLocation) throws {
        let source = page.map(AutoScrollStitchTests.rowHash)
        let seamRed = ScrollFixtures.pixel(230, 40, 40)
        let parts = run.lines.split { $0[0] == seamRed }.map { $0.map(AutoScrollStitchTests.rowHash) }
        if run.seams == 0 {
            #expect(parts.flatMap { $0 } == source, "no seam, so every row must be there exactly",
                    sourceLocation: sourceLocation)
            return
        }
        var cursor = 0
        for part in parts {
            let start = try #require((cursor...max(cursor, source.count - part.count)).first { start in
                start + part.count <= source.count && source[start..<start + part.count].elementsEqual(part)
            }, "a part after a seam isn't a later run of the page", sourceLocation: sourceLocation)
            cursor = start + part.count
        }
        #expect(cursor == source.count, "reaches the end of the page", sourceLocation: sourceLocation)
    }

    /// Each `-- step n --` row of the page occurs exactly once in the stitched image.
    static func expectEachMarkerOnce(_ run: AutoScrollStitchTests.Run, page: [Line],
                                     sourceLocation: SourceLocation = #_sourceLocation) {
        let stitched = run.lines.map(AutoScrollStitchTests.rowHash)
        let rows = TerminalPage.rowHeight
        for row in TerminalPage.periodTenMarkerRows {
            let block = page[row * rows..<(row + 1) * rows].map(AutoScrollStitchTests.rowHash)
            let found = stitched.indices.filter { start in
                stitched[start] == block[0] && start + rows <= stitched.count
                    && stitched[start..<start + rows].elementsEqual(block)
            }
            #expect(found.count == 1, "marker at row \(row) found \(found.count) times", sourceLocation: sourceLocation)
        }
    }
}

extension TerminalPage {
    /// Scrollback above the issue's command: blank lines left by `clear`.
    static let periodTenHeader = Array(repeating: "", count: 18)
        + ["~  v3.11.8",
           "> clear; for i in $(seq 1 400); do if (( i % 10 == 0 )); then echo \"-- step $i --\"; ",
           "else echo \"ok\"; fi; done"]

    /// The #126 page: the command, 400 lines of period-10 output, the prompt.
    static let periodTen: [Line] = render(
        periodTenHeader + (1...400).map { $0 % 10 == 0 ? "-- step \($0) --" : "ok" } + ["", "~  v3.11.8", "> "],
        width: 1000
    )

    /// Text rows of `periodTen` holding a `-- step n --` marker.
    static let periodTenMarkerRows: [Int] = (1...400).filter { $0 % 10 == 0 }.map { periodTenHeader.count + $0 - 1 }
}
