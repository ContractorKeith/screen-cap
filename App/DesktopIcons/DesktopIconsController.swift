import AppKit
import QuartzCore

/// Hides desktop icons by covering each screen with a borderless window that draws the
/// current wallpaper, just above Finder's icon layer and below every app window.
/// Finder's own defaults are never touched, so quitting (or crashing) brings the icons back.
@MainActor
final class DesktopIconsController {
    /// What the URL scheme and menu can ask for.
    enum Change: Equatable, Sendable {
        case hide, show, toggle
    }

    /// Above the desktop icons, below normal windows.
    static let coverLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    private(set) var isHidden = false
    /// True while hidden only for the duration of a capture.
    private var isTemporary = false
    private var covers: [NSWindow] = []
    private var observers: [NSObjectProtocol] = []

    /// Window numbers of the covers, so captures keep them despite excluding our own app.
    var coverWindowIDs: Set<CGWindowID> {
        Set(covers.map { CGWindowID($0.windowNumber) })
    }

    func apply(_ change: Change) {
        switch change {
        case .hide: hide()
        case .show: show()
        case .toggle:
            if isHidden && !isTemporary { show() } else { hide() }
        }
    }

    func hide() {
        isTemporary = false
        guard !isHidden else { return }
        isHidden = true
        rebuildCovers()
        observeChanges()
        appLog.notice("Desktop icons hidden on \(self.covers.count) screen(s)")
    }

    func show() {
        isTemporary = false
        guard isHidden else { return }
        isHidden = false
        covers.forEach { $0.orderOut(nil) }
        covers.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        appLog.notice("Desktop icons shown")
    }

    /// Hides for one capture. Returns false (and does nothing) if already hidden.
    func beginTemporaryHide() -> Bool {
        guard !isHidden else { return false }
        hide()
        isTemporary = true
        return true
    }

    /// Ends a temporary hide; a hide the user asked for in between is kept.
    func endTemporaryHide() {
        if isTemporary { show() }
    }

    // MARK: - Covers

    private func rebuildCovers() {
        covers.forEach { $0.orderOut(nil) }
        covers = NSScreen.screens.map(Self.makeCover)
        covers.forEach { $0.orderFront(nil) }
    }

    private static func makeCover(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = coverLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.title = "Desktop Cover"
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        Self.drawWallpaper(of: screen, into: view)
        window.contentView = view
        return window
    }

    /// Mirrors the desktop picture's scaling options as closely as a layer allows.
    private static func drawWallpaper(of screen: NSScreen, into view: NSView) {
        let workspace = NSWorkspace.shared
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        let fill = options[.fillColor] as? NSColor ?? .black
        view.layer?.backgroundColor = fill.cgColor
        guard let url = workspace.desktopImageURL(for: screen), let image = NSImage(contentsOf: url) else { return }
        view.layer?.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) }
        let clips = (options[.allowClipping] as? NSNumber)?.boolValue ?? true
        view.layer?.contentsGravity = switch scaling {
        case .scaleAxesIndependently: .resize
        case .scaleNone: .center
        case .scaleProportionallyDown: .resizeAspect
        default: clips ? .resizeAspectFill : .resizeAspect
        }
    }

    /// Rebuilds on display changes and Space switches (each Space can have its own wallpaper).
    private func observeChanges() {
        let rebuild: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { if self?.isHidden == true { self?.rebuildCovers() } }
        }
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: rebuild
            ),
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: rebuild
            )
        ]
    }
}
