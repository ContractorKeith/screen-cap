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
    /// Whether the last grabbed frame differs from the one before beyond capture noise (true for the
    /// first): live captures can vary by a level or two between grabs of a still page (#126).
    private(set) var lastFrameChangedBeyondNoise = true
    /// The last grabbed frame is one flat color, give or take noise: blank space shows nothing
    /// moving, so it says nothing about where the content ends (#126).
    private(set) var lastFrameIsBlank = false
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
    /// auto-scroll posted since the last placed frame and the pixels of one step (nil when
    /// scrolling manually). Returns nil when the capture failed (`failure` is set).
    func grab(expectedStep: (CGFloat) -> (posted: Int, unit: Int)?) async -> Stitcher.AppendOutcome? {
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
        lastFrameChangedBeyondNoise = Self.differ(pixels, lastPixels)
        lastFrameIsBlank = Self.isBlank(pixels)
        lastPixels = pixels
        let motion = expectedStep(frame.scale)
        await active.setExpectedStep(motion?.posted, unit: motion?.unit)
        let outcome = await active.append(frame: frame.cgImage)
        if case .gapDetected = outcome { hasGap = true }
        return outcome
    }

    /// Waits for the page to finish redrawing after a scroll (#126): captures until two grabs in a
    /// row match within capture noise, at most `tries` times. Terminal animates its scrolling, and a
    /// frame taken mid-animation shows the page between two positions.
    /// False when a capture failed (`failure` is set).
    func settle(tries: Int) async -> Bool {
        guard failure == nil else { return false }
        var previous: Data?
        for _ in 0..<tries {
            do {
                let pixels = Self.pixels(of: try await source.captureArea(pointRect: region))
                if let previous, let pixels, !Self.differ(previous, pixels) { return true }
                previous = pixels
            } catch {
                failure = error
                return false
            }
        }
        return true
    }

    /// Captures a frame without stitching it and reports whether it differs from the last
    /// grabbed frame (an end-of-content probe). Nil when the capture failed (`failure` is set).
    func peekChanged() async -> Bool? {
        guard failure == nil else { return nil }
        do {
            let frame = try await source.captureArea(pointRect: region)
            return Self.differ(Self.pixels(of: frame), lastPixels)
        } catch {
            failure = error
            return nil
        }
    }

    /// Byte difference that counts as a change; capture noise moves channels by one or two.
    static let noiseLevel: UInt8 = 8

    /// Whether every pixel is within capture noise of the first one (false when missing).
    static func isBlank(_ pixels: Data?) -> Bool {
        guard let pixels, pixels.count >= 4 else { return false }
        return pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Bool in
            for index in 4..<bytes.count {
                let (value, first) = (bytes[index], bytes[index % 4])
                if (value > first ? value - first : first - value) > noiseLevel { return false }
            }
            return true
        }
    }

    /// Whether two bitmaps differ beyond capture noise; true when either is missing.
    static func differ(_ one: Data?, _ other: Data?) -> Bool {
        guard let one, let other, one.count == other.count else { return true }
        return one.withUnsafeBytes { (first: UnsafeRawBufferPointer) -> Bool in
            other.withUnsafeBytes { (second: UnsafeRawBufferPointer) -> Bool in
                for index in 0..<first.count {
                    let (left, right) = (first[index], second[index])
                    if (left > right ? left - right : right - left) > noiseLevel { return true }
                }
                return false
            }
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
