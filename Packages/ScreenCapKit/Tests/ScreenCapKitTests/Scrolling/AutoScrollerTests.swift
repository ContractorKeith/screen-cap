import CoreGraphics
@testable import ScreenCapKit
import Testing

@MainActor
private final class FakePoster: ScrollEventPosting {
    var isTrusted: Bool
    private(set) var posts: [Int] = []
    init(trusted: Bool) { isTrusted = trusted }
    func postScroll(at point: CGPoint, axis: ScrollAxis, delta: Int) { posts.append(delta) }
}

@Suite("AutoScroller")
@MainActor
struct AutoScrollerTests {
    @Test func stopRule() {
        var rule = AutoScrollStopRule()
        #expect(rule.record(.started) == nil)
        #expect(rule.record(.noMovement) == nil)
        #expect(rule.record(.appended(lines: 120)) == nil)
        #expect(rule.record(.noMovement) == nil)
        #expect(rule.record(.unrelated) == nil)
        #expect(rule.record(.noMovement) == .endReached)
        var capped = AutoScrollStopRule()
        #expect(capped.record(.maxLengthReached) == .maxLengthReached)
    }

    @Test func needsAccessibilityWithoutPosting() async {
        let poster = FakePoster(trusted: false)
        let scroller = AutoScroller(poster: poster)
        #expect(scroller.start(at: .zero) == .needsAccessibility)
        await Task.yield()
        #expect(poster.posts.isEmpty)
    }

    @Test func stopsAtEndOfContent() {
        let scroller = AutoScroller(interval: .seconds(60), poster: FakePoster(trusted: true))
        #expect(scroller.start(at: .zero) == .scrolling)
        scroller.record(.appended(lines: 120))
        scroller.record(.noMovement)
        #expect(scroller.state == .scrolling)
        scroller.record(.noMovement)
        #expect(scroller.state == .stopped(.endReached))
    }

    @Test func stopsAtMaxLengthAndOnCancel() {
        let capped = AutoScroller(interval: .seconds(60), poster: FakePoster(trusted: true))
        capped.start(at: .zero)
        capped.record(.maxLengthReached)
        #expect(capped.state == .stopped(.maxLengthReached))

        let cancelled = AutoScroller(interval: .seconds(60), poster: FakePoster(trusted: true))
        cancelled.start(at: .zero)
        cancelled.cancel()
        #expect(cancelled.state == .stopped(.cancelled))
        cancelled.record(.noMovement) // ignored once stopped
        #expect(cancelled.state == .stopped(.cancelled))
    }
}
