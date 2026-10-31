import AppKit
import CoreGraphics
import Foundation
import ImageIO
@testable import ScreenCap
import ScreenCapKit
import Testing

/// #88: only a swipe that ends normally past the threshold commits.
@Suite("Quick Access swipe phases")
struct SwipeGestureTests {
    /// One synthetic scroll event: phase, momentum flag, horizontal finger delta.
    private struct Event {
        let phase: SwipeGesture.Phase
        var momentum = false
        var dx: CGFloat = 0
    }

    private func run(_ events: [Event]) -> [SwipeGesture.Step] {
        var gesture = SwipeGesture()
        return events.flatMap { gesture.handle(phase: $0.phase, isMomentum: $0.momentum, dx: $0.dx, dy: 0) }
    }

    /// The issue's harness: Began, Changed +100, Cancelled, in either direction.
    @Test(arguments: [CGFloat(100), -100])
    func cancelledSwipeCommitsNothing(dx: CGFloat) {
        let steps = run([Event(phase: .began), Event(phase: .changed, dx: dx), Event(phase: .cancelled)])
        #expect(steps == [.moved(dx), .cancelled])
        #expect(!steps.contains { if case .ended = $0 { true } else { false } })
    }

    @Test func endedSwipePastThresholdCommits() {
        let steps = run([Event(phase: .began), Event(phase: .changed, dx: 50), Event(phase: .changed, dx: 50),
                         Event(phase: .ended)])
        guard case .ended(let tracker) = steps.last else { Issue.record("no end step"); return }
        #expect(tracker.action(for: .bottomRight) == .save)
        #expect(tracker.action(for: .bottomLeft) == .dismiss)
    }

    @Test func endedShortSwipeHasNoAction() {
        let steps = run([Event(phase: .began), Event(phase: .changed, dx: 30), Event(phase: .ended)])
        guard case .ended(let tracker) = steps.last else { Issue.record("no end step"); return }
        #expect(tracker.action(for: .bottomRight) == nil)
    }

    /// Momentum after the fingers lift never moves or commits, even when it would carry the
    /// total past the threshold: the decision is the finger travel at `.ended`.
    @Test func momentumNeverCommits() {
        let steps = run([
            Event(phase: .began), Event(phase: .changed, dx: 30), Event(phase: .ended),
            Event(phase: .began, momentum: true), Event(phase: .changed, momentum: true, dx: 200),
            Event(phase: .ended, momentum: true)
        ])
        #expect(steps.count == 2)
        guard case .ended(let tracker) = steps.last else { Issue.record("no end step"); return }
        #expect(tracker.dx == 30 && tracker.action(for: .bottomRight) == nil)
    }

    @Test func momentumAfterCancelDoesNothing() {
        let steps = run([
            Event(phase: .began), Event(phase: .changed, dx: 90), Event(phase: .cancelled),
            Event(phase: .changed, momentum: true, dx: 200), Event(phase: .ended, momentum: true)
        ])
        #expect(steps == [.moved(90), .cancelled])
    }

    /// AppKit reports Began / Changed / Cancelled as raw phases 1, 4, 16.
    @Test func mapsAppKitPhases() {
        #expect(SwipeGesture.Phase(NSEvent.Phase(rawValue: 1)) == .began)
        #expect(SwipeGesture.Phase(NSEvent.Phase(rawValue: 4)) == .changed)
        #expect(SwipeGesture.Phase(NSEvent.Phase(rawValue: 16)) == .cancelled)
        #expect(SwipeGesture.Phase(NSEvent.Phase.ended) == .ended)
        #expect(SwipeGesture.Phase([]).isEmpty)
    }
}

/// #87: drag-out uses the output scale, like Save; the capture itself stays full resolution.
@Suite("Quick Access drag-out scale")
struct QuickAccessDragScaleTests {
    private func result() throws -> CaptureResult {
        let image = try #require(CaptureLogicTests.solidImage(width: 200, height: 100))
        return CaptureResult(
            image: CapturedImage(cgImage: image, scale: 2, pointRect: CGRect(x: 0, y: 0, width: 100, height: 50),
                                 displayID: nil),
            kind: .area, context: FilenameTemplate.Context()
        )
    }

    /// Own folder: QuickAccessController empties the shared one when other suites create it.
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("DragScaleTests-\(UUID())")

    private func options(_ scale: RetinaScale, _ format: ImageFormat = .png) -> SaveOptions {
        SaveOptions(format: format, scale: scale, jpegQuality: 0.9,
                    folder: FileManager.default.temporaryDirectory, filenameTemplate: "drag {date} {time}")
    }

    private func size(_ data: Data?) -> CGSize? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    @Test(arguments: [(RetinaScale.standard, CGSize(width: 100, height: 50)),
                      (RetinaScale.retina, CGSize(width: 200, height: 100))])
    func dragPayloadMatchesOutputScale(scale: RetinaScale, expected: CGSize) async throws {
        let result = try result()
        let contents = await QuickAccessItem.prepareDrag(for: result, options: options(scale), in: root)
        let url = try #require(contents.fileURL)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(size(contents.pngData) == expected)
        #expect(size(try Data(contentsOf: url)) == expected)
        // Quick Access and History keep the full-resolution source.
        #expect(result.image.pixelSize == CGSize(width: 200, height: 100))
    }

    @Test func jpegDragFileIsScaledToo() async throws {
        let contents = await QuickAccessItem.prepareDrag(for: try result(), options: options(.standard, .jpeg),
                                                         in: root)
        let url = try #require(contents.fileURL)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(size(try Data(contentsOf: url)) == CGSize(width: 100, height: 50))
    }

    /// The on-the-spot fallback used before background preparation finishes.
    @Test func fallbackEncodeIsScaled() throws {
        let data = QuickAccessItem.encode(try result().image, scale: .standard, format: .png)
        #expect(size(data) == CGSize(width: 100, height: 50))
    }
}

/// #89: window captures composite the Wallpaper settings.
@Suite("Window with background")
struct WindowBackgroundTests {
    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // Top-left pixel coordinates: shift the image so (x, y) lands on the 1×1 context.
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return bytes
    }

    @Test func solidFillAndPaddingInPoints() throws {
        let window = try #require(CaptureLogicTests.solidImage(width: 40, height: 20, red: 1, green: 0, blue: 0))
        let image = CapturedImage(cgImage: window, scale: 2,
                                  pointRect: CGRect(x: 100, y: 200, width: 20, height: 10), displayID: 7)
        let options = WallpaperOptions(style: .solid, solidColor: RGBAColor(red: 0, green: 0, blue: 1), padding: 8)

        let output = try WindowBackground.composite(image, options: options, wallpaper: nil)

        // 8 pt of padding is 16 px per side at 2x.
        #expect(output.pixelSize == CGSize(width: 72, height: 52))
        #expect(output.scale == 2)
        #expect(output.pointRect == CGRect(x: 92, y: 192, width: 36, height: 26))
        #expect(output.displayID == 7)
        let corner = pixel(output.cgImage, x: 2, y: 2)
        #expect(corner[2] > 240 && corner[0] < 15)
        let center = pixel(output.cgImage, x: 36, y: 26)
        #expect(center[0] > 240 && center[2] < 15)
    }

    @Test func imageStyleUsesSuppliedWallpaper() throws {
        let window = try #require(CaptureLogicTests.solidImage(width: 10, height: 10, red: 1, green: 0, blue: 0))
        let wallpaper = try #require(CaptureLogicTests.solidImage(width: 30, height: 30, red: 0, green: 1, blue: 0))
        let image = CapturedImage(cgImage: window, scale: 1, pointRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                  displayID: nil)
        let options = WallpaperOptions(style: .image, padding: 4)
        let output = try WindowBackground.composite(image, options: options, wallpaper: wallpaper)
        #expect(output.pixelSize == CGSize(width: 18, height: 18))
        #expect(pixel(output.cgImage, x: 1, y: 1)[1] > 240)
    }

    @MainActor @Test func settingDefaultsOffAndResets() {
        let settings = AppSettings(store: InMemorySettingsStore())
        #expect(settings.windowBackground == false)
        settings.windowBackground = true
        settings.resetToDefaults()
        #expect(settings.windowBackground == false)
    }
}
