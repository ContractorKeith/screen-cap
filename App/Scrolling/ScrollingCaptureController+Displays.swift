import AppKit

// MARK: - Display changes

extension ScrollingCaptureController {
    /// A resolution or scale change, or a display added or removed, moves the region off the pixels
    /// it covered: frames stop lining up and auto-scroll would run forever (#127). End the capture
    /// and keep what was stitched; before Start, cancel.
    func watchDisplays() {
        guard displayObserver == nil else { return }
        displayObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        }
    }

    func unwatchDisplays() {
        displayObserver.map(notificationCenter.removeObserver)
        displayObserver = nil
    }
}

extension ScrollingCaptureController {
    static let displayChangedTitle = "Display changed, capture stopped"
    static let displayChangedProblem = "The display configuration changed during the scrolling capture."
}
