import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Quick Access layout")
struct QuickAccessLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let panel = CGSize(width: 200, height: 150)
    let margin = QuickAccessLayout.margin
    let spacing = QuickAccessLayout.spacing

    @Test func bottomLeftStacksUpwardNewestAtCorner() {
        let frames = QuickAccessLayout.frames(for: [panel, panel, panel], corner: .bottomLeft, in: screen)
        #expect(frames.map(\.minX) == [margin, margin, margin])
        #expect(frames.map(\.minY) == [margin, margin + 162, margin + 324])
    }

    @Test func bottomRightAlignsToRightEdge() {
        let frames = QuickAccessLayout.frames(for: [panel, panel], corner: .bottomRight, in: screen)
        #expect(frames.map(\.maxX) == [1440 - margin, 1440 - margin])
        #expect(frames.map(\.minY) == [margin, margin + 150 + spacing])
    }

    @Test func topCornersStackDownward() {
        let left = QuickAccessLayout.frames(for: [panel, panel], corner: .topLeft, in: screen)
        #expect(left.map(\.maxY) == [900 - margin, 900 - margin - 150 - spacing])
        #expect(left.map(\.minX) == [margin, margin])
        let right = QuickAccessLayout.frames(for: [panel], corner: .topRight, in: screen)
        #expect(right == [CGRect(x: 1440 - margin - 200, y: 900 - margin - 150, width: 200, height: 150)])
    }

    @Test func respectsScreenOrigin() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let frames = QuickAccessLayout.frames(for: [panel], corner: .bottomLeft, in: second)
        #expect(frames == [CGRect(x: 1440 + margin, y: -200 + margin, width: 200, height: 150)])
    }

    @Test func overflowWrapsIntoNextColumn() {
        // 900 high fits 5 panels of 150 + 12 (16 + 5 * 162 - 12 = 814 <= 884); the 6th wraps.
        let frames = QuickAccessLayout.frames(for: Array(repeating: panel, count: 6), corner: .bottomRight, in: screen)
        #expect(frames[4].minX == 1440 - margin - 200)
        #expect(frames[5].minX == 1440 - margin - 200 - spacing - 200)
        #expect(frames[5].minY == margin)
    }

    @Test func panelSizeFollowsAspectWithClamps() {
        let wide = QuickAccessLayout.thumbnailSize(imageSize: CGSize(width: 2880, height: 1800), size: .medium)
        #expect(wide == CGSize(width: 240, height: 150))
        let banner = QuickAccessLayout.thumbnailSize(imageSize: CGSize(width: 4000, height: 100), size: .small)
        #expect(banner.height == 90)
        let tall = QuickAccessLayout.thumbnailSize(imageSize: CGSize(width: 800, height: 8000), size: .large)
        #expect(tall.height == 400)
        let full = QuickAccessLayout.panelSize(imageSize: CGSize(width: 2880, height: 1800), size: .medium)
        #expect(full.width == 240 + 2 * QuickAccessLayout.padding)
        #expect(full.height == 150 + 2 * QuickAccessLayout.padding + QuickAccessLayout.infoHeight)
    }

    @Test func entryFrameStartsPastTheSideEdge() {
        let frame = CGRect(x: 16, y: 16, width: 200, height: 150)
        #expect(QuickAccessLayout.entryFrame(for: frame, corner: .bottomLeft).maxX <= 0)
        let right = CGRect(x: 1224, y: 16, width: 200, height: 150)
        #expect(QuickAccessLayout.entryFrame(for: right, corner: .topRight).minX >= 1440)
    }
}

@Suite("Quick Access swipes")
struct SwipeClassifierTests {
    @Test(arguments: [ScreenCorner.bottomLeft, .topLeft])
    func leftCorners(corner: ScreenCorner) {
        #expect(SwipeClassifier.action(fingerDX: -80, fingerDY: 5, corner: corner) == .save)
        #expect(SwipeClassifier.action(fingerDX: 80, fingerDY: 5, corner: corner) == .dismiss)
    }

    @Test(arguments: [ScreenCorner.bottomRight, .topRight])
    func rightCorners(corner: ScreenCorner) {
        #expect(SwipeClassifier.action(fingerDX: 80, fingerDY: 0, corner: corner) == .save)
        #expect(SwipeClassifier.action(fingerDX: -80, fingerDY: 0, corner: corner) == .dismiss)
    }

    @Test func shortOrVerticalSwipesDoNothing() {
        #expect(SwipeClassifier.action(fingerDX: 30, fingerDY: 0, corner: .bottomLeft) == nil)
        #expect(SwipeClassifier.action(fingerDX: 90, fingerDY: 120, corner: .bottomLeft) == nil)
    }

    @Test func fingerDeltaUndoesScrollDirection() {
        #expect(SwipeClassifier.fingerDelta(10, invertedFromDevice: true) == 10)
        #expect(SwipeClassifier.fingerDelta(10, invertedFromDevice: false) == -10)
    }

    @Test func trackerAccumulates() {
        var tracker = SwipeTracker()
        for _ in 0..<4 { tracker.add(dx: 20, dy: 1) }
        #expect(tracker.dx == 80)
        #expect(tracker.action(for: .bottomRight) == .save)
        #expect(tracker.action(for: .bottomLeft) == .dismiss)
    }
}

@Suite("Quick Access auto-close")
struct AutoCloseTimerTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func expiresAfterDuration() {
        let timer = AutoCloseTimer(seconds: 5, now: start)
        #expect(timer.remaining(at: start.addingTimeInterval(2)) == 3)
        #expect(!timer.isExpired(at: start.addingTimeInterval(4.9)))
        #expect(timer.isExpired(at: start.addingTimeInterval(5)))
    }

    @Test func neverWithoutDuration() {
        let timer = AutoCloseTimer(seconds: nil, now: start)
        #expect(timer.remaining(at: start) == nil)
        #expect(!timer.isExpired(at: start.addingTimeInterval(10_000)))
    }

    @Test func pauseFreezesRemainingTime() {
        var timer = AutoCloseTimer(seconds: 10, now: start)
        timer.pause(at: start.addingTimeInterval(4))
        #expect(timer.isPaused)
        #expect(timer.remaining(at: start.addingTimeInterval(100)) == 6)
        #expect(!timer.isExpired(at: start.addingTimeInterval(100)))
        timer.resume(at: start.addingTimeInterval(100))
        #expect(timer.remaining(at: start.addingTimeInterval(103)) == 3)
        #expect(timer.isExpired(at: start.addingTimeInterval(106)))
    }

    @Test func repeatedPauseAndResumeAreIgnored() {
        var timer = AutoCloseTimer(seconds: 10, now: start)
        timer.resume(at: start.addingTimeInterval(5))
        timer.pause(at: start.addingTimeInterval(2))
        timer.pause(at: start.addingTimeInterval(8))
        #expect(timer.remaining(at: start.addingTimeInterval(50)) == 8)
    }

    @Test func restartResetsToFullLength() {
        var timer = AutoCloseTimer(seconds: 5, now: start)
        timer.restart(at: start.addingTimeInterval(4))
        #expect(timer.remaining(at: start.addingTimeInterval(4)) == 5)
    }
}
