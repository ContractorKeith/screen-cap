import CoreGraphics
import ScreenCapKit

/// How frames arrive during a scrolling capture.
enum ScrollingMode: Equatable, Sendable {
    /// The user scrolls; we stitch.
    case manual
    /// `AutoScroller` posts scroll-wheel events.
    case auto
}

/// Why a scrolling capture stopped.
enum ScrollingStopReason: Equatable, Sendable {
    /// Consecutive still frames while auto-scrolling, confirmed by a probe scroll (`ScrollingFrameLoop`).
    case endReached
    /// The stitcher hit the max length.
    case maxLengthReached
    /// Stop button.
    case stopped
    /// Esc key.
    case escape
    /// A frame couldn't be captured (permission revoked, display gone); what was stitched is kept.
    case failed
    /// The display configuration changed (resolution, scale, a display added or removed): the
    /// region no longer covers the same pixels, so what was stitched before is kept (#127).
    case displayChanged
}

/// Scrolling capture state machine. Pure, so it is unit-tested; the controller drives the UI from it.
///
/// idle → selecting → capturing(manual|auto) → finishing → done, or cancelled from any live phase.
struct ScrollingSession: Equatable {
    enum Phase: Equatable {
        case idle
        /// Region chosen (or being chosen); waiting for Start.
        case selecting
        case capturing(ScrollingMode)
        /// Stopped; the stitched image is being built and delivered.
        case finishing
        case done
        case cancelled
    }

    private(set) var phase = Phase.idle
    private(set) var stopReason: ScrollingStopReason?
    /// Auto-scroll toggle. Switching it mid-capture changes the mode.
    private(set) var autoScroll: Bool
    /// Scroll axis. Fixed once capturing starts.
    private(set) var axis: ScrollAxis
    /// Consecutive unchanged frames that end an auto-scroll.
    static let stillFramesToEnd = 2
    private var stopRule = AutoScrollStopRule(noMovementLimit: stillFramesToEnd)

    init(autoScroll: Bool = false, axis: ScrollAxis = .vertical) {
        self.autoScroll = autoScroll
        self.axis = axis
    }

    var isCapturing: Bool {
        if case .capturing = phase { return true }
        return false
    }

    var mode: ScrollingMode? {
        if case let .capturing(mode) = phase { return mode }
        return nil
    }

    /// True once the session can no longer change.
    var isFinal: Bool { phase == .done || phase == .cancelled }

    mutating func beginSelection() {
        guard phase == .idle else { return }
        phase = .selecting
    }

    /// Starts capturing in the mode the toggle selects. Returns the mode, or nil if not selecting.
    @discardableResult
    mutating func start() -> ScrollingMode? {
        guard phase == .selecting else { return nil }
        let mode: ScrollingMode = autoScroll ? .auto : .manual
        stopRule = AutoScrollStopRule(noMovementLimit: Self.stillFramesToEnd)
        phase = .capturing(mode)
        return mode
    }

    mutating func setAutoScroll(_ isOn: Bool) {
        guard !isFinal, phase != .finishing else { return }
        autoScroll = isOn
        if isCapturing {
            stopRule = AutoScrollStopRule(noMovementLimit: Self.stillFramesToEnd)
            phase = .capturing(isOn ? .auto : .manual)
        }
    }

    /// The axis can only change before capturing starts.
    mutating func setAxis(_ axis: ScrollAxis) {
        guard phase == .idle || phase == .selecting else { return }
        self.axis = axis
    }

    /// Auto-scroll was refused (no Accessibility permission): continue manually.
    mutating func accessibilityDenied() {
        autoScroll = false
        if mode == .auto { phase = .capturing(.manual) }
    }

    /// Feeds one stitcher outcome. Returns true when the capture should stop. `frameChanged`
    /// (the content moved since the previous frame) is the evidence for the end; see `AutoScrollStopRule`.
    ///
    /// Max length stops either mode; still frames only end an auto-scroll (a manual user may pause).
    @discardableResult
    mutating func record(_ outcome: Stitcher.AppendOutcome, frameChanged: Bool? = nil) -> Bool {
        guard let mode else { return false }
        let reason = stopRule.record(outcome, frameChanged: frameChanged)
        switch reason {
        case .maxLengthReached:
            finish(.maxLengthReached)
        case .endReached where mode == .auto:
            finish(.endReached)
        case .endReached, .cancelled, nil:
            return false
        }
        return true
    }

    /// Stop button: keep what was captured. Before Start there is nothing to keep, so it cancels.
    mutating func stop() {
        if isCapturing { finish(.stopped) } else { cancel() }
    }

    /// Esc behaves like Stop.
    mutating func escape() {
        if isCapturing { finish(.escape) } else { cancel() }
    }

    /// A frame capture failed: stop and keep what was stitched. Before Start it cancels.
    mutating func fail() {
        if isCapturing { finish(.failed) } else { cancel() }
    }

    /// The displays changed mid-capture: stop and keep what was stitched. Before Start it cancels.
    mutating func displayChanged() {
        if isCapturing { finish(.displayChanged) } else { cancel() }
    }

    mutating func cancel() {
        guard !isFinal else { return }
        phase = .cancelled
    }

    /// The stitched image was built (`hasImage`) and handed off, or there was nothing to deliver.
    mutating func delivered(hasImage: Bool) {
        guard phase == .finishing else { return }
        phase = hasImage ? .done : .cancelled
    }

    private mutating func finish(_ reason: ScrollingStopReason) {
        stopReason = reason
        phase = .finishing
    }
}

/// Live preview geometry.
enum PreviewFit {
    /// The largest rect with `image`'s aspect ratio that fits inside `box`, centered.
    /// Never upscales past 1:1 (`maxScale`). Empty inputs give a zero rect at the box center.
    static func rect(for image: CGSize, in box: CGRect, maxScale: CGFloat = 1) -> CGRect {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else {
            return CGRect(x: box.midX, y: box.midY, width: 0, height: 0)
        }
        let scale = min(box.width / image.width, box.height / image.height, maxScale)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// Hidden launch options for scrolling capture, read from `CommandLine.arguments`:
/// `--region x,y,w,h` (global AppKit points) skips the selection and starts at once;
/// `--autoscroll on|off` overrides the default mode.
struct ScrollingLaunchOptions: Equatable {
    var region: CGRect?
    var autoScroll: Bool?

    static func parse(_ arguments: [String]) -> ScrollingLaunchOptions {
        var result = ScrollingLaunchOptions()
        for (index, argument) in arguments.enumerated() where index + 1 < arguments.count {
            let value = arguments[index + 1]
            switch argument {
            case "--region": result.region = parseRect(value)
            case "--autoscroll": result.autoScroll = ["on", "true", "1", "yes"].contains(value.lowercased())
            default: break
            }
        }
        return result
    }

    /// "x,y,w,h" with a positive size. Plain decimals only (x and y may be negative), so `nan`,
    /// `inf`, `1e309` and hex are rejected like the URL scheme's regions (#105).
    static func parseRect(_ text: String) -> CGRect? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { StrictNumber.signedDecimal($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4, let x = parts[0], let y = parts[1], let width = parts[2], let height = parts[3],
              width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
