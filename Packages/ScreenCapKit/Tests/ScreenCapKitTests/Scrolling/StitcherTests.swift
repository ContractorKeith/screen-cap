import CoreGraphics
@testable import ScreenCapKit
import Testing

@Suite("Stitcher")
struct StitcherTests {
    struct Scenario {
        var axis: ScrollAxis = .vertical
        var breadth = 400
        var length = 3000
        var viewport = 600
        var header = 40
        var footer = 0
        var step = 180
        var scale: CGFloat = 1
    }

    /// Stitches the scenario's frames and checks the result line by line against the page.
    private func stitchAndCompare(_ scenario: Scenario) async throws {
        let page = ScrollFixtures.page(length: scenario.length, breadth: scenario.breadth, seed: 42)
        let header = ScrollFixtures.bar(length: scenario.header, breadth: scenario.breadth, seed: 7)
        let footer = ScrollFixtures.bar(length: scenario.footer, breadth: scenario.breadth, seed: 9)
        let frames = ScrollFixtures.frames(
            page: page, viewport: scenario.viewport, header: header, footer: footer, step: scenario.step
        )
        let stitcher = Stitcher(axis: scenario.axis, scale: scenario.scale)
        var outcomes: [Stitcher.AppendOutcome] = []
        for frame in frames {
            outcomes.append(await stitcher.append(frame: ScrollFixtures.image(lines: frame, axis: scenario.axis)))
        }
        #expect(outcomes.first == .started)
        #expect(outcomes.dropFirst().allSatisfy { if case .appended = $0 { true } else { false } })
        #expect(await stitcher.fixedEdges == FixedEdges(leading: scenario.header, trailing: scenario.footer))
        #expect(await stitcher.scale == scenario.scale)

        let image = try #require(await stitcher.finish())
        let expected = header + page + footer
        let length = scenario.axis == .vertical ? image.height : image.width
        let breadth = scenario.axis == .vertical ? image.width : image.height
        #expect(abs(length - expected.count) <= 2)
        #expect(breadth == scenario.breadth)
        let result = ScrollFixtures.lines(of: image, axis: scenario.axis)
        // Every line in order: no duplicated or missing bands, header once, footer once.
        let mismatches = zip(result, expected).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        #expect(mismatches.isEmpty, "first mismatched lines: \(mismatches.prefix(5))")
    }

    @Test func verticalWithStickyHeader() async throws {
        try await stitchAndCompare(Scenario())
    }

    @Test func horizontalWithStickySidebar() async throws {
        try await stitchAndCompare(Scenario(axis: .horizontal))
    }

    @Test func retinaScale() async throws {
        try await stitchAndCompare(
            Scenario(breadth: 800, length: 6000, viewport: 1200, header: 80, step: 360, scale: 2)
        )
    }

    @Test func headerAndFooterKeptOnce() async throws {
        try await stitchAndCompare(Scenario(footer: 30))
    }

    @Test func dropsStillFramesAndUnrelatedFrames() async throws {
        let page = ScrollFixtures.page(length: 1500, breadth: 300, seed: 3)
        let frames = ScrollFixtures.frames(page: page, viewport: 500, header: [], footer: [], step: 150)
            .map { ScrollFixtures.image(lines: $0, axis: .vertical) }
        let noise = ScrollFixtures.image(
            lines: ScrollFixtures.page(length: 500, breadth: 300, seed: 99), axis: .vertical
        )
        let stitcher = Stitcher()
        #expect(await stitcher.append(frame: frames[0]) == .started)
        #expect(await stitcher.append(frame: frames[0]) == .noMovement)
        #expect(await stitcher.append(frame: noise) == .unrelated)
        for frame in frames.dropFirst() { await stitcher.append(frame: frame) }
        #expect(await stitcher.append(frame: try #require(frames.last)) == .noMovement)
        let image = try #require(await stitcher.finish())
        #expect(ScrollFixtures.lines(of: image, axis: .vertical) == page)
    }

    @Test func capsAtMaxLength() async throws {
        let page = ScrollFixtures.page(length: 3000, breadth: 200, seed: 5)
        let frames = ScrollFixtures.frames(page: page, viewport: 600, header: [], footer: [], step: 200)
        let stitcher = Stitcher(maxLength: 1000)
        var outcomes: [Stitcher.AppendOutcome] = []
        for frame in frames {
            outcomes.append(await stitcher.append(frame: ScrollFixtures.image(lines: frame, axis: .vertical)))
        }
        #expect(outcomes.contains(.maxLengthReached))
        #expect(outcomes.last == .maxLengthReached)
        let image = try #require(await stitcher.finish())
        #expect(image.height == 1000)
        #expect(ScrollFixtures.lines(of: image, axis: .vertical) == Array(page.prefix(1000)))
    }

    @Test func previewAndReset() async throws {
        let page = ScrollFixtures.page(length: 900, breadth: 200, seed: 8)
        let frames = ScrollFixtures.frames(page: page, viewport: 400, header: [], footer: [], step: 150)
            .map { ScrollFixtures.image(lines: $0, axis: .vertical) }
        let stitcher = Stitcher()
        #expect(await stitcher.currentImage() == nil)
        await stitcher.append(frame: frames[0])
        #expect(await stitcher.currentImage()?.height == 400)
        await stitcher.append(frame: frames[1])
        #expect(await stitcher.currentImage()?.height == 550)
        await stitcher.reset()
        #expect(await stitcher.currentImage() == nil)
        #expect(await stitcher.append(frame: frames[1]) == .started)
    }

    /// Stitches `frames` and returns the outcomes and the final image.
    private func stitch(_ frames: [[ScrollFixtures.Line]], stitcher: Stitcher) async throws
        -> (outcomes: [Stitcher.AppendOutcome], image: CGImage) {
        var outcomes: [Stitcher.AppendOutcome] = []
        for frame in frames {
            outcomes.append(await stitcher.append(frame: ScrollFixtures.image(lines: frame, axis: .vertical)))
        }
        return (outcomes, try #require(await stitcher.finish()))
    }

    // Issue #44: a 300 px region with a 40 px header and a 30 px footer, scrolled 190 px per
    // frame. Only 40 lines of the 230-line moving band overlap; that must still stitch.
    @Test(arguments: [true, false])
    func fastScrollWithLittleOverlap(usesVision: Bool) async throws {
        let page = ScrollFixtures.page(length: 1750, breadth: 300, seed: 44)
        let header = ScrollFixtures.bar(length: 40, breadth: 300, seed: 7)
        let footer = ScrollFixtures.bar(length: 30, breadth: 300, seed: 9)
        let frames = ScrollFixtures.frames(page: page, viewport: 300, header: header, footer: footer, step: 190)
        let stitcher = Stitcher(aligner: FrameAligner(usesVision: usesVision))
        let (outcomes, image) = try await stitch(frames, stitcher: stitcher)
        #expect(outcomes.dropFirst().allSatisfy { if case .appended = $0 { true } else { false } }, "\(outcomes)")
        #expect(image.height == 1820)
        #expect(ScrollFixtures.lines(of: image, axis: .vertical) == header + page + footer)
    }

    // Issue #44: steps larger than the moving band leave no overlap at all. The stitcher must
    // keep going, marking each gap with a seam, instead of freezing on the first frame.
    @Test func scrollPastTheRegionMarksGapsAndContinues() async throws {
        let page = ScrollFixtures.page(length: 1500, breadth: 300, seed: 45)
        let header = ScrollFixtures.bar(length: 40, breadth: 300, seed: 7)
        // Bars open with blank lines; a gap only trusts edges up to their detail, so flip the footer.
        let footer = Array(ScrollFixtures.bar(length: 30, breadth: 300, seed: 9).reversed())
        var frames = ScrollFixtures.frames(page: page, viewport: 300, header: header, footer: footer, step: 260)
        frames.append(try #require(frames.last)) // the end of the page: a still frame
        let stitcher = Stitcher()
        let (outcomes, image) = try await stitch(frames, stitcher: stitcher)
        let gaps = outcomes.filter { if case .gapDetected = $0 { true } else { false } }
        #expect(gaps.count == frames.count - 2, "\(outcomes)")
        let seam = await stitcher.seamThickness
        // Header + first band, then a seam and a full band per later frame, then the footer.
        #expect(image.height == 40 + 230 + (frames.count - 2) * (seam + 230) + 30)
        let lines = ScrollFixtures.lines(of: image, axis: .vertical)
        #expect(Array(lines[0..<270]) == header + page[0..<230])
        #expect(lines[270] != lines[269] && lines[270][0] != lines[270][lines[270].count / 2]) // dashed seam
        #expect(Array(lines[(270 + seam)..<(500 + seam)]) == Array(page[260..<490]))
        #expect(Array(lines.suffix(30)) == footer)
    }

    // Issue #44: a single flick past the region, then normal scrolling, recovers.
    @Test func recoversAfterOneFlick() async throws {
        let page = ScrollFixtures.page(length: 2000, breadth: 300, seed: 46)
        let all = ScrollFixtures.frames(page: page, viewport: 300, header: [], footer: [], step: 100)
        // Frames at 0, 100, then a jump to 500, then 600, 700, ... to the end.
        let frames = Array(all[0...1]) + Array(all[5...])
        let stitcher = Stitcher(aligner: FrameAligner(usesVision: false))
        let (outcomes, image) = try await stitch(frames, stitcher: stitcher)
        #expect(outcomes[2] == .unrelated)
        #expect(outcomes[3] == .gapDetected(lines: await stitcher.seamThickness + 300 + 100), "\(outcomes)")
        #expect(outcomes.dropFirst(4).allSatisfy { if case .appended = $0 { true } else { false } })
        let seam = await stitcher.seamThickness
        #expect(image.height == 400 + seam + 1500)
        let lines = ScrollFixtures.lines(of: image, axis: .vertical)
        #expect(Array(lines[0..<400]) == Array(page[0..<400]))
        #expect(Array(lines[(400 + seam)...]) == Array(page[500...]))
    }

    // A gap's frame shares blank space with the first frame only by chance (a cleared Terminal
    // filling in): that must not be taken for a fixed header or footer.
    @Test func gapFramesDoNotDefineFixedEdges() async throws {
        let blank = ScrollFixtures.Line(repeating: ScrollFixtures.pixel(30, 30, 30), count: 200)
        let page = ScrollFixtures.page(length: 2000, breadth: 200, seed: 47)
        let empty = Array(repeating: blank, count: 400)
        let filling = Array(repeating: blank, count: 150) + Array(page[0..<100]) + Array(repeating: blank, count: 150)
        let stitcher = Stitcher(aligner: FrameAligner(usesVision: false))
        let image = { (lines: [ScrollFixtures.Line]) in ScrollFixtures.image(lines: lines, axis: .vertical) }
        #expect(await stitcher.append(frame: image(empty)) == .started)
        #expect(await stitcher.append(frame: image(filling)) == .unrelated)
        // The filling frame is kept after a seam; the scrolled frame is held in turn.
        #expect(await stitcher.append(frame: image(Array(page[300..<700]))) == .gapDetected(lines: 2 + 400))
        #expect(await stitcher.fixedEdges == .none)
        #expect(await stitcher.append(frame: image(Array(page[400..<800]))) == .gapDetected(lines: 2 + 400 + 100))
        #expect(await stitcher.append(frame: image(Array(page[500..<900]))) == .appended(lines: 100))
        #expect(await stitcher.fixedEdges == .none)
    }

    // Issue #45: 80 table rows with a rule every 4th row repeat every 75 lines. Scrolled 100 px a
    // frame, offsets 25, 100, 175 and 250 match equally; the auto-scroll step must pick 100.
    @Test(arguments: [true, false])
    func repetitiveTableStitchesToFullLength(usesVision: Bool) async throws {
        let page = ScrollFixtures.repetitiveList(rows: 80, length: 1500, breadth: 300, ruleEvery: 4)
        let frames = ScrollFixtures.frames(page: page, viewport: 300, header: [], footer: [], step: 100)
        let stitcher = Stitcher(aligner: FrameAligner(usesVision: usesVision))
        await stitcher.setExpectedStep(100)
        let (outcomes, image) = try await stitch(frames, stitcher: stitcher)
        #expect(outcomes.dropFirst().allSatisfy { $0 == .appended(lines: 100) }, "\(outcomes)")
        #expect(image.height == 1500)
        #expect(ScrollFixtures.lines(of: image, axis: .vertical) == page)
    }

    // Issue #45: 80 identical rows (a repeated log line) must not duplicate or drop rows.
    @Test(arguments: [true, false])
    func identicalRowsStitchToFullLength(usesVision: Bool) async throws {
        let page = ScrollFixtures.repetitiveList(rows: 80, length: 1500, breadth: 300)
        let frames = ScrollFixtures.frames(page: page, viewport: 300, header: [], footer: [], step: 100)
        let stitcher = Stitcher(aligner: FrameAligner(usesVision: usesVision))
        await stitcher.setExpectedStep(100)
        let (outcomes, image) = try await stitch(frames, stitcher: stitcher)
        #expect(outcomes.dropFirst().allSatisfy { $0 == .appended(lines: 100) }, "\(outcomes)")
        #expect(image.height == 1500)
        #expect(ScrollFixtures.lines(of: image, axis: .vertical) == page)
    }

    // Manual scrolling on repetitive content: the previous step breaks the tie once known.
    @Test func repetitiveContentFollowsThePreviousStep() async throws {
        let page = ScrollFixtures.repetitiveList(rows: 80, length: 1500, breadth: 300, ruleEvery: 4)
        let frames = ScrollFixtures.frames(page: page, viewport: 300, header: [], footer: [], step: 100)
        let aligner = FrameAligner(usesVision: false)
        let previous = ScrollFixtures.image(lines: frames[1], axis: .vertical)
        let next = ScrollFixtures.image(lines: frames[2], axis: .vertical)
        #expect(aligner.align(previous: previous, next: next, axis: .vertical,
                              prior: .init(previousStep: 96)) == .offset(100))
        #expect(aligner.align(previous: previous, next: next, axis: .vertical,
                              prior: .init(expectedStep: 100)) == .offset(100))
    }
}
