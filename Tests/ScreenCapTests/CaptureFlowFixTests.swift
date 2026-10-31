import CoreGraphics
import Foundation
import ImageIO
@testable import ScreenCap
import ScreenCapKit
import Testing

/// Exit codes, previous-area rules, aspect lock and saving (issues #46, #48, #50, #51, #60).
@Suite("Capture flow fixes")
struct CaptureFlowFixTests {
    // MARK: - #46 `--quit`

    @Test func quitIsNotSwallowedAsACaptureValue() {
        let parsed = LaunchArguments.parse(["ScreenCap", "--capture", "--quit"])
        #expect(parsed.capture == nil)
        #expect(parsed.quitAfterCapture)
        #expect(parsed.requestsCapture)
        #expect(parsed.problems.count == 1)
    }

    @Test func outcomesMapToExitStatuses() {
        #expect(CaptureOutcome.delivered.exitStatus == 0)
        #expect(CaptureOutcome.failed("disk full").exitStatus == 1)
        #expect(CaptureOutcome.cancelled.exitStatus == 2)
        #expect(CaptureOutcome.notStarted("no permission").exitStatus == 3)
    }

    @Test func outcomesMergeSoFailuresStick() {
        let cancelled = CaptureOutcome.cancelled
        #expect(cancelled.merged(with: .delivered) == .delivered)
        #expect(CaptureOutcome.delivered.merged(with: .failed("x")) == .failed("x"))
        #expect(CaptureOutcome.failed("x").merged(with: .delivered) == .failed("x"))
        #expect(cancelled.merged(with: .cancelled) == .cancelled)
        #expect(CaptureOutcome.delivered.merged(with: .cancelled) == .delivered)
    }

    // MARK: - #50 previous area

    @Test func ocrAndScrollingDoNotBecomeThePreviousArea() {
        #expect(!CaptureKind.text.remembersArea)
        #expect(!CaptureKind.scrolling.remembersArea)
        #expect(CaptureKind.area.remembersArea)
        #expect(CaptureKind.selfTimer.remembersArea)
        #expect(!AllInOneChoice.text.remembersArea)
        #expect(!AllInOneChoice.scrolling.remembersArea)
        #expect(AllInOneChoice.timer.remembersArea)
    }

    // MARK: - #60 aspect lock

    @Test func aspectLockIgnoresSlivers() {
        let sliver = CGRect(x: 0, y: 0, width: 200, height: 0)
        #expect(SelectionMath.lockedAspect(current: sliver, fallback: nil) == 1)
        #expect(SelectionMath.lockedAspect(current: sliver, fallback: CGRect(x: 0, y: 0, width: 160, height: 90))
            == CGFloat(160) / CGFloat(90))
        #expect(SelectionMath.lockedAspect(current: CGRect(x: 0, y: 0, width: 7, height: 50), fallback: nil) == 1)
        #expect(SelectionMath.lockedAspect(current: CGRect(x: 0, y: 0, width: 80, height: 40), fallback: nil) == 2)
    }

    @Test func lockedRectStaysInsideTheDisplayUnion() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = SelectionMath.rect(from: CGPoint(x: 900, y: 100), to: CGPoint(x: 950, y: 600),
                                      aspect: 2, within: bounds)
        #expect(bounds.contains(rect))
        #expect(rect == CGRect(x: 900, y: 100, width: 100, height: 50))
        let free = SelectionMath.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: -50, y: 900), within: bounds)
        #expect(free == CGRect(x: 0, y: 100, width: 100, height: 700))
    }

    // MARK: - #48 and #51 saving

    @MainActor static func output(folder: URL, scale: RetinaScale) -> CaptureOutput {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.saveFolder = folder
        settings.filenameTemplate = "ScreenCap {date} at {time}"
        settings.imageFormat = .png
        settings.retinaScale = scale
        return CaptureOutput(settings: settings)
    }

    static func retinaResult() throws -> CaptureResult {
        let image = try #require(CaptureLogicTests.solidImage(width: 200, height: 100))
        let captured = CapturedImage(cgImage: image, scale: 2, pointRect: CGRect(x: 0, y: 0, width: 100, height: 50),
                                     displayID: 1)
        return CaptureResult(image: captured, kind: .area, context: FilenameTemplate.Context())
    }

    static func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test @MainActor func twoConcurrentSavesWriteTwoFiles() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = Self.output(folder: folder, scale: .retina)
        let result = try Self.retinaResult()
        async let first = output.save(result)
        async let second = output.save(result)
        let urls = try await [first, second]
        #expect(Set(urls).count == 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.count == 2)
        for url in urls {
            #expect(try !Data(contentsOf: url).isEmpty)
        }
    }

    @Test @MainActor func oneXScalesOnlyTheWrittenFile() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try Self.retinaResult()
        let url = try await Self.output(folder: folder, scale: .standard).save(result)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let written = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(written.width == 100)
        // The capture handed to history, the editor and pins is untouched.
        #expect(result.image.cgImage.width == 200)
        #expect(result.image.scale == 2)
    }
}
