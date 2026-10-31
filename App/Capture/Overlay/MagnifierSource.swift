import AppKit
import ScreenCapKit
import ScreenCaptureKit

/// Where the magnifier reads its pixels (#90).
enum MagnifierSource: Equatable {
    /// Magnifier hidden.
    case off
    /// Read from the overlay's frozen display still.
    case frozenStill
    /// Sample a small region under the pointer, live, on a throttle. No full-display grab (#62).
    case live
}

/// What one selection session grabs up front, and what feeds its magnifier (#62, #90).
struct OverlaySources: Equatable {
    /// Grab every display before showing the overlay and show those stills.
    let freezes: Bool
    let magnifier: MagnifierSource

    /// Self-timer never freezes: it captures live after the countdown.
    init(kind: CaptureKind, freezeScreen: Bool, showMagnifier: Bool) {
        freezes = freezeScreen && kind != .selfTimer
        magnifier = showMagnifier ? (freezes ? .frozenStill : .live) : .off
    }
}

/// Throttle for live magnifier samples: one request in flight, at most one start per `interval`.
struct LiveSampleThrottle {
    var interval: TimeInterval = 1.0 / 20
    private(set) var inFlight = false
    private(set) var lastStart: TimeInterval = -.infinity

    /// True (and marks a request in flight) if a sample may start at `now`.
    mutating func begin(now: TimeInterval) -> Bool {
        guard !inFlight, now - lastStart >= interval else { return false }
        inFlight = true
        lastStart = now
        return true
    }

    mutating func end() { inFlight = false }
}

/// Geometry of the live sample region.
enum LiveSample {
    /// Side of the sampled square, in points: covers the loupe's 15×15 pixels at 1x with slack for movement.
    static let side: CGFloat = 24

    /// A whole-point square of `side` centered on `point`, clipped to `display`; nil if nothing is left.
    static func rect(around point: CGPoint, in display: CGRect, side: CGFloat = side) -> CGRect? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let half = (side / 2).rounded(.down)
        let square = CGRect(x: point.x.rounded(.down) - half, y: point.y.rounded(.down) - half,
                            width: side, height: side)
        let clipped = square.intersection(display)
        return clipped.isNull || clipped.width < 1 || clipped.height < 1 ? nil : clipped
    }
}

/// Grabs a small live region of one display for the magnifier.
protocol PixelSampler: Sendable {
    func sample(pointRect: CGRect, display: DisplayInfo) async -> CapturedImage?
}

/// ScreenCaptureKit sampler: only the requested region is captured, with this app's windows
/// (the overlay itself) excluded. Shareable content is fetched once per session.
actor ScreenPixelSampler: PixelSampler {
    private let excludedBundleIdentifier: String?
    private var content: SCShareableContent?

    init(excludedBundleIdentifier: String? = Bundle.main.bundleIdentifier ?? ScreenCapKit.bundleIdentifier) {
        self.excludedBundleIdentifier = excludedBundleIdentifier
    }

    func sample(pointRect: CGRect, display: DisplayInfo) async -> CapturedImage? {
        do {
            let content = try await shareableContent()
            guard let screen = content.displays.first(where: { $0.displayID == display.id }) else { return nil }
            let own = content.applications.filter { $0.bundleIdentifier == excludedBundleIdentifier }
            let filter = SCContentFilter(display: screen, excludingApplications: own, exceptingWindows: [])
            let config = SCStreamConfiguration()
            // sourceRect is display-local points with a top-left origin.
            config.sourceRect = CGRect(x: pointRect.minX - display.frame.minX, y: display.frame.maxY - pointRect.maxY,
                                       width: pointRect.width, height: pointRect.height)
            config.width = max(Int((pointRect.width * display.backingScale).rounded()), 1)
            config.height = max(Int((pointRect.height * display.backingScale).rounded()), 1)
            config.captureResolution = .best
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return CapturedImage(cgImage: image, scale: display.backingScale, pointRect: pointRect,
                                 displayID: display.id)
        } catch {
            return nil
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        if let content { return content }
        let fresh = try await Self.fetchShareableContent().value
        content = fresh
        return fresh
    }

    /// Older SDKs (CI's macOS 15 runner) don't mark `SCShareableContent` Sendable; it is immutable.
    private nonisolated static func fetchShareableContent() async throws -> UncheckedSendable<SCShareableContent> {
        UncheckedSendable(try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true))
    }
}

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
