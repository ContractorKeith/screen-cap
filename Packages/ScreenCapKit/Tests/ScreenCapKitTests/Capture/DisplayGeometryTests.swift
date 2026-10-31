import CoreGraphics
@testable import ScreenCapKit
import Testing

// Layouts use AppKit global points: primary display at origin, y up.
private let retina = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), backingScale: 2)

@Suite("DisplayGeometry")
struct DisplayGeometryTests {
    @Test func singleRetina() {
        let geometry = DisplayGeometry(displays: [retina])
        #expect(retina.pixelSize == CGSize(width: 3024, height: 1964))
        #expect(retina.pixelRect(forGlobalPoints: retina.frame) == CGRect(x: 0, y: 0, width: 3024, height: 1964))

        // 100 pt from the left, 82 pt from the bottom: top edge is 982 - 182 = 800 pt down.
        let rect = CGRect(x: 100, y: 82, width: 200, height: 100)
        #expect(retina.pixelRect(forGlobalPoints: rect) == CGRect(x: 200, y: 1600, width: 400, height: 200))
        #expect(retina.globalPointRect(forPixelRect: CGRect(x: 200, y: 1600, width: 400, height: 200)) == rect)
        #expect(retina.pixelPoint(forGlobalPoint: CGPoint(x: 0, y: 982)) == .zero)

        let slices = geometry.slices(forGlobalPoints: rect)
        #expect(slices.count == 1)
        #expect(slices.first?.pixelRect == CGRect(x: 200, y: 1600, width: 400, height: 200))
        #expect(geometry.primaryDisplay == retina)
        #expect(geometry.slices(forGlobalPoints: CGRect(x: 2000, y: 0, width: 10, height: 10)).isEmpty)
    }

    @Test func retinaPlusStandardExternalToTheRight() {
        let external = DisplayInfo(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), backingScale: 1)
        let geometry = DisplayGeometry(displays: [retina, external])

        let spanning = CGRect(x: 1412, y: 500, width: 200, height: 100)
        let slices = geometry.slices(forGlobalPoints: spanning)
        #expect(slices.map(\.display.id) == [1, 2])
        #expect(slices[0].pointRect == CGRect(x: 1412, y: 500, width: 100, height: 100))
        #expect(slices[0].pixelRect == CGRect(x: 2824, y: 764, width: 200, height: 200))
        #expect(slices[1].pointRect == CGRect(x: 1512, y: 500, width: 100, height: 100))
        #expect(slices[1].pixelRect == CGRect(x: 0, y: 480, width: 100, height: 100))

        // Shared edge belongs to the display on the right (half-open frames).
        #expect(geometry.display(containing: CGPoint(x: 1511.5, y: 10))?.id == 1)
        #expect(geometry.display(containing: CGPoint(x: 1512, y: 10))?.id == 2)
        #expect(geometry.display(bestFor: CGRect(x: 1500, y: 0, width: 100, height: 10))?.id == 2)
        #expect(geometry.unionFrame == CGRect(x: 0, y: 0, width: 3432, height: 1080))
    }

    @Test func externalAbove() {
        let external = DisplayInfo(id: 2, frame: CGRect(x: -204, y: 982, width: 1920, height: 1080), backingScale: 1)
        let geometry = DisplayGeometry(displays: [retina, external])

        #expect(geometry.display(containing: CGPoint(x: 0, y: 1000))?.id == 2)
        #expect(external.pixelPoint(forGlobalPoint: CGPoint(x: 0, y: 1000)) == CGPoint(x: 204, y: 1062))

        // In Quartz space (y down from the primary's top) the display above sits at negative y.
        let quartz = CGRect(x: -204, y: -1080, width: 1920, height: 1080)
        #expect(geometry.appKitRect(fromQuartz: quartz) == external.frame)
        #expect(geometry.quartzRect(fromAppKit: external.frame) == quartz)
        #expect(geometry.quartzRect(fromAppKit: retina.frame) == retina.frame)

        let window = CGRect(x: 100, y: 900, width: 300, height: 200) // straddles the seam
        let slices = geometry.slices(forGlobalPoints: window)
        #expect(slices[0].pixelRect == CGRect(x: 200, y: 0, width: 600, height: 164))
        #expect(slices[1].pixelRect == CGRect(x: 304, y: 962, width: 300, height: 118))
    }

    @Test func externalLeftWithNegativeOrigin() {
        let external = DisplayInfo(id: 2, frame: CGRect(x: -2560, y: -200, width: 2560, height: 1440), backingScale: 1)
        let geometry = DisplayGeometry(displays: [retina, external])

        #expect(geometry.unionFrame == CGRect(x: -2560, y: -200, width: 4072, height: 1440))
        #expect(geometry.primaryDisplay == retina)
        #expect(geometry.display(containing: CGPoint(x: -1, y: 0))?.id == 2)
        #expect(geometry.display(containing: CGPoint(x: 0, y: 0))?.id == 1)
        #expect(geometry.display(containing: CGPoint(x: -100, y: -150))?.id == 2)

        let rect = CGRect(x: -100, y: 100, width: 300, height: 50)
        let slices = geometry.slices(forGlobalPoints: rect)
        #expect(slices.map(\.display.id) == [1, 2])
        #expect(slices[0].pixelRect == CGRect(x: 0, y: 1664, width: 400, height: 100))
        #expect(slices[1].pixelRect == CGRect(x: 2460, y: 1090, width: 100, height: 50))
        #expect(geometry.display(bestFor: rect)?.id == 1)

        let back = external.globalPointRect(forPixelRect: CGRect(x: 2460, y: 1090, width: 100, height: 50))
        #expect(back == CGRect(x: -100, y: 100, width: 100, height: 50))
    }

    @Test func threeDisplaysMixedScales() {
        let left = DisplayInfo(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), backingScale: 1)
        let right = DisplayInfo(id: 3, frame: CGRect(x: 1512, y: -500, width: 2560, height: 1440), backingScale: 1.5)
        let geometry = DisplayGeometry(displays: [left, retina, right])

        #expect(right.pixelSize == CGSize(width: 3840, height: 2160))
        let rect = CGRect(x: -10, y: 400, width: 1600, height: 100)
        let slices = geometry.slices(forGlobalPoints: rect)
        #expect(slices.map(\.display.id) == [2, 1, 3])
        #expect(slices[0].pixelRect == CGRect(x: 1910, y: 580, width: 10, height: 100))
        #expect(slices[1].pixelRect == CGRect(x: 0, y: 964, width: 3024, height: 200))
        #expect(slices[2].pixelRect == CGRect(x: 0, y: 660, width: 117, height: 150))
        #expect(right.globalPointRect(forPixelRect: slices[2].pixelRect) == slices[2].pointRect)
        #expect(geometry.display(bestFor: rect)?.id == 1)
        #expect(geometry.primaryDisplay == retina)

        // Quartz: right display's top (AppKit maxY 940) is 42 pt above the primary's top.
        #expect(geometry.quartzRect(fromAppKit: right.frame) == CGRect(x: 1512, y: 42, width: 2560, height: 1440))
    }

    @Test(arguments: [CGFloat(1), 1.5, 2, 3])
    func pixelRoundTripAtScale(_ scale: CGFloat) {
        let display = DisplayInfo(id: 9, frame: CGRect(x: -800, y: -600, width: 800, height: 600), backingScale: scale)
        let rect = CGRect(x: -700, y: -500, width: 200, height: 100)
        let pixels = display.pixelRect(forGlobalPoints: rect)
        #expect(pixels.width == 200 * scale)
        #expect(pixels.height == 100 * scale)
        #expect(display.globalPointRect(forPixelRect: pixels) == rect)
    }
}
