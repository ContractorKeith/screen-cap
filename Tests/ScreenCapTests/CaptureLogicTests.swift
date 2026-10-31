import CoreGraphics
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Capture logic")
struct CaptureLogicTests {
    @Test func launchArguments() {
        let parsed = LaunchArguments.parse(["ScreenCap", "--capture", "fullscreen", "--action", "save", "--quit"])
        #expect(parsed == LaunchArguments(capture: .fullscreen, action: .save, quitAfterCapture: true))
        #expect(LaunchArguments.parse(["ScreenCap"]) == LaunchArguments())
        let system = LaunchArguments.parse(["ScreenCap", "-NSDocumentRevisionsDebugMode", "YES"])
        #expect(system == LaunchArguments())
        let junk = LaunchArguments.parse(["ScreenCap", "--capture", "bogus"])
        #expect(junk.capture == nil)
        #expect(junk.problems == ["--capture needs a kind, got bogus"])
        #expect(LaunchArguments.parse(["ScreenCap", "--capture"]).capture == nil)
        let window = LaunchArguments.parse(["ScreenCap", "--capture", "window", "--window", "Terminal"])
        #expect(window.capture == .window)
        #expect(window.windowApp == "Terminal")
    }

    /// #119: a bad `--region` with `--quit` is a usage error (exit 3), never the interactive overlay.
    @Test(arguments: ["nan,0,100,100", "0,0,inf,100", "1e3,0,100,100", "0x10,0,100,100", "1,2,3"])
    func badRegionWithQuitFailsFast(region: String) {
        let parsed = LaunchArguments.parse(["ScreenCap", "--capture", "scrolling", "--region", region, "--quit"])
        #expect(parsed.problems == ["\(LaunchArguments.regionUsage), got \(region)"])
        #expect(parsed.warnings.isEmpty)
        #expect(parsed.requestsCapture)
        #expect(CaptureOutcome.notStarted(parsed.problems[0]).exitStatus == 3)
    }

    @Test func badRegionOptionOrderAndMissingValue() {
        let quitFirst = LaunchArguments.parse(["ScreenCap", "--quit", "--capture", "scrolling", "--region", "nan"])
        #expect(quitFirst.problems.count == 1)
        let missing = LaunchArguments.parse(["ScreenCap", "--capture", "scrolling", "--region", "--quit"])
        #expect(missing.quitAfterCapture)
        #expect(missing.problems == ["\(LaunchArguments.regionUsage), got nothing"])
    }

    @Test func badRegionWithoutQuitWarnsAndFallsBack() {
        let parsed = LaunchArguments.parse(["ScreenCap", "--capture", "scrolling", "--region", "nan,0,100,100"])
        #expect(parsed.problems.isEmpty)
        #expect(parsed.capture == .scrolling)
        let expected = "\(LaunchArguments.regionUsage), got nan,0,100,100; selecting the region interactively"
        #expect(parsed.warnings == [expected])
    }

    @Test func goodOrAbsentRegionIsSilent() {
        let good = LaunchArguments.parse(["ScreenCap", "--capture", "scrolling", "--region", "-10,0,100,100", "--quit"])
        #expect(good.problems.isEmpty && good.warnings.isEmpty)
        #expect(good.capture == .scrolling && good.quitAfterCapture)
        let absent = LaunchArguments.parse(["ScreenCap", "--capture", "scrolling", "--quit"])
        #expect(absent.problems.isEmpty && absent.warnings.isEmpty)
    }

    @Test func everyKindRawValueRoundTrips() {
        for kind in CaptureKind.allCases {
            #expect(CaptureKind(rawValue: kind.rawValue) == kind)
        }
        #expect(CaptureKind.previousArea.rawValue == "previousArea")
    }

    @Test func kindsMapToSettingsAndFilenameTokens() {
        #expect(CaptureKind.window.shortcut == .window)
        #expect(CaptureKind.allInOne.shortcut == .area)
        #expect(CaptureKind.selfTimer.shortcut == .selfTimer)
        #expect(CaptureKind.fullscreen.filenameKind == .fullscreen)
        #expect(CaptureKind.previousArea.filenameKind == .area)
        // History kinds are built from these raw values.
        for kind in FilenameTemplate.Kind.allCases {
            #expect(["area", "window", "fullscreen", "scrolling"].contains(kind.rawValue))
        }
    }

    @Test func windowPickerSkipsNonAppWindowsAndPicksFrontmost() {
        func window(_ id: CGWindowID, _ frame: CGRect, layer: Int = 0) -> ShareableWindow {
            ShareableWindow(id: id, frame: frame, title: nil, appName: nil, bundleIdentifier: nil,
                            processID: 1, layer: layer)
        }
        let picker = WindowPicker(windows: [
            window(1, CGRect(x: 0, y: 870, width: 1512, height: 30), layer: 24),
            window(2, CGRect(x: 100, y: 100, width: 20, height: 20)),
            window(3, CGRect(x: 50, y: 50, width: 400, height: 300)),
            window(4, CGRect(x: 0, y: 0, width: 800, height: 600))
        ])
        #expect(picker.windows.map(\.id) == [3, 4])
        #expect(picker.window(at: CGPoint(x: 110, y: 110))?.id == 3)
        #expect(picker.window(at: CGPoint(x: 700, y: 500))?.id == 4)
        #expect(picker.window(at: CGPoint(x: 10, y: 880)) == nil)
    }

    @Test func outputScalerHalvesRetinaForStandard() throws {
        let image = try #require(Self.solidImage(width: 200, height: 100))
        let retina = CapturedImage(cgImage: image, scale: 2, pointRect: CGRect(x: 0, y: 0, width: 100, height: 50),
                                   displayID: 1)
        let standard = try OutputScaler.scaled(retina, to: .standard)
        #expect(standard.cgImage.width == 100)
        #expect(standard.cgImage.height == 50)
        #expect(standard.scale == 1)
        #expect(standard.pointRect == retina.pointRect)
        // Never upsamples, and 2x stays untouched.
        #expect(try OutputScaler.scaled(retina, to: .retina).cgImage.width == 200)
        let oneX = CapturedImage(cgImage: image, scale: 1, pointRect: .zero, displayID: nil)
        #expect(try OutputScaler.scaled(oneX, to: .retina).cgImage.width == 200)
    }

    @Test @MainActor func magnifierReadsTheCenterPixel() throws {
        let image = try #require(Self.solidImage(width: 40, height: 40, red: 1, green: 0, blue: 0))
        let still = CapturedImage(cgImage: image, scale: 2, pointRect: CGRect(x: 0, y: 0, width: 20, height: 20),
                                  displayID: 1)
        let sample = try #require(Magnifier.sample(still, at: CGPoint(x: 10, y: 10)))
        #expect(sample.hex == "#FF0000")
        #expect(sample.image.width == Magnifier.radius * 2 + 1)
        // At a corner, the sample is still full-size (padded with black).
        #expect(Magnifier.sample(still, at: CGPoint(x: 0.2, y: 19.8))?.image.width == Magnifier.radius * 2 + 1)
    }

    static func solidImage(width: Int, height: Int, red: CGFloat = 0.2, green: CGFloat = 0.4, blue: CGFloat = 0.6)
        -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
