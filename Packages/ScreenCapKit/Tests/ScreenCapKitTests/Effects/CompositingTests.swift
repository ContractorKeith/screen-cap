import CoreGraphics
@testable import ScreenCapKit
import Testing

@Suite("Spotlight")
struct SpotlightTests {
    static let gray = EffectsColor(red: 0.8, green: 0.6, blue: 0.4)

    @Test func dimsOutsideAndKeepsInside() throws {
        let image = try EffectsFixtures.image(width: 100, height: 100, fill: Self.gray)
        let original = try EffectsFixtures.pixel(image, x: 0, y: 0)
        let result = try Spotlight.apply(
            image,
            shapes: [
                .rect(CGRect(x: 10, y: 10, width: 30, height: 30)),
                .ellipse(CGRect(x: 50, y: 50, width: 40, height: 40))
            ],
            dimColor: .black, dimOpacity: 0.5
        )
        // Inside the rect and the ellipse center: unchanged.
        #expect(try EffectsFixtures.pixel(result, x: 25, y: 25) == original)
        #expect(try EffectsFixtures.pixel(result, x: 70, y: 70) == original)
        // Outside, including the ellipse's bounding-box corner: roughly halved.
        for (x, y) in [(5, 5), (95, 5), (51, 51), (45, 80)] {
            let dimmed = try EffectsFixtures.pixel(result, x: x, y: y)
            for channel in 0..<3 {
                #expect(abs(dimmed[channel] - original[channel] / 2) <= 2)
            }
            #expect(dimmed[3] == 255)
        }
    }

    @Test func overlappingShapesFormAUnion() throws {
        let image = try EffectsFixtures.image(width: 60, height: 40, fill: Self.gray)
        let original = try EffectsFixtures.pixel(image, x: 0, y: 0)
        let result = try Spotlight.apply(
            image,
            shapes: [
                .rect(CGRect(x: 0, y: 0, width: 40, height: 40)),
                .rect(CGRect(x: 20, y: 0, width: 40, height: 40))
            ]
        )
        #expect(try EffectsFixtures.pixel(result, x: 30, y: 20) == original)
    }
}

@Suite("BackgroundCompositor")
struct BackgroundCompositorTests {
    static let red = EffectsColor(red: 1, green: 0, blue: 0)

    @Test func outputIsImagePlusPaddingWithFillInCorner() throws {
        let image = try EffectsFixtures.image(width: 100, height: 60, fill: .white)
        let spec = BackgroundSpec(
            fill: .solid(Self.red),
            padding: EffectsInsets(top: 10, left: 20, bottom: 30, right: 40),
            cornerRadius: 12,
            shadow: EffectsShadow(offset: CGSize(width: 0, height: 4), blur: 6, opacity: 0.4)
        )
        let result = try BackgroundCompositor.render(image, background: spec)
        #expect(result.width == 160 && result.height == 100)
        #expect(try EffectsFixtures.pixel(result, x: 0, y: 0) == [255, 0, 0, 255])
        #expect(try EffectsFixtures.pixel(result, x: 159, y: 99) == [255, 0, 0, 255])
        // Image center is the screenshot; its rounded corner shows the fill.
        #expect(try EffectsFixtures.pixel(result, x: 70, y: 40) == [255, 255, 255, 255])
        let corner = try EffectsFixtures.pixel(result, x: 20, y: 10)
        #expect(corner[0] > 200 && corner[1] < 60)
    }

    @Test func aspectRatioGrowsCanvasAndAligns() throws {
        let image = try EffectsFixtures.image(width: 100, height: 100, fill: .white)
        let spec = BackgroundSpec(
            fill: .solid(Self.red), padding: EffectsInsets(all: 10), alignment: .leading, aspectRatio: 2
        )
        let layout = BackgroundCompositor.layout(imageSize: CGSize(width: 100, height: 100), spec: spec)
        #expect(layout.canvas == CGSize(width: 240, height: 120))
        #expect(layout.frame.origin == CGPoint(x: 10, y: 10))
        let result = try BackgroundCompositor.render(image, background: spec)
        #expect(result.width == 240 && result.height == 120)
        #expect(try EffectsFixtures.pixel(result, x: 200, y: 60) == [255, 0, 0, 255])
    }

    @Test func gradientRunsAlongAngle() throws {
        let image = try EffectsFixtures.image(width: 10, height: 10, fill: .white)
        let stops = [
            EffectsGradientStop(color: .black, location: 0),
            EffectsGradientStop(color: .white, location: 1)
        ]
        let spec = BackgroundSpec(fill: .linearGradient(stops: stops, angle: 90), padding: EffectsInsets(all: 45))
        let result = try BackgroundCompositor.render(image, background: spec)
        let top = try EffectsFixtures.pixel(result, x: 2, y: 1)
        let bottom = try EffectsFixtures.pixel(result, x: 2, y: 98)
        #expect(top[0] < 20 && bottom[0] > 235)
        // Same row, different columns: equal (within dithering) for a vertical gradient.
        let sameRow = try EffectsFixtures.pixel(result, x: 90, y: 1)
        #expect(abs(sameRow[0] - top[0]) <= 2)
    }
}
