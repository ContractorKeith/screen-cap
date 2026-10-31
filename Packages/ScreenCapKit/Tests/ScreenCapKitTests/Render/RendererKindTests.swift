import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

/// One test per annotation kind: render on a white 200 × 200 base, check specific pixels.
@Suite("Renderer kinds")
struct RendererKindTests {
    private typealias Fix = RenderFixtures
    private let blue = RenderFixtures.blue
    private let green = RenderFixtures.green

    private func arrow(_ style: Annotation.ArrowStyle, y: Double = 100) throws -> RenderedPixels {
        try Fix.render([Fix.annotation(.arrow(start: CGPoint(x: 20, y: y), end: CGPoint(x: 180, y: y), style: style))])
    }

    @Test func baseImageOnly() throws {
        let pixels = try Fix.render([])
        #expect(pixels.width == 200 && pixels.height == 200)
        #expect(pixels[0, 0].matches(.white) && pixels[199, 199].matches(.white))
    }

    @Test func straightArrow() throws {
        let pixels = try arrow(.straight)
        #expect(pixels[60, 100].matches(blue))
        #expect(pixels[170, 103].matches(blue), "head is wider than the shaft")
        #expect(pixels[30, 103].matches(.white), "no head at the tail")
        #expect(pixels[185, 100].matches(.white), "nothing past the tip")
        #expect(pixels[60, 60].matches(.white))
    }

    @Test func taperedArrow() throws {
        let pixels = try arrow(.tapered)
        #expect(pixels[25, 100].matches(blue))
        #expect(pixels[25, 103].matches(.white), "thin at the tail")
        #expect(pixels[150, 100].matches(blue))
        #expect(pixels[168, 104].matches(blue), "wide head")
    }

    @Test func doubleHeadedArrow() throws {
        let pixels = try arrow(.doubleHeaded)
        #expect(pixels[30, 103].matches(blue))
        #expect(pixels[170, 103].matches(blue))
        #expect(pixels[100, 103].matches(.white))
    }

    @Test func curvedArrowFollowsControlPoint() throws {
        let pixels = try Fix.render([Fix.annotation(.arrow(start: CGPoint(x: 20, y: 150), end: CGPoint(x: 180, y: 150),
                                                       style: .curved(control: CGPoint(x: 100, y: 20))))])
        #expect(pixels[100, 85].matches(blue), "quadratic midpoint")
        #expect(pixels[100, 150].matches(.white), "not a straight line")
        #expect(pixels[176, 146].matches(blue), "head at the end")
    }

    @Test func strokedRectangle() throws {
        let rect = CGRect(x: 40, y: 40, width: 120, height: 120)
        let pixels = try Fix.render([Fix.annotation(.rectangle(rect: rect, filled: false, cornerRadius: 0))])
        #expect(pixels[40, 100].matches(blue))
        #expect(pixels[100, 159].matches(blue))
        #expect(pixels[100, 100].matches(.white))
    }

    @Test func filledRectangleUsesFillColor() throws {
        let rect = CGRect(x: 40, y: 40, width: 120, height: 120)
        let annotation = Fix.annotation(.rectangle(rect: rect, filled: true, cornerRadius: 0), fill: green)
        let pixels = try Fix.render([annotation])
        #expect(pixels[100, 100].matches(green))
        #expect(pixels[30, 100].matches(.white))
    }

    @Test func roundedRectangleCutsCorners() throws {
        let rect = CGRect(x: 40, y: 40, width: 120, height: 120)
        let pixels = try Fix.render([Fix.annotation(.rectangle(rect: rect, filled: true, cornerRadius: 40))])
        #expect(pixels[42, 42].matches(.white))
        #expect(pixels[100, 42].matches(blue))
        #expect(pixels[42, 100].matches(blue))
    }

    @Test func ellipse() throws {
        let pixels = try Fix.render([Fix.annotation(.ellipse(rect: CGRect(x: 40, y: 40, width: 120, height: 120)))])
        #expect(pixels[40, 100].matches(blue))
        #expect(pixels[100, 40].matches(blue))
        #expect(pixels[45, 45].matches(.white), "corner of the bounding box is outside")
        #expect(pixels[100, 100].matches(.white))
    }

    @Test func line() throws {
        let pixels = try Fix.render([Fix.annotation(.line(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 180, y: 180)))])
        #expect(pixels[100, 100].matches(blue))
        #expect(pixels[100, 20].matches(.white))
    }

    @Test func counter() throws {
        let pixels = try Fix.render([Fix.annotation(.counter(number: 7, center: CGPoint(x: 100, y: 100), radius: 30))])
        #expect(pixels[100, 74].matches(blue))
        #expect(pixels[73, 100].matches(blue))
        #expect(pixels[100, 135].matches(.white), "outside the circle")
        let numberArea = CGRect(x: 88, y: 88, width: 24, height: 24)
        var whiteInside = 0
        for y in Int(numberArea.minY)..<Int(numberArea.maxY) {
            for x in Int(numberArea.minX)..<Int(numberArea.maxX) where pixels[x, y].matches(.white, tolerance: 30) {
                whiteInside += 1
            }
        }
        #expect(whiteInside > 20, "white number on a blue disc")
    }

    @Test(arguments: [false, true])
    func pathSmoothing(smoothed: Bool) throws {
        let points = [CGPoint(x: 20, y: 100), CGPoint(x: 100, y: 20), CGPoint(x: 180, y: 100)]
        let pixels = try Fix.render([Fix.annotation(.path(points: points, smoothed: smoothed))])
        for point in points.dropFirst().dropLast() { #expect(pixels[Int(point.x), Int(point.y) + 1].matches(blue)) }
        // The Catmull-Rom curve passes (55, 55); the polyline passes (55, 65).
        #expect(pixels[55, 55].matches(smoothed ? blue : .white))
        #expect(pixels[55, 65].matches(smoothed ? .white : blue))
    }

    @Test func highlightMultipliesOntoContent() throws {
        let yellow = RGBAColor(red: 1, green: 1, blue: 0)
        let pixels = try Fix.render([
            Fix.annotation(.rectangle(rect: CGRect(x: 0, y: 0, width: 100, height: 200), filled: true, cornerRadius: 0),
                         color: .black),
            Fix.annotation(.highlight(region: .rect(rect: CGRect(x: 50, y: 90, width: 100, height: 20)), color: yellow),
                         zIndex: 1)
        ])
        #expect(pixels[120, 100].matches(yellow), "white × yellow = yellow")
        #expect(pixels[70, 100].matches(.black), "black × yellow stays black")
        #expect(pixels[120, 120].matches(.white))
    }

    @Test func highlightPath() throws {
        let yellow = RGBAColor(red: 1, green: 1, blue: 0)
        let points = [CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100)]
        let annotation = Fix.annotation(.highlight(region: .path(points: points), color: yellow), width: 16)
        let pixels = try Fix.render([annotation])
        #expect(pixels[100, 106].matches(yellow))
        #expect(pixels[100, 112].matches(.white))
    }

    @Test func imageLayerIsUpright() throws {
        let layer = Fix.twoToneImage()
        let pixels = try Fix.render([Fix.annotation(.imageLayer(layerName: "pasted",
                                                            rect: CGRect(x: 50, y: 50, width: 40, height: 40)))],
                                  layers: ["pasted": layer])
        #expect(pixels[70, 55].matches(RGBAColor(red: 1, green: 0, blue: 0)), "top half red")
        #expect(pixels[70, 85].matches(green), "bottom half green")
        #expect(pixels[45, 70].matches(.white))
    }

    @Test func missingImageLayerDrawsNothing() throws {
        let pixels = try Fix.render([Fix.annotation(.imageLayer(layerName: "gone", rect: CGRect(x: 0, y: 0, width: 50,
                                                                                         height: 50)))])
        #expect(pixels.inkCount(in: CGRect(x: 0, y: 0, width: 50, height: 50)) == 0)
    }

    @Test func noOpRedactionHookDrawsNothing() throws {
        let rect = CGRect(x: 20, y: 20, width: 100, height: 100)
        let pixels = try Fix.render([
            Fix.annotation(.blur(rect: rect, mode: .secure, radius: 10)),
            Fix.annotation(.pixelate(rect: rect, blockSize: 8, randomize: true)),
            Fix.annotation(.spotlight(shapes: [.rect(rect: rect)]))
        ], renderer: Renderer(redaction: NoOpRedactionRenderer()))
        #expect(pixels.inkCount(in: CGRect(x: 0, y: 0, width: 200, height: 200)) == 0)
    }
}
