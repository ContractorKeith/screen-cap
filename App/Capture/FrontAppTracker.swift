import AppKit

/// The app a capture is "of", for History and `{app}` / `{window}` (#79).
struct FrontApp: Equatable, Sendable {
    var name: String?
    var processID: pid_t
}

/// Remembers the last app other than ScreenCap that was frontmost. A `screencap://` URL activates
/// ScreenCap before the router runs, so reading the frontmost app then would name ScreenCap itself.
@MainActor
final class FrontAppTracker {
    private let ownPID: pid_t
    private(set) var lastOther: FrontApp?
    private var observer: NSObjectProtocol?

    init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
        lastOther = Self.resolve(frontmost: Self.current, previous: nil, ownPID: ownPID)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                .map { FrontApp(name: $0.localizedName, processID: $0.processIdentifier) }
            MainActor.assumeIsolated {
                guard let self, let app, app.processID != self.ownPID else { return }
                self.lastOther = app
            }
        }
    }

    /// The frontmost app, or the last other one if ScreenCap is frontmost.
    var app: FrontApp? { Self.resolve(frontmost: Self.current, previous: lastOther, ownPID: ownPID) }

    private static var current: FrontApp? {
        NSWorkspace.shared.frontmostApplication.map {
            FrontApp(name: $0.localizedName, processID: $0.processIdentifier)
        }
    }

    nonisolated static func resolve(frontmost: FrontApp?, previous: FrontApp?, ownPID: pid_t) -> FrontApp? {
        guard let frontmost, frontmost.processID != ownPID else { return previous }
        return frontmost
    }
}
