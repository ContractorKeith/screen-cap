import AppKit
import ScreenCapKit

/// Pinned screenshots: the `.pin` after-capture action, "Pin from Clipboard" and `pinRequested`.
///
/// Positions are remembered per history record for this session only, so re-pinning a capture
/// puts it back where it was.
@MainActor
final class PinController: CaptureSink {
    private let output: CaptureOutput
    private var pins: [(panel: PinPanel, result: CaptureResult)] = []
    private var sessionFrames: [UUID: NSRect] = [:]
    private var observer: NSObjectProtocol?

    init(output: CaptureOutput) {
        self.output = output
    }

    var lockedCount: Int { pins.filter { $0.panel.lockState == .locked }.count }

    /// Starts observing `pinRequested`.
    func install() {
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name.pinRequested, object: nil, queue: .main
        ) { [weak self] note in
            let result = note.userInfo?["result"] as? CaptureResult
            let url = note.userInfo?["url"] as? URL
            MainActor.assumeIsolated {
                guard let self else { return }
                if let result {
                    self.pin(result)
                } else if let url {
                    self.pin(contentsOf: url)
                }
            }
        }
    }

    func deliver(_ result: CaptureResult, action: AfterCaptureAction) async {
        pin(result)
    }

    // MARK: Sources

    func pinFromClipboard() {
        guard let image = NSImage(pasteboard: .general), let captured = Self.captured(image) else {
            HUDPanel.show("No image on the clipboard")
            return
        }
        pin(CaptureResult(image: captured, kind: .area, context: FilenameTemplate.Context()))
    }

    func pin(contentsOf url: URL) {
        guard let image = NSImage(contentsOf: url), let captured = Self.captured(image) else {
            appLog.error("Can't pin \(url.path, privacy: .public): not an image")
            return
        }
        let context = FilenameTemplate.Context(app: nil, window: url.deletingPathExtension().lastPathComponent)
        pin(CaptureResult(image: captured, kind: .area, context: context))
    }

    /// An NSImage as a CapturedImage, keeping its pixels-per-point so it pins at 1x points.
    private static func captured(_ image: NSImage) -> CapturedImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              image.size.width > 0 else { return nil }
        let scale = CGFloat(cgImage.width) / image.size.width
        return CapturedImage(cgImage: cgImage, scale: scale, pointRect: .zero, displayID: nil)
    }

    // MARK: Pins

    func pin(_ result: CaptureResult) {
        let image = result.image
        let pointSize = CGSize(width: image.pixelSize.width / image.scale, height: image.pixelSize.height / image.scale)
        let panel = PinPanel(image: image.cgImage, pointSize: pointSize, frame: initialFrame(for: result, pointSize))
        panel.onCommand = { [weak self] panel, command in self?.perform(command, on: panel) }
        panel.onFrameChange = { [weak self] panel in self?.remember(panel) }
        pins.append((panel, result))
        panel.orderFrontRegardless()
        panel.makeKey()
        appLog.notice("Pinned \(Int(pointSize.width))x\(Int(pointSize.height)) pt")
    }

    /// Last session frame for this capture; else over the captured area if it fits; else centered.
    private func initialFrame(for result: CaptureResult, _ pointSize: CGSize) -> NSRect {
        if let id = result.historyRecordID, let frame = sessionFrames[id] { return frame }
        let source = result.image.pointRect
        let screen = NSScreen.screens.first { !source.isEmpty && $0.frame.intersects(source) }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: pointSize)
        let fit = PinMath.fitScale(pointSize: pointSize, visibleFrame: visible.size)
        let size = PinMath.size(for: pointSize, scale: fit)
        var origin: NSPoint
        if fit >= 1, !source.isEmpty, visible.contains(source) {
            origin = source.origin
        } else {
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        }
        // Cascade so a new pin doesn't hide exactly behind an existing one.
        while pins.contains(where: { $0.panel.frame.origin == origin }) {
            origin.x += 20
            origin.y -= 20
        }
        return NSRect(origin: origin, size: size)
    }

    private func remember(_ panel: PinPanel) {
        guard let id = pins.first(where: { $0.panel === panel })?.result.historyRecordID else { return }
        sessionFrames[id] = panel.frame
    }

    private func perform(_ command: PinCommand, on panel: PinPanel) {
        guard let result = pins.first(where: { $0.panel === panel })?.result else { return }
        switch command {
        case .copy:
            Task {
                try? await output.copy(result)
                HUDPanel.show("Copied")
            }
        case .save:
            Task {
                do {
                    let url = try await output.save(result)
                    HUDPanel.show("Saved \(url.lastPathComponent)")
                } catch {
                    HUDPanel.show("Save failed")
                }
            }
        case .annotate:
            NotificationCenter.default.post(name: Notification.Name.openAnnotateRequested, object: self,
                                            userInfo: ["result": result])
        case .toggleLock:
            panel.apply(.toggleLock)
        case .close:
            remember(panel)
            panel.apply(.close)
            panel.close()
            pins.removeAll { $0.panel === panel }
        }
    }

    /// Menu-bar "Unlock All Pins".
    func unlockAll() {
        for pin in pins { pin.panel.apply(.unlockAll) }
    }
}
