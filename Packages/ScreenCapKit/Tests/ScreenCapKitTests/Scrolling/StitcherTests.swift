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
}
