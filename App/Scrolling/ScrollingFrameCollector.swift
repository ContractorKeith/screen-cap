import CoreGraphics
import Foundation
import ScreenCapKit

/// Where scrolling capture gets its stills. `CaptureService` in the app; a fake in tests.
protocol ScrollingFrameSource: Sendable {
    func captureArea(pointRect: CGRect) async throws -> CapturedImage
}

extension CaptureService: ScrollingFrameSource {}

/// How a scrolling capture ended once the user stopped it or a frame failed.
enum ScrollingCaptureEnd {
    /// Deliver this image. `problem` is set when capture failed partway and this is what was
    /// stitched before it; `gapMarked` when the image has a seam marker (frames that didn't
    /// line up, or a held frame kept on stop).
    case image(CapturedImage, problem: String?, gapMarked: Bool)
    /// Nothing to deliver, because of this problem.
    case failed(String)

    static let buildFailed = "The stitched image couldn't be built. Try a shorter capture."
}

/// Grabs frames from a source and feeds them to a `Stitcher`; remembers the first capture
/// error so the controller can report it and still deliver what was stitched (#76).
@MainActor
final class ScrollingFrameCollector {
    private let source: any ScrollingFrameSource
    let region: CGRect
    let axis: ScrollAxis
    /// Cap on the stitched length, in points.
    let maxLength: Int
    private(set) var stitcher: Stitcher?
    private(set) var lastFrame: CapturedImage?
    /// The first capture error; no more frames are taken after it.
    private(set) var failure: (any Error)?
    /// Whether the last grabbed frame's pixels differ from the frame before it (true for the first).
    private(set) var lastFrameChanged = true
    /// A seam was marked while stitching.
    private(set) var hasGap = false
    /// Pixels of the last grabbed frame, to tell a still page from a moving one byte for byte.
    private var lastPixels: Data?

    init(source: any ScrollingFrameSource, region: CGRect, axis: ScrollAxis, maxLength: Int) {
        self.source = source
        self.region = region
        self.axis = axis
        self.maxLength = maxLength
    }

    /// Captures and appends one frame. `expectedStep` turns the frame's scale into the pixels
    /// auto-scroll moved since the last frame (nil when scrolling manually).
    /// Returns nil when the capture failed (`failure` is set).
    func grab(expectedStep: (CGFloat) -> Int?) async -> Stitcher.AppendOutcome? {
        guard failure == nil else { return nil }
        let frame: CapturedImage
        do {
            frame = try await source.captureArea(pointRect: region)
        } catch {
            failure = error
            return nil
        }
        let active = stitcher ?? Stitcher(axis: axis, scale: frame.scale,
                                           maxLength: Int(CGFloat(maxLength) * frame.scale))
        stitcher = active
        lastFrame = frame
        let pixels = Self.pixels(of: frame)
        lastFrameChanged = pixels == nil || pixels != lastPixels
        lastPixels = pixels
        await active.setExpectedStep(expectedStep(frame.scale))
        let outcome = await active.append(frame: frame.cgImage)
        if case .gapDetected = outcome { hasGap = true }
        return outcome
    }

    /// Captures a frame without stitching it and reports whether it differs from the last
    /// grabbed frame (an end-of-content probe). Nil when the capture failed (`failure` is set).
    func peekChanged() async -> Bool? {
        guard failure == nil else { return nil }
        do {
            let frame = try await source.captureArea(pointRect: region)
            let pixels = Self.pixels(of: frame)
            return pixels == nil || pixels != lastPixels
        } catch {
            failure = error
            return nil
        }
    }

    private static func pixels(of frame: CapturedImage) -> Data? {
        frame.cgImage.dataProvider?.data as Data?
    }

    /// Builds the final image. Nil frames and no failure means there is nothing to report.
    func finish() async -> ScrollingCaptureEnd? {
        let problem = failure.map { Self.describe($0) }
        guard let stitcher, let lastFrame else { return problem.map { .failed($0) } }
        let gapMarked = await stitcher.hasHeldFrame || hasGap
        guard let image = await stitcher.finish() else {
            return .failed(problem ?? ScrollingCaptureEnd.buildFailed)
        }
        let scale = lastFrame.scale
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let origin = CGPoint(x: region.minX, y: region.maxY - size.height)
        let captured = CapturedImage(cgImage: image, scale: scale, pointRect: CGRect(origin: origin, size: size),
                                     displayID: lastFrame.displayID)
        return .image(captured, problem: problem, gapMarked: gapMarked)
    }

    static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
