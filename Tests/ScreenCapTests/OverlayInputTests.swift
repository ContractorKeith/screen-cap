import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// Fixed-size input stays total (#85); the magnifier keeps a pixel source when the screen isn't frozen (#90).
@Suite("Overlay input and magnifier source")
struct OverlayInputTests {
    // MARK: - #85 fixed size

    @Test(arguments: ["inf x 600", "600 x inf", "-inf x 600", "nan x 600", "600 x nan", "1e309 x 600",
                      "600 x 1e309", "-5 x 600", "600 x -1", "0 x 600", "0.4 x 600", "32769 x 600",
                      "600 x 40000", "1e18 x 1e18", "infinity x infinity", "", "800", "1 x 2 x 3"])
    func rejectsBadSizes(_ text: String) {
        #expect(SelectionMath.parseSize(text) == nil)
    }

    @Test func acceptsSizesUpToTheCap() {
        #expect(SelectionMath.parseSize("800 x 600") == CGSize(width: 800, height: 600))
        #expect(SelectionMath.parseSize("32768x1") == CGSize(width: 32768, height: 1))
        #expect(SelectionMath.parseSize("0.6 × 1.4") == CGSize(width: 1, height: 1))
    }

    @Test func fixedRectAndLabelAreTotal() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let bad: [CGFloat] = [.infinity, -.infinity, .nan, -5, 1e300, .greatestFiniteMagnitude]
        for width in bad {
            for height in bad + [100] {
                let rect = SelectionMath.fixedRect(size: CGSize(width: width, height: height),
                                                   centeredAt: CGPoint(x: 500, y: 400), within: screen)
                #expect(rect.width.isFinite && rect.height.isFinite && rect.minX.isFinite && rect.minY.isFinite)
                #expect(rect.width <= SelectionMath.maximumFixedSide && rect.height <= SelectionMath.maximumFixedSide)
                _ = SelectionMath.sizeLabel(rect.size)
                _ = SelectionMath.sizeLabel(CGSize(width: width, height: height))
            }
        }
        let nanPoint = SelectionMath.fixedRect(size: CGSize(width: 100, height: 100),
                                               centeredAt: CGPoint(x: CGFloat.nan, y: CGFloat.infinity),
                                               within: screen)
        #expect(nanPoint == CGRect(x: 450, y: 350, width: 100, height: 100))
        #expect(SelectionMath.sizeLabel(CGSize(width: CGFloat.infinity, height: CGFloat.nan)) == "0 × 0")
        #expect(SelectionMath.sizeLabel(CGSize(width: 800.4, height: 600.6)) == "800 × 601")
    }

    /// Fuzz: random strings never trap anywhere on the parse → rect → label path, and anything
    /// accepted is finite and within the cap.
    @Test func randomInputNeverTraps() {
        var rng = SplitMix64(seed: 85)
        let pieces = ["inf", "nan", "1e309", "-", "1e", "x", "X", "×", "*", ",", " ", ".", "0", "9", "32768",
                      "99999", "e", "+", "infinity", "0x1p1024", "1_000", "١٢", "5", "1e-400", "\t"]
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        for _ in 0..<5000 {
            let count = Int(rng.next() % 8)
            let text = (0..<count).map { _ in pieces[Int(rng.next() % UInt64(pieces.count))] }.joined()
            guard let size = SelectionMath.parseSize(text) else { continue }
            #expect(size.width.isFinite && size.height.isFinite)
            #expect((1...SelectionMath.maximumFixedSide).contains(size.width))
            #expect((1...SelectionMath.maximumFixedSide).contains(size.height))
            let rect = SelectionMath.fixedRect(size: size, centeredAt: CGPoint(x: -700, y: 450), within: screen)
            _ = SelectionMath.sizeLabel(rect.size)
        }
    }

    // MARK: - #90 magnifier source

    @Test func magnifierSourceFollowsFreezeScreen() {
        let frozen = OverlaySources(kind: .area, freezeScreen: true, showMagnifier: true)
        #expect(frozen == OverlaySources(kind: .area, freezeScreen: true, showMagnifier: true))
        #expect(frozen.freezes && frozen.magnifier == .frozenStill)
        let live = OverlaySources(kind: .area, freezeScreen: false, showMagnifier: true)
        #expect(!live.freezes && live.magnifier == .live)
        let hidden = OverlaySources(kind: .allInOne, freezeScreen: false, showMagnifier: false)
        #expect(!hidden.freezes && hidden.magnifier == .off)
    }

    @Test func selfTimerSamplesLiveEvenWithFreezeOn() {
        let timer = OverlaySources(kind: .selfTimer, freezeScreen: true, showMagnifier: true)
        #expect(!timer.freezes)
        #expect(timer.magnifier == .live)
        #expect(OverlaySources(kind: .selfTimer, freezeScreen: true, showMagnifier: false).magnifier == .off)
    }

    @Test func throttleAllowsOneRequestInFlightAndSpacesStarts() {
        var throttle = LiveSampleThrottle(interval: 0.05)
        let first = throttle.begin(now: 10)
        let whileInFlight = throttle.begin(now: 10.2)
        throttle.end()
        let afterEnd = throttle.begin(now: 10.2)
        throttle.end()
        let tooSoon = throttle.begin(now: 10.22)
        let spaced = throttle.begin(now: 10.26)
        #expect(first && !whileInFlight && afterEnd && !tooSoon && spaced)
    }

    @Test func liveSampleRectIsSmallAndOnTheDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(LiveSample.rect(around: CGPoint(x: 500.7, y: 300.2), in: display)
            == CGRect(x: 488, y: 288, width: 24, height: 24))
        #expect(LiveSample.rect(around: CGPoint(x: 2, y: 899), in: display)
            == CGRect(x: 0, y: 887, width: 14, height: 13))
        #expect(LiveSample.rect(around: CGPoint(x: 3000, y: 300), in: display) == nil)
        #expect(LiveSample.rect(around: CGPoint(x: CGFloat.nan, y: 0), in: display) == nil)
    }

    @MainActor @Test func overlayFeedsTheMagnifierFromTheRightSource() throws {
        let main = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 2)
        let side = DisplayInfo(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), backingScale: 1)
        let geometry = DisplayGeometry(displays: [main, side])
        let still = try Self.image(red: 255, pointRect: main.frame, scale: 2, displayID: 1)

        var options = SelectionOptions()
        options.magnifier = .frozenStill
        let frozen = SelectionOverlay(stills: [still], geometry: geometry, windows: [], options: options)
        #expect(frozen.magnifierImage(for: main)?.cgImage === still.cgImage)
        #expect(frozen.magnifierImage(for: side) == nil)

        options.magnifier = .live
        let live = SelectionOverlay(stills: [], geometry: geometry, windows: [], options: options)
        #expect(live.magnifierImage(for: main) == nil)
        let sample = try Self.image(red: 0, pointRect: CGRect(x: 38, y: 38, width: 24, height: 24), scale: 2,
                                    displayID: 1)
        live.acceptLiveSample(sample)
        #expect(live.magnifierImage(for: main)?.cgImage === sample.cgImage)
        #expect(live.magnifierImage(for: side) == nil)
        live.acceptLiveSample(nil)
        #expect(live.magnifierImage(for: main) != nil, "a failed grab keeps the last sample")

        options.magnifier = .off
        let off = SelectionOverlay(stills: [still], geometry: geometry, windows: [], options: options)
        #expect(off.magnifierImage(for: main) == nil)
    }

    /// A small live sample reads the pixel under the pointer, like a full still does.
    @MainActor @Test func liveSampleGivesPixelsAndHex() throws {
        let rect = CGRect(x: 488, y: 288, width: 24, height: 24)
        let sample = try Self.image(red: 0x12, green: 0xAB, pointRect: rect, scale: 2, displayID: 1)
        let pixels = try #require(Magnifier.sample(sample, at: CGPoint(x: 500, y: 300)))
        #expect(pixels.hex == "#12AB00")
        #expect(pixels.image.width == Magnifier.radius * 2 + 1)
    }

    // MARK: - Helpers

    static func image(red: UInt8, green: UInt8 = 0, pointRect: CGRect, scale: CGFloat,
                      displayID: CGDirectDisplayID) throws -> CapturedImage {
        let width = Int(pointRect.width * scale), height = Int(pointRect.height * scale)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        return CapturedImage(cgImage: image, scale: scale, pointRect: pointRect, displayID: displayID)
    }
}

/// Deterministic generator for the fuzz loop.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
