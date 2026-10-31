import AppKit
import Foundation
import ScreenCapKit

/// What the router drives. The app implements it with the coordinator and window controllers;
/// tests record the calls.
@MainActor
protocol AutomationHandling: AnyObject {
    /// `rect` is in global AppKit points; nil means the normal interactive flow.
    func capture(_ kind: CaptureKind, rect: CGRect?, action: AfterCaptureAction?)
    func post(_ name: Notification.Name, userInfo: [String: Any])
    func openFromClipboard()
    func openSettings(tab: AutomationCommand.SettingsTab?)
    func desktopIcons(_ change: DesktopIconsController.Change)
    func showError(_ message: String)
}

/// Parses `screencap://` URLs and dispatches each command (PLAN §6, docs/url-scheme.md).
@MainActor
final class URLSchemeRouter {
    private let handler: AutomationHandling
    private let parser: URLSchemeParser
    private let displayFrames: @MainActor () -> [CGRect]

    init(
        handler: AutomationHandling,
        parser: URLSchemeParser = URLSchemeParser(),
        displayFrames: @escaping @MainActor () -> [CGRect]
    ) {
        self.handler = handler
        self.parser = parser
        self.displayFrames = displayFrames
    }

    /// Parses and runs a URL; parse errors go to `showError`.
    func open(_ url: URL) {
        do {
            route(try parser.parse(url))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            handler.showError("\(url.absoluteString)\n\(message)")
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func route(_ command: AutomationCommand) {
        switch command {
        case let .allInOne(region):
            capture(.allInOne, region: region, action: nil)
        case let .captureArea(region, action):
            capture(.area, region: region, action: action)
        case let .capturePreviousArea(action):
            handler.capture(.previousArea, rect: nil, action: action)
        case let .captureFullscreen(action):
            handler.capture(.fullscreen, rect: nil, action: action)
        case let .captureWindow(action):
            handler.capture(.window, rect: nil, action: action)
        case let .selfTimer(action):
            handler.capture(.selfTimer, rect: nil, action: action)
        case let .scrollingCapture(region, start, autoscroll):
            scrolling(region: region, start: start, autoscroll: autoscroll)
        case let .captureText(source, lineBreaks):
            captureText(source, lineBreaks: lineBreaks)
        case let .openAnnotate(file):
            handler.post(.openAnnotateRequested, userInfo: Self.fileInfo(file))
        case let .pin(file):
            handler.post(.pinRequested, userInfo: Self.fileInfo(file))
        case let .addQuickAccessOverlay(file):
            handler.post(.addQuickAccessOverlayRequested, userInfo: [AutomationKey.url: file])
        case .openFromClipboard:
            handler.openFromClipboard()
        case .openHistory:
            handler.post(.openHistoryRequested, userInfo: [:])
        case .restoreRecentlyClosed:
            handler.post(.restoreRecentlyClosedRequested, userInfo: [:])
        case .toggleDesktopIcons:
            handler.desktopIcons(.toggle)
        case .hideDesktopIcons:
            handler.desktopIcons(.hide)
        case .showDesktopIcons:
            handler.desktopIcons(.show)
        case let .openSettings(tab):
            handler.openSettings(tab: tab)
        }
    }

    // MARK: - Helpers

    private func capture(_ kind: CaptureKind, region: Region?, action: AfterCaptureAction?) {
        guard let region else {
            handler.capture(kind, rect: nil, action: action)
            return
        }
        guard let rect = globalRect(region) else { return }
        handler.capture(kind, rect: rect, action: action)
    }

    /// No region: the normal scrolling flow (select, then the scrolling feature takes over).
    /// With a region: hand it straight to the scrolling feature with the flags.
    private func scrolling(region: Region?, start: Bool, autoscroll: Bool) {
        guard let region else {
            handler.capture(.scrolling, rect: nil, action: nil)
            return
        }
        guard let rect = globalRect(region) else { return }
        handler.post(.scrollingCaptureRequested, userInfo: [
            AutomationKey.rect: NSValue(rect: rect), AutomationKey.start: start, AutomationKey.autoscroll: autoscroll
        ])
    }

    private func captureText(_ source: AutomationCommand.TextSource?, lineBreaks: Bool) {
        switch source {
        case nil:
            handler.capture(.text, rect: nil, action: nil)
        case let .file(url):
            handler.post(.captureTextRequested, userInfo: [
                AutomationKey.url: url, AutomationKey.lineBreaks: lineBreaks
            ])
        case let .region(region):
            guard let rect = globalRect(region) else { return }
            handler.post(.captureTextRequested, userInfo: [
                AutomationKey.rect: NSValue(rect: rect), AutomationKey.lineBreaks: lineBreaks
            ])
        }
    }

    private func globalRect(_ region: Region) -> CGRect? {
        let frames = displayFrames()
        if let rect = RegionMapper.globalRect(for: region, displayFrames: frames) { return rect }
        if frames.indices.contains(region.display - 1) {
            handler.showError("The region doesn't overlap display \(region.display).")
        } else {
            handler.showError("Display \(region.display) not found (\(frames.count) connected).")
        }
        return nil
    }

    private static func fileInfo(_ file: URL?) -> [String: Any] {
        file.map { [AutomationKey.url: $0] } ?? [:]
    }
}
