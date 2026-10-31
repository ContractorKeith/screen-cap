import CoreGraphics
@testable import ScreenCap
import Testing

@Suite("SelectionMath")
struct SelectionMathTests {
    @Test func dragInAnyDirectionGivesTheSameRect() {
        let expected = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(SelectionMath.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 70)) == expected)
        #expect(SelectionMath.rect(from: CGPoint(x: 110, y: 70), to: CGPoint(x: 10, y: 20)) == expected)
        #expect(SelectionMath.rect(from: CGPoint(x: 10, y: 70), to: CGPoint(x: 110, y: 20)) == expected)
    }

    @Test func snapsToWholePoints() {
        let rect = SelectionMath.rect(from: CGPoint(x: 10.4, y: 20.6), to: CGPoint(x: 50.5, y: 60.2))
        #expect(rect == CGRect(x: 10, y: 21, width: 41, height: 39))
    }

    @Test func aspectLockFollowsTheLongerDrag() {
        let wide = SelectionMath.rect(from: .zero, to: CGPoint(x: 200, y: 10), aspect: 2)
        #expect(wide == CGRect(x: 0, y: 0, width: 200, height: 100))
        let tall = SelectionMath.rect(from: .zero, to: CGPoint(x: 10, y: 100), aspect: 1)
        #expect(tall == CGRect(x: 0, y: 0, width: 100, height: 100))
        let upLeft = SelectionMath.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 0, y: 90), aspect: 1)
        #expect(upLeft == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func fixedRectCentersAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 200, height: 100)
        #expect(SelectionMath.fixedRect(size: size, centeredAt: CGPoint(x: 500, y: 400), within: screen)
            == CGRect(x: 400, y: 350, width: 200, height: 100))
        #expect(SelectionMath.fixedRect(size: size, centeredAt: CGPoint(x: 990, y: 5), within: screen)
            == CGRect(x: 800, y: 0, width: 200, height: 100))
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        #expect(SelectionMath.fixedRect(size: size, centeredAt: CGPoint(x: -1430, y: 895), within: left)
            == CGRect(x: -1440, y: 800, width: 200, height: 100))
    }

    @Test func tinyDragsAreClicks() {
        #expect(!SelectionMath.isSelection(nil))
        #expect(!SelectionMath.isSelection(CGRect(x: 0, y: 0, width: 3, height: 100)))
        #expect(SelectionMath.isSelection(CGRect(x: 0, y: 0, width: 4, height: 4)))
    }

    @Test(arguments: [
        ("800x600", CGSize(width: 800, height: 600)),
        ("800 × 600", CGSize(width: 800, height: 600)),
        (" 1280 X 720 ", CGSize(width: 1280, height: 720)),
        ("640,480", CGSize(width: 640, height: 480))
    ])
    func parsesTypedSizes(text: String, expected: CGSize) {
        #expect(SelectionMath.parseSize(text) == expected)
    }

    @Test(arguments: ["", "800", "0x600", "axb", "1x2x3", "-5x10"])
    func rejectsBadSizes(text: String) {
        #expect(SelectionMath.parseSize(text) == nil)
    }

    @Test func labels() {
        #expect(SelectionMath.sizeLabel(CGSize(width: 800, height: 600)) == "800 × 600")
        #expect(SelectionMath.hex(red: 255, green: 0, blue: 171) == "#FF00AB")
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(SelectionMath.localTopLeft(CGPoint(x: 10.7, y: 972.2), in: display) == CGPoint(x: 10, y: 9))
    }
}
