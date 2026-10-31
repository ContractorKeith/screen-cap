import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("Text rendering")
struct TextRenderingTests {
    private typealias Fix = RenderFixtures

    private func text(_ string: String, preset: Int, fontSize: Double = 32, rect: CGRect,
                      fill: RGBAColor? = nil) throws -> RenderedPixels {
        try Fix.render([Fix.annotation(.text(string: string, preset: preset, fontSize: fontSize, rect: rect),
                                   fill: fill)])
    }

    @Test(arguments: TextPreset.allCases)
    func everyPresetDrawsInsideItsRect(preset: TextPreset) throws {
        let rect = CGRect(x: 10, y: 10, width: 180, height: 60)
        let pixels = try text("Hi mom", preset: preset.rawValue, rect: rect)
        #expect(pixels.inkCount(in: rect) > 100)
        #expect(pixels.inkCount(in: CGRect(x: 0, y: 75, width: 200, height: 125)) == 0, "nothing below the rect")
    }

    @Test func plainTextUsesStrokeColor() throws {
        let rect = CGRect(x: 10, y: 10, width: 180, height: 80)
        let pixels = try text("████", preset: 1, fontSize: 40, rect: rect)
        var found = false
        for y in 10..<90 {
            for x in 10..<190 where pixels[x, y].matches(Fix.blue) { found = true }
        }
        #expect(found)
    }

    @Test(arguments: [3, 5])
    func backgroundPresetsFillTheRect(preset: Int) throws {
        let rect = CGRect(x: 10, y: 10, width: 180, height: 60)
        let pixels = try text("Hi", preset: preset, rect: rect, fill: Fix.green)
        #expect(pixels[180, 40].matches(Fix.green))
        #expect(pixels[100, 75].matches(.white))
    }

    @Test func textIsUprightAndStartsAtTheTop() throws {
        // A "T" has a wide bar on top and a narrow stem below.
        let rect = CGRect(x: 10, y: 10, width: 180, height: 180)
        let pixels = try text("T", preset: 1, fontSize: 120, rect: rect)
        var inkRows: [(y: Int, width: Int)] = []
        for y in 0..<200 {
            let width = pixels.inkCount(in: CGRect(x: 0, y: y, width: 200, height: 1))
            if width > 0 { inkRows.append((y, width)) }
        }
        let top = try #require(inkRows.first)
        let bottom = try #require(inkRows.last)
        #expect(top.width > bottom.width * 2)
        #expect(top.y < 60, "first line sits at the top of the rect")
    }

    @Test func longTextWrapsWithinTheRect() throws {
        let rect = CGRect(x: 10, y: 10, width: 70, height: 180)
        let pixels = try text("wrap these words please", preset: 1, fontSize: 18, rect: rect)
        #expect(pixels.inkCount(in: CGRect(x: 10, y: 60, width: 70, height: 130)) > 0, "later lines")
        #expect(pixels.inkCount(in: CGRect(x: 85, y: 0, width: 115, height: 200)) == 0, "nothing right of the rect")
    }

    @Test func boldUppercaseUppercases() throws {
        let rect = CGRect(x: 10, y: 10, width: 180, height: 80)
        let lower = try text("abc", preset: 6, rect: rect)
        let upper = try text("ABC", preset: 6, rect: rect)
        #expect(lower == upper)
    }
}
