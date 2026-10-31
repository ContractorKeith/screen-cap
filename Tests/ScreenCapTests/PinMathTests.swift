import CoreGraphics
@testable import ScreenCap
import Testing

@Suite("Pin math")
struct PinMathTests {
    let image = CGSize(width: 400, height: 200)

    @Test func edgeDragKeepsAspect() {
        // Dragging the right edge: width leads.
        let wider = PinMath.aspectResize(current: image, proposed: CGSize(width: 600, height: 200), pointSize: image)
        #expect(wider == CGSize(width: 600, height: 300))
        // Dragging the bottom edge: height leads.
        let taller = PinMath.aspectResize(current: image, proposed: CGSize(width: 400, height: 100), pointSize: image)
        #expect(taller == CGSize(width: 200, height: 100))
    }

    @Test func resizeNeverCollapses() {
        let tiny = PinMath.aspectResize(current: image, proposed: CGSize(width: 2, height: 200), pointSize: image)
        #expect(tiny.height >= PinMath.minimumEdge)
        #expect(tiny.width / tiny.height == 2)
    }

    @Test func zoomStepsAndClamps() {
        #expect(PinMath.zoomed(1, steps: 1, pointSize: image) == 1.25)
        #expect(PinMath.zoomed(1.25, steps: -1, pointSize: image) == 1)
        #expect(PinMath.zoomed(7, steps: 3, pointSize: image) == PinMath.scaleRange.upperBound)
        // 200 pt short side: 40 pt minimum edge means 0.2x is the floor.
        #expect(PinMath.zoomed(0.25, steps: -5, pointSize: image) == 0.2)
    }

    @Test func fitAndDoubleClick() {
        let screen = CGSize(width: 1000, height: 1000)
        #expect(PinMath.fitScale(pointSize: image, visibleFrame: screen) == 1)
        let big = CGSize(width: 2000, height: 1000)
        #expect(PinMath.fitScale(pointSize: big, visibleFrame: screen) == 0.45)
        #expect(PinMath.doubleClickScale(current: 0.45, fitScale: 0.45) == 1)
        #expect(PinMath.doubleClickScale(current: 1, fitScale: 0.45) == 0.45)
        #expect(PinMath.doubleClickScale(current: 1, fitScale: 1) == 0.5)
        #expect(PinMath.doubleClickScale(current: 2.5, fitScale: 1) == 1)
    }

    @Test func opacityStepsAndClamps() {
        #expect(PinMath.opacity(1, steps: -1) == 0.9)
        #expect(PinMath.opacity(0.9, steps: 1) == 1)
        #expect(PinMath.opacity(1, steps: 1) == 1)
        #expect(PinMath.opacity(0.1, steps: -1) == 0.1)
        #expect(PinMath.opacity(0.2, steps: -5) == 0.1)
        // Off-grid values (e.g. from a fade) snap to tenths.
        #expect(PinMath.opacity(0.53, steps: 1) == 0.6)
        var value = 1.0
        for _ in 0..<12 { value = PinMath.opacity(value, steps: -1) }
        #expect(value == 0.1)
    }

    @Test func nudgeDistances() {
        #expect(PinMath.nudge(.left, shift: false) == CGVector(dx: -1, dy: 0))
        #expect(PinMath.nudge(.up, shift: true) == CGVector(dx: 0, dy: 10))
        #expect(PinMath.nudge(.down, shift: true) == CGVector(dx: 0, dy: -10))
    }
}

@Suite("Pin lock mode")
struct PinLockStateTests {
    @Test func lockMakesClickThrough() {
        let locked = PinLockState.interactive.handling(.toggleLock)
        #expect(locked == .locked)
        #expect(locked.ignoresMouseEvents)
        #expect(locked.showsLockBorder)
        #expect(!locked.acceptsKeyboard)
        let interactive = PinLockState.interactive
        #expect(!interactive.ignoresMouseEvents && !interactive.showsLockBorder && interactive.acceptsKeyboard)
    }

    @Test func unlockPaths() {
        #expect(PinLockState.locked.handling(.unlockAll) == .interactive)
        #expect(PinLockState.locked.handling(.toggleLock) == .interactive)
        #expect(PinLockState.interactive.handling(.unlockAll) == .interactive)
    }

    @Test func closedIsFinal() {
        #expect(PinLockState.locked.handling(.close) == .closed)
        #expect(PinLockState.interactive.handling(.close) == .closed)
        for event in [PinLockState.Event.toggleLock, .unlockAll, .close] {
            #expect(PinLockState.closed.handling(event) == .closed)
        }
        #expect(!PinLockState.closed.ignoresMouseEvents)
    }
}
