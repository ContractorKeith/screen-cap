import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("Path smoothing")
struct PathSmoothingTests {
    private let points = [CGPoint(x: 20, y: 100), CGPoint(x: 100, y: 20), CGPoint(x: 180, y: 100)]

    @Test func passesThroughEveryInputPoint() {
        let smoothed = PathSmoothing.catmullRom(points: points, samplesPerSegment: 8)
        #expect(smoothed.count == 1 + 2 * 8)
        #expect(smoothed[0] == points[0])
        #expect(smoothed[8] == points[1])
        #expect(smoothed[16] == points[2])
    }

    @Test func midpointMatchesTheSpline() {
        let smoothed = PathSmoothing.catmullRom(points: points, samplesPerSegment: 2)
        // First segment at t = 0.5 with the start point repeated as its own neighbor.
        #expect(abs(smoothed[1].x - 55) < 1e-9)
        #expect(abs(smoothed[1].y - 55) < 1e-9)
    }

    @Test func collinearPointsStayOnTheLine() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20), CGPoint(x: 30, y: 30)]
        for point in PathSmoothing.catmullRom(points: line) {
            #expect(abs(point.x - point.y) < 1e-9)
        }
    }

    @Test func shortInputIsUnchanged() {
        let two = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5)]
        #expect(PathSmoothing.catmullRom(points: two) == two)
        #expect(PathSmoothing.catmullRom(points: []).isEmpty)
    }
}
