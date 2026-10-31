import AppKit
@testable import ScreenCap
import ScreenCapKit
import Testing
import UniformTypeIdentifiers

/// One call the router made on its handler.
enum RouterCall: Equatable {
    case capture(ScreenCap.CaptureKind, CGRect?, AfterCaptureAction?)
    case post(Notification.Name, [String])
    case openFromClipboard
    case openSettings(AutomationCommand.SettingsTab?)
    case desktopIcons(DesktopIconsController.Change)
    case error
}

@Suite("URL scheme router")
@MainActor
struct URLSchemeRouterTests {
    /// Records every call the router makes.
    final class Recorder: AutomationHandling {
        var calls: [RouterCall] = []
        var infos: [[String: Any]] = []
        var errors: [String] = []

        func capture(_ kind: ScreenCap.CaptureKind, rect: CGRect?, action: AfterCaptureAction?) {
            calls.append(.capture(kind, rect, action))
        }

        func post(_ name: Notification.Name, userInfo: [String: Any]) {
            calls.append(.post(name, userInfo.keys.sorted()))
            infos.append(userInfo)
        }

        func openFromClipboard() { calls.append(.openFromClipboard) }
        func openSettings(tab: AutomationCommand.SettingsTab?) { calls.append(.openSettings(tab)) }
        func desktopIcons(_ change: DesktopIconsController.Change) { calls.append(.desktopIcons(change)) }

        func showError(_ message: String) {
            calls.append(.error)
            errors.append(message)
        }
    }

    /// Primary 1440×900 at the origin, a second 1920×1080 display to its left and higher up.
    static let frames = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                         CGRect(x: -1920, y: 200, width: 1920, height: 1080)]
    static let imagePath = "/tmp/shot.png"

    private func run(_ string: String) throws -> Recorder {
        let recorder = Recorder()
        let files = StubFileChecker()
        let router = URLSchemeRouter(handler: recorder, parser: URLSchemeParser(fileChecker: files),
                                     displayFrames: { Self.frames })
        router.open(try #require(URL(string: string)))
        return recorder
    }

    private func calls(_ string: String) throws -> [RouterCall] {
        try run(string).calls
    }

    // MARK: - Captures

    @Test func capturesWithoutRegionUseTheInteractiveFlow() throws {
        #expect(try calls("screencap://capture-area") == [.capture(.area, nil, nil)])
        #expect(try calls("screencap://capture-area?action=copy") == [.capture(.area, nil, .copy)])
        #expect(try calls("screencap://capture-previous-area?action=pin") == [.capture(.previousArea, nil, .pin)])
        #expect(try calls("screencap://capture-fullscreen?action=save") == [.capture(.fullscreen, nil, .save)])
        #expect(try calls("screencap://capture-window?action=annotate") == [.capture(.window, nil, .annotate)])
        #expect(try calls("screencap://self-timer") == [.capture(.selfTimer, nil, nil)])
        #expect(try calls("screencap://self-timer?action=overlay") == [.capture(.selfTimer, nil, .overlay)])
        #expect(try calls("screencap://all-in-one") == [.capture(.allInOne, nil, nil)])
    }

    @Test func regionsMapToGlobalRects() throws {
        #expect(try calls("screencap://capture-area?x=10&y=20&width=300&height=200&action=save")
            == [.capture(.area, CGRect(x: 10, y: 20, width: 300, height: 200), .save)])
        #expect(try calls("screencap://capture-area?x=10&y=20&width=300&height=200&display=2")
            == [.capture(.area, CGRect(x: -1910, y: 220, width: 300, height: 200), nil)])
        #expect(try calls("screencap://all-in-one?x=0&y=0&width=100&height=50")
            == [.capture(.allInOne, CGRect(x: 0, y: 0, width: 100, height: 50), nil)])
    }

    @Test func missingDisplayIsAnError() throws {
        let recorder = try run("screencap://capture-area?x=0&y=0&width=10&height=10&display=3")
        #expect(recorder.calls == [.error])
        #expect(recorder.errors.first?.contains("Display 3") == true)
    }

    @Test func regionOffTheDisplayIsAnError() throws {
        #expect(try calls("screencap://capture-area?x=5000&y=0&width=10&height=10") == [.error])
    }

    /// Half off the 1440-pt display: rejected, not clipped to a 40-pt image (#59).
    @Test func regionPartlyOffTheDisplayIsAnError() throws {
        let recorder = try run("screencap://capture-area?x=1400&y=0&width=400&height=200&action=save")
        #expect(recorder.calls == [.error])
        #expect(recorder.errors.first?.contains("doesn't fit inside display 1 (1440×900 points)") == true)
        #expect(try calls("screencap://scrolling-capture?x=0&y=800&width=100&height=200") == [.error])
        #expect(try calls("screencap://capture-text?x=0&y=0&width=1441&height=10") == [.error])
        #expect(try calls("screencap://all-in-one?x=1900&y=0&width=100&height=100&display=2") == [.error])
        // Touching the edges exactly is inside.
        #expect(try calls("screencap://capture-area?x=0&y=0&width=1440&height=900")
            == [.capture(.area, CGRect(x: 0, y: 0, width: 1440, height: 900), nil)])
    }

    @Test func scrolling() throws {
        #expect(try calls("screencap://scrolling-capture") == [.capture(.scrolling, nil, nil)])
        let recorder = try run("screencap://scrolling-capture?x=200&y=100&width=900&height=700&start=true")
        #expect(recorder.calls == [.post(.scrollingCaptureRequested, ["autoscroll", "rect", "start"])])
        let info = try #require(recorder.infos.first)
        #expect((info["rect"] as? NSValue)?.rectValue == CGRect(x: 200, y: 100, width: 900, height: 700))
        #expect(info["start"] as? Bool == true)
        #expect(info["autoscroll"] as? Bool == false)
    }

    @Test func captureText() throws {
        #expect(try calls("screencap://capture-text") == [.capture(.text, nil, nil)])
        let file = try run("screencap://capture-text?filepath=\(Self.imagePath)&linebreaks=false")
        #expect(file.calls == [.post(.captureTextRequested, ["lineBreaks", "url"])])
        #expect((file.infos.first?["url"] as? URL)?.path == Self.imagePath)
        #expect(file.infos.first?["lineBreaks"] as? Bool == false)
        let region = try run("screencap://capture-text?x=0&y=0&width=500&height=200")
        #expect(region.calls == [.post(.captureTextRequested, ["lineBreaks", "rect"])])
        #expect((region.infos.first?["rect"] as? NSValue)?.rectValue == CGRect(x: 0, y: 0, width: 500, height: 200))
    }

    // MARK: - Files and windows

    @Test func fileCommandsPostTheirNotification() throws {
        let annotate = try run("screencap://open-annotate?filepath=\(Self.imagePath)")
        #expect(annotate.calls == [.post(.openAnnotateRequested, ["url"])])
        #expect((annotate.infos.first?["url"] as? URL)?.path == Self.imagePath)
        #expect(try calls("screencap://open-annotate") == [.post(.openAnnotateRequested, [])])
        #expect(try calls("screencap://pin?filepath=\(Self.imagePath)") == [.post(.pinRequested, ["url"])])
        #expect(try calls("screencap://pin") == [.post(.pinRequested, [])])
        #expect(try calls("screencap://add-quick-access-overlay?filepath=\(Self.imagePath)")
            == [.post(.addQuickAccessOverlayRequested, ["url"])])
    }

    @Test func noParameterCommands() throws {
        #expect(try calls("screencap://open-from-clipboard") == [.openFromClipboard])
        #expect(try calls("screencap://open-history") == [.post(.openHistoryRequested, [])])
        #expect(try calls("screencap://restore-recently-closed") == [.post(.restoreRecentlyClosedRequested, [])])
        #expect(try calls("screencap://toggle-desktop-icons") == [.desktopIcons(.toggle)])
        #expect(try calls("screencap://hide-desktop-icons") == [.desktopIcons(.hide)])
        #expect(try calls("screencap://show-desktop-icons") == [.desktopIcons(.show)])
    }

    @Test func openSettings() throws {
        #expect(try calls("screencap://open-settings") == [.openSettings(nil)])
        #expect(try calls("screencap://open-settings?tab=advanced") == [.openSettings(.advanced)])
        #expect(try calls("screencap://open-settings?tab=quickaccess") == [.openSettings(.quickAccess)])
        #expect(try calls("screencap://open-settings?tab=text") == [.openSettings(.text)])
        let history = try run("screencap://open-settings?tab=history")
        #expect(history.calls == [.error])
        #expect(history.errors.first?.contains("Invalid value \"history\" for \"tab\"") == true)
    }

    @Test func parseErrorsShowTheirDescription() throws {
        let recorder = try run("screencap://capture-area?acton=copy")
        #expect(recorder.calls == [.error])
        #expect(recorder.errors.first?.contains("Unknown parameter \"acton\"") == true)
        #expect(try calls("screencap://nope") == [.error])
        #expect(try calls("screencap://capture-area?action=Copy") == [.error])
    }

    // MARK: - Region mapping

    @Test func regionMapperUsesLowerLeftOriginAndOneBasedDisplays() {
        let region = Region(x: 0, y: 0, width: 100, height: 100, display: 2)
        #expect(RegionMapper.globalRect(for: region, displayFrames: Self.frames)
            == CGRect(x: -1920, y: 200, width: 100, height: 100))
        let top = Region(x: 1340, y: 800, width: 100, height: 100)
        #expect(RegionMapper.globalRect(for: top, displayFrames: Self.frames)
            == CGRect(x: 1340, y: 800, width: 100, height: 100))
        #expect(RegionMapper.globalRect(for: Region(x: 0, y: 0, width: 1, height: 1, display: 0),
                                        displayFrames: Self.frames) == nil)
        #expect(RegionMapper.globalRect(for: region, displayFrames: []) == nil)
        let partial = Region(x: 1400, y: 0, width: 400, height: 200)
        #expect(RegionMapper.globalRect(for: partial, displayFrames: Self.frames) == nil)
    }
}

/// Every path exists and is a PNG.
struct StubFileChecker: FileChecker {
    func isReadableFile(at url: URL) -> Bool { true }
    func contentType(of url: URL) -> UTType? { .png }
}
