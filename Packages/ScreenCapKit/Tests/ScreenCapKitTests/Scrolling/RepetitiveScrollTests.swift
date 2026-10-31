import CoreGraphics
@testable import ScreenCapKit
import Testing

/// The skeptic pass #2 cases (#70, #71) on rendered text: a 600 px region over 200 rows of 30 px.
/// Every stretch of the result between seam markers must be an exact, contiguous slice of the
/// page: a wrong offset on repeating rows shows up as a slice that exists nowhere on the page.
@Suite("Stitcher on repetitive text")
struct RepetitiveScrollTests {
    typealias Line = ScrollFixtures.Line

    struct Run {
        let outcomes: [Stitcher.AppendOutcome]
        let height: Int
        /// Stretches between seams, as lines.
        let segments: [[Line]]
        let seam: Int
    }

    /// Stitches the frames at `tops` like the harness (scale 2). `posted` feeds the auto-scroll
    /// distance before each frame, the way the controller does.
    private func run(_ page: CGImage, tops: [Int], posted: (Int, Int) -> Int? = { _, _ in nil },
                     usesVision: Bool) async throws -> Run {
        let stitcher = Stitcher(axis: .vertical, scale: 2, aligner: FrameAligner(usesVision: usesVision))
        var outcomes: [Stitcher.AppendOutcome] = []
        var previousTop = 0
        for top in tops {
            await stitcher.setExpectedStep(posted(previousTop, top))
            outcomes.append(await stitcher.append(frame: TextScrollFixtures.frame(page, at: top)))
            previousTop = top
        }
        let image = try #require(await stitcher.finish())
        let lines = ScrollFixtures.lines(of: image, axis: .vertical)
        let seamRed = ScrollFixtures.pixel(230, 40, 40)
        var segments: [[Line]] = [[]]
        for line in lines {
            if line[0] == seamRed {
                if !(segments.last ?? []).isEmpty { segments.append([]) }
            } else {
                segments[segments.count - 1].append(line)
            }
        }
        return Run(outcomes: outcomes, height: image.height, segments: segments, seam: await stitcher.seamThickness)
    }

    /// Where `segment` occurs on the page (all starts; repeating content can have several).
    private func starts(of segment: [Line], in page: [Line]) -> [Int] {
        guard let first = segment.first, segment.count <= page.count else { return [] }
        return (0...(page.count - segment.count)).filter { start in
            page[start] == first && Array(page[start..<start + segment.count]) == segment
        }
    }

    /// Checks every segment is a page slice, the first starts at the top and the last ends at
    /// the bottom of the last frame. `complete` also requires no seams (nothing missing).
    private func expectFaithful(_ run: Run, page image: CGImage, end: Int, complete: Bool,
                                sourceLocation: SourceLocation = #_sourceLocation) {
        let page = ScrollFixtures.lines(of: image, axis: .vertical)
        for (index, segment) in run.segments.enumerated() {
            let found = starts(of: segment, in: page)
            #expect(!found.isEmpty, "segment \(index) is not on the page: rows duplicated or dropped",
                    sourceLocation: sourceLocation)
            if index == 0 { #expect(found.contains(0), sourceLocation: sourceLocation) }
            if index == run.segments.count - 1 {
                #expect(found.contains(end - segment.count), "last segment doesn't end at \(end)",
                        sourceLocation: sourceLocation)
            }
        }
        if complete {
            #expect(run.segments.count == 1 && run.height == end, sourceLocation: sourceLocation)
        }
    }

    private static let even = TextScrollFixtures.positions(Array(repeating: 100, count: 30))

    // MARK: - #70 manual scrolling

    // Unique rows stitch exactly whatever the scroll pattern.
    @Test(arguments: [true, false])
    func uniqueRowsHandScroll(usesVision: Bool) async throws {
        let tops = TextScrollFixtures.handScroll
        let result = try await run(TextScrollFixtures.unique, tops: tops, usesVision: usesVision)
        expectFaithful(result, page: TextScrollFixtures.unique, end: 2219, complete: true)
    }

    // Terminal by hand at 100 px a frame: frames that share a unique line align exactly; frames
    // that see only `$ make test` rows are held and, if nothing lines them up, kept after a seam.
    // Before #70 this stitched 4710 px with 1264 wrong rows and no seam.
    @Test(arguments: [true, false])
    func terminalManualEvenSteps(usesVision: Bool) async throws {
        let result = try await run(TextScrollFixtures.terminal, tops: Self.even, usesVision: usesVision)
        #expect(result.height == 5016, "\(result.outcomes)")
        #expect(result.segments.count == 5)
        #expect(result.outcomes.contains(.ambiguous))
        expectFaithful(result, page: TextScrollFixtures.terminal, end: 3600, complete: false)
    }

    // Terminal, irregular hand scroll (was 2339 px, 208 wrong rows).
    @Test(arguments: [true, false])
    func terminalHandScroll(usesVision: Bool) async throws {
        let result = try await run(TextScrollFixtures.terminal, tops: TextScrollFixtures.handScroll,
                                   usesVision: usesVision)
        #expect(result.height == 3354, "\(result.outcomes)")
        expectFaithful(result, page: TextScrollFixtures.terminal, end: 2219, complete: false)
    }

    // A fully periodic table by hand can't be lined up at all: the first and last screens are
    // kept either side of a seam instead of a confident wrong length (was 1979 / 1259 px).
    @Test(arguments: [true, false])
    func tableHandScroll(usesVision: Bool) async throws {
        let result = try await run(TextScrollFixtures.table, tops: TextScrollFixtures.handScroll,
                                   usesVision: usesVision)
        #expect(result.outcomes.dropFirst().allSatisfy { $0 == .ambiguous }, "\(result.outcomes)")
        #expect(result.height == 600 + result.seam + 600)
        expectFaithful(result, page: TextScrollFixtures.table, end: 2219, complete: false)
    }

    // The same table at exactly 100 px a frame repeats every 600 px, so frames 6 apart are
    // pixel-identical and look like no movement. Nothing is guessed (was 7200 px).
    @Test func tableManualEvenStepsGuessesNothing() async throws {
        let result = try await run(TextScrollFixtures.table, tops: Self.even, usesVision: true)
        #expect(!result.outcomes.contains { if case .appended = $0 { true } else { false } })
        #expect(result.height == 600)
    }

    // MARK: - #70 auto-scroll

    // With the distance auto-scroll actually posted, repeating content stitches exactly.
    @Test(arguments: [true, false])
    func autoScrollUsesThePostedDistance(usesVision: Bool) async throws {
        for page in [TextScrollFixtures.terminal, TextScrollFixtures.table] {
            let result = try await run(page, tops: Self.even, posted: { $1 - $0 }, usesVision: usesVision)
            expectFaithful(result, page: page, end: 3600, complete: true)
        }
    }

    // The page moved 60/140 while 100 was posted: no candidate matches 100, so nothing is
    // trusted to it (was 3037 px, 2696 wrong rows). Frames that can't be placed follow a seam
    // from where the image ends, so rows may be missing at a seam but none repeat (#112; was
    // 2268 px, repeating what the 1600 px page had already shown after each seam).
    @Test(arguments: [true, false])
    func autoScrollDistanceThatDoesNotMatchIsIgnored(usesVision: Bool) async throws {
        let tops = TextScrollFixtures.positions([60, 140, 60, 140, 60, 140, 60, 140, 60, 140])
        let result = try await run(TextScrollFixtures.terminal, tops: tops, posted: { _, _ in 100 },
                                   usesVision: usesVision)
        #expect(result.height == 1098, "\(result.outcomes)")
        #expect(result.segments.reduce(0) { $0 + $1.count } <= 1600, "rows repeated after a seam")
        expectFaithful(result, page: TextScrollFixtures.terminal, end: 1600, complete: false)
    }

    // MARK: - #71 fast scrolling

    // 560 px steps leave 40 px of overlap: aligned at the found offset, no seams (was 2412 px).
    @Test(arguments: [true, false])
    func lowOverlapStitchesAtTheFoundOffset(usesVision: Bool) async throws {
        let tops = TextScrollFixtures.positions([560, 560, 560, 560])
        let result = try await run(TextScrollFixtures.unique, tops: tops, usesVision: usesVision)
        #expect(result.outcomes == [.started] + Array(repeating: .appended(lines: 560), count: 4))
        expectFaithful(result, page: TextScrollFixtures.unique, end: 2840, complete: true)
    }

    // The same steps over Terminal output can't be lined up; nothing is silently misaligned
    // (was 1760 px with offsets +410 +230 +410 +110).
    @Test(arguments: [true, false])
    func lowOverlapOnRepeatingRowsIsMarked(usesVision: Bool) async throws {
        let tops = TextScrollFixtures.positions([560, 560, 560, 560])
        let result = try await run(TextScrollFixtures.terminal, tops: tops, usesVision: usesVision)
        #expect(result.height == 1764, "\(result.outcomes)")
        expectFaithful(result, page: TextScrollFixtures.terminal, end: 2840, complete: false)
    }

    // A flick past the region, then Stop: the last screen is kept after a seam (was dropped).
    @Test(arguments: [true, false])
    func stopRightAfterAFlickKeepsTheLastScreen(usesVision: Bool) async throws {
        let tops = TextScrollFixtures.positions([100, 700])
        let result = try await run(TextScrollFixtures.unique, tops: tops, usesVision: usesVision)
        #expect(result.outcomes == [.started, .appended(lines: 100), .unrelated])
        #expect(result.height == 700 + result.seam + 600)
        #expect(result.segments.count == 2)
        expectFaithful(result, page: TextScrollFixtures.unique, end: 1400, complete: false)
    }

    // Flicks mid-capture keep every screen, each jump marked (the harness's "uniq fast 700").
    @Test(arguments: [true, false])
    func flicksKeepEveryScreen(usesVision: Bool) async throws {
        let tops = TextScrollFixtures.positions([700, 100, 100, 700, 100])
        let result = try await run(TextScrollFixtures.unique, tops: tops, usesVision: usesVision)
        #expect(result.height == 600 + 2 * result.seam + 800 + 700)
        expectFaithful(result, page: TextScrollFixtures.unique, end: 2300, complete: false)
    }
}
