import AppKit
import Observation
import ScreenCapKit
import SwiftUI

/// What the control panel shows; the controller writes it, buttons call back.
@MainActor
@Observable
final class ScrollingPanelModel {
    var phase = ScrollingSession.Phase.idle
    var autoScroll = false
    var horizontal = false
    /// Stitched size in pixels, for the readout.
    var capturedSize = CGSize.zero

    @ObservationIgnored var onStart: () -> Void = {}
    @ObservationIgnored var onStop: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}
    @ObservationIgnored var onAutoScroll: (Bool) -> Void = { _ in }
    @ObservationIgnored var onHorizontal: (Bool) -> Void = { _ in }

    var readout: String {
        guard capturedSize.width > 0 else { return phase == .selecting ? "Ready" : "Waiting for frames…" }
        return "\(Int(capturedSize.width).formatted()) × \(Int(capturedSize.height).formatted()) px"
    }
}

/// Start / Auto-scroll / Stop / Cancel, plus the captured-length readout.
struct ScrollingControlView: View {
    @Bindable var model: ScrollingPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scrolling Capture").font(.headline)
            Toggle("Auto-scroll", isOn: Binding(get: { model.autoScroll }, set: { model.onAutoScroll($0) }))
                .disabled(model.phase == .finishing)
            Toggle("Horizontal", isOn: Binding(get: { model.horizontal }, set: { model.onHorizontal($0) }))
                .disabled(model.phase != .selecting)
            Text(model.readout)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { model.onCancel() }
                Spacer()
                if model.phase == .selecting {
                    Button("Start") { model.onStart() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Stop") { model.onStop() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.phase == .finishing)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(12)
        .frame(width: ScrollingPanelLayout.columnWidth)
    }
}

/// Draws the stitched image scaled to fit (`PreviewFit`).
final class ScrollingPreviewView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        // Pixels, not points: a 2x image would otherwise be shown at double size before fitting.
        let box = bounds.insetBy(dx: 6, dy: 6)
        let target = PreviewFit.rect(for: CGSize(width: image.width, height: image.height), in: box)
        context.interpolationQuality = .medium
        context.draw(image, in: target)
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: target.insetBy(dx: -0.5, dy: -0.5)).stroke()
    }
}

/// Dashed outline just outside the region. Click-through; our windows never appear in captures.
final class RegionBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemBlue.setStroke()
        path.stroke()
    }
}

/// A floating panel that takes clicks without activating the app, so the scrolled app keeps focus.
final class ScrollingPanel: NSPanel {
    init(frame: CGRect, titled: Bool) {
        let style: NSWindow.StyleMask = titled
            ? [.titled, .utilityWindow, .nonactivatingPanel, .fullSizeContentView]
            : [.borderless, .nonactivatingPanel]
        super.init(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        level = .statusBar
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        if titled {
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            isMovableByWindowBackground = true
        } else {
            isOpaque = false
            backgroundColor = .clear
            hasShadow = false
            ignoresMouseEvents = true
        }
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { styleMask.contains(.titled) }
    override var canBecomeMain: Bool { false }
}

/// Where the control and preview panels go beside the region. Pure, so it is unit-tested.
enum ScrollingPanelLayout {
    static let columnWidth: CGFloat = 220
    static let controlHeight: CGFloat = 170
    static let gap: CGFloat = 10

    /// A column right of the region if it fits on `screen`, else left, else inside the region's right edge.
    /// The control panel sits at the top of the column, the preview below it down to the region's bottom.
    static func frames(region: CGRect, screen: CGRect) -> (control: CGRect, preview: CGRect) {
        let width = columnWidth
        let x: CGFloat
        if region.maxX + gap + width <= screen.maxX {
            x = region.maxX + gap
        } else if region.minX - gap - width >= screen.minX {
            x = region.minX - gap - width
        } else {
            x = max(screen.minX, region.maxX - width - gap)
        }
        let top = min(region.maxY, screen.maxY)
        let control = CGRect(x: x, y: top - controlHeight, width: width, height: controlHeight)
        let bottom = max(region.minY, screen.minY)
        let previewHeight = max(120, control.minY - gap - bottom)
        let preview = CGRect(x: x, y: max(screen.minY, control.minY - gap - previewHeight),
                             width: width, height: previewHeight)
        return (control, preview)
    }
}
