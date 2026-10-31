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

    // #98: only changed-or-not decides the end, not the stitcher's guess on repeating rows.
    @Test func stopRuleNeedsIdenticalFrames() {
        var rule = AutoScrollStopRule()
        #expect(rule.record(.started, frameChanged: true) == nil)
        #expect(rule.record(.noMovement, frameChanged: true) == nil) // looked still but pixels moved
        #expect(rule.record(.ambiguous, frameChanged: true) == nil)
        #expect(rule.record(.ambiguous, frameChanged: true) == nil)
        #expect(rule.record(.ambiguous, frameChanged: false) == nil)
        #expect(rule.record(.appended(lines: 0), frameChanged: true) == nil) // progress resets
        #expect(rule.record(.ambiguous, frameChanged: false) == nil)
        #expect(rule.record(.noMovement, frameChanged: false) == .endReached)
    }

    // #98: arming posts nothing, so the first frame is taken before anything moves.
    @Test func startPostsNothingUntilAdvance() async {
        let poster = FakePoster(trusted: true)
        let scroller = AutoScroller(step: 80, poster: poster)
        #expect(scroller.start(at: .zero) == .scrolling)
        await Task.yield()
        #expect(poster.posts.isEmpty)
        scroller.advance()
        scroller.nudge(by: -80)
        scroller.nudge(by: 80)
        scroller.advance()
        #expect(poster.posts == [80, -80, 80, 80])
        #expect(scroller.takePostedDistance() == 160) // probes don't count
        #expect(scroller.takePostedDistance() == 0)
        scroller.cancel()
        scroller.advance()
        #expect(poster.posts.count == 4)
    }

    @Test func needsAccessibilityWithoutPosting() async {
        let poster = FakePoster(trusted: false)
        let scroller = AutoScroller(poster: poster)
        #expect(scroller.start(at: .zero) == .needsAccessibility)
        await Task.yield()
        #expect(poster.posts.isEmpty)
    }

    @Test func stopsAtEndOfContent() {
        let scroller = AutoScroller(poster: FakePoster(trusted: true))
        #expect(scroller.start(at: .zero) == .scrolling)
        scroller.record(.appended(lines: 120))
        scroller.record(.noMovement)
        #expect(scroller.state == .scrolling)
        scroller.record(.noMovement)
        #expect(scroller.state == .stopped(.endReached))
    }

    @Test func stopsAtMaxLengthAndOnCancel() {
        let capped = AutoScroller(poster: FakePoster(trusted: true))
        capped.start(at: .zero)
        capped.record(.maxLengthReached)
        #expect(capped.state == .stopped(.maxLengthReached))

        let cancelled = AutoScroller(poster: FakePoster(trusted: true))
        cancelled.start(at: .zero)
        cancelled.cancel()
        #expect(cancelled.state == .stopped(.cancelled))
        cancelled.record(.noMovement) // ignored once stopped
        #expect(cancelled.state == .stopped(.cancelled))
    }
}
