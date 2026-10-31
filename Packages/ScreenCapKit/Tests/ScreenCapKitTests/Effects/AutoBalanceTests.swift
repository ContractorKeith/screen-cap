import CoreGraphics
@testable import ScreenCapKit
import Testing

@Suite("AutoBalance")
struct AutoBalanceTests {
    static let dark = EffectsColor(red: 0.15, green: 0.2, blue: 0.3)

    /// Each edge within 2 px of the expected value (PLAN §7 M4 acceptance).
    static func expectClose(_ actual: EffectsInsets, _ expected: EffectsInsets) {
        #expect(abs(actual.top - expected.top) <= 2, "top \(actual.top) vs \(expected.top)")
        #expect(abs(actual.left - expected.left) <= 2, "left \(actual.left) vs \(expected.left)")
        #expect(abs(actual.bottom - expected.bottom) <= 2, "bottom \(actual.bottom) vs \(expected.bottom)")
        #expect(abs(actual.right - expected.right) <= 2, "right \(actual.right) vs \(expected.right)")
    }

    /// Fills a top-left-origin rect in a CG (bottom-left) context of the given height.
    static func fill(_ rect: CGRect, height: Int, color: EffectsColor, in context: CGContext) {
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
    }

    @Test func centeredContentOnTransparency() throws {
        let content = CGRect(x: 50, y: 25, width: 100, height: 50)
        let image = try EffectsFixtures.image(width: 200, height: 100, fill: nil) {
            Self.fill(content, height: 100, color: Self.dark, in: $0)
        }
        #expect(try AutoBalance.contentBounds(in: image) == content)
        // Margins 25/50/25/50; every side reaches max(48, 50 horizontally, 25 vertically).
        Self.expectClose(try AutoBalance.padding(for: image), EffectsInsets(top: 23, left: 0, bottom: 23, right: 0))
    }

    @Test func offsetContentOnOpaqueBackground() throws {
        let content = CGRect(x: 20, y: 10, width: 100, height: 50)
        let image = try EffectsFixtures.image(width: 300, height: 200, fill: .white) {
            Self.fill(content, height: 200, color: Self.dark, in: $0)
        }
        #expect(try AutoBalance.contentBounds(in: image) == content)
        // Margins top 10, left 20, bottom 140, right 180: pad the near sides up to the far ones.
        Self.expectClose(try AutoBalance.padding(for: image), EffectsInsets(top: 130, left: 160, bottom: 0, right: 0))
    }

    @Test func bottomHeavyWindowShadow() throws {
        let window = CGRect(x: 50, y: 30, width: 200, height: 150)
        let shadow = EffectsShadow(offset: CGSize(width: 0, height: 12), blur: 24, opacity: 0.5)
        let image = try EffectsFixtures.image(width: 300, height: 260, fill: nil) { context in
            context.setShadow(
                offset: CGSize(width: 0, height: -shadow.offset.height), blur: shadow.blur,
                color: EffectsColor(red: 0, green: 0, blue: 0, alpha: shadow.opacity).cgColor
            )
            Self.fill(window, height: 260, color: .white, in: context)
        }
        // The soft shadow is not content; the window body is.
        let bounds = try #require(try AutoBalance.contentBounds(in: image))
        #expect(abs(bounds.minX - window.minX) <= 2 && abs(bounds.maxX - window.maxX) <= 2)
        #expect(abs(bounds.minY - window.minY) <= 2 && abs(bounds.maxY - window.maxY) <= 2)

        // Margins top 30, bottom 80. Shift up by half the 12 px offset: total space 68 above, 80 below.
        let padding = try AutoBalance.padding(for: image, shadow: shadow)
        Self.expectClose(padding, EffectsInsets(top: 38, left: 0, bottom: 0, right: 0))
        // Without compensation the window would sit dead center vertically.
        Self.expectClose(try AutoBalance.padding(for: image), EffectsInsets(top: 50, left: 0, bottom: 0, right: 0))
    }
}
