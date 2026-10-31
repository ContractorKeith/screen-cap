import CoreGraphics
@testable import ScreenCapKit
import Testing

@Suite("FrameAligner and FixedEdgeDetector")
struct FrameAlignerTests {
    private let page = ScrollFixtures.page(length: 1200, breadth: 400, seed: 11)

    private func frame(at start: Int, length: Int = 600, axis: ScrollAxis = .vertical) -> CGImage {
        ScrollFixtures.image(lines: Array(page[start..<start + length]), axis: axis)
    }

    @Test func identicalFramesHaveNoMovement() {
        #expect(FrameAligner().align(previous: frame(at: 100), next: frame(at: 100), axis: .vertical) == .noMovement)
    }

    @Test(arguments: [true, false])
    func findsScrollOffset(usesVision: Bool) {
        let aligner = FrameAligner(usesVision: usesVision)
        #expect(aligner.align(previous: frame(at: 0), next: frame(at: 180), axis: .vertical) == .offset(180))
        #expect(aligner.align(previous: frame(at: 300), next: frame(at: 307), axis: .vertical) == .offset(7))
    }

    @Test func findsHorizontalOffset() {
        let previous = frame(at: 0, axis: .horizontal)
        let next = frame(at: 250, axis: .horizontal)
        #expect(FrameAligner().align(previous: previous, next: next, axis: .horizontal) == .offset(250))
    }

    @Test func unrelatedFramesAreUnrelated() {
        let other = ScrollFixtures.image(
            lines: ScrollFixtures.page(length: 600, breadth: 400, seed: 12), axis: .vertical
        )
        #expect(FrameAligner().align(previous: frame(at: 0), next: other, axis: .vertical) == .unrelated)
        let short = frame(at: 0, length: 500)
        #expect(FrameAligner().align(previous: frame(at: 0), next: short, axis: .vertical) == .unrelated)
    }

    @Test func detectsHeaderAndFooter() {
        let header = ScrollFixtures.bar(length: 40, breadth: 400, seed: 1)
        let footer = ScrollFixtures.bar(length: 30, breadth: 400, seed: 2)
        for axis in ScrollAxis.allCases {
            let frames = ScrollFixtures.frames(page: page, viewport: 600, header: header, footer: footer, step: 180)
                .map { ScrollFixtures.image(lines: $0, axis: axis) }
            #expect(FixedEdgeDetector.detect(frames: frames, axis: axis) == FixedEdges(leading: 40, trailing: 30))
        }
    }

    @Test func noEdgesWithoutEvidence() {
        #expect(FixedEdgeDetector.detect(frames: [frame(at: 0)], axis: .vertical) == .none)
        #expect(FixedEdgeDetector.detect(frames: [frame(at: 0), frame(at: 0)], axis: .vertical) == .none)
        #expect(FixedEdgeDetector.detect(frames: [frame(at: 0), frame(at: 90)], axis: .vertical) == .none)
    }
}
