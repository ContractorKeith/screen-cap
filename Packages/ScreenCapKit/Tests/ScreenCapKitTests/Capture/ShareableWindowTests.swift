import CoreGraphics
@testable import ScreenCapKit
import Testing

private func window(_ id: CGWindowID, _ frame: CGRect) -> ShareableWindow {
    ShareableWindow(
        id: id, frame: frame, title: "W\(id)", appName: "App", bundleIdentifier: "com.example.app",
        processID: 42, layer: 0
    )
}

@Suite("ShareableWindow")
struct ShareableWindowTests {
    @Test func ordersFrontToBackWithUnknownsLast() {
        let windows = [1, 2, 3, 4].map { window(CGWindowID($0), .zero) }
        let ordered = ShareableWindow.orderedFrontToBack(windows, zOrder: [3, 1, 99])
        #expect(ordered.map(\.id) == [3, 1, 2, 4])
    }

    @Test func topmostHitTest() {
        let front = window(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let back = window(2, CGRect(x: 50, y: 50, width: 200, height: 200))
        #expect(ShareableWindow.topmost(at: CGPoint(x: 75, y: 75), in: [front, back])?.id == 1)
        #expect(ShareableWindow.topmost(at: CGPoint(x: 150, y: 150), in: [front, back])?.id == 2)
        #expect(ShareableWindow.topmost(at: CGPoint(x: 400, y: 400), in: [front, back]) == nil)
    }
}
