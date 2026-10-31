import AppKit
@testable import ScreenCap
import Testing

@Suite("Menu model")
@MainActor
struct MenuModelTests {
    /// Records what the menu triggered.
    final class Recorder {
        var captures: [CaptureKind] = []
        var timers: [Int] = []
        var calls: [String] = []
        var timerSeconds = 5
    }

    private func actions(_ recorder: Recorder) -> AppMenu.Actions {
        AppMenu.Actions(
            capture: { recorder.captures.append($0) },
            selfTimer: { recorder.timers.append($0) },
            selfTimerSeconds: { recorder.timerSeconds },
            openSettings: { recorder.calls.append("settings") },
            openOnboarding: { recorder.calls.append("onboarding") },
            toggleLaunchAtLogin: { recorder.calls.append("login") },
            launchAtLoginIsOn: { true },
            quit: { recorder.calls.append("quit") }
        )
    }

    private func fire(_ item: NSMenuItem?) {
        (item?.representedObject as? MenuActionHandler)?.fire(nil)
    }

    @Test func topLevelLayout() {
        let menu = MenuBuilder.menu(from: AppMenu.entries(actions(Recorder())))
        let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(titles == [
            "Capture Area", "Capture Window", "Capture Fullscreen", "All-In-One", "Capture", "-",
            "Screen Recording Permission…", "Launch at Login", "Settings…", "-", "Quit ScreenCap"
        ])
        #expect(menu.item(withTitle: "Settings…")?.keyEquivalent == ",")
        #expect(menu.item(withTitle: "Quit ScreenCap")?.keyEquivalent == "q")
    }

    @Test func itemsRunTheirActions() {
        let recorder = Recorder()
        let menu = MenuBuilder.menu(from: AppMenu.entries(actions(recorder)))
        fire(menu.item(withTitle: "Capture Window"))
        fire(menu.item(withTitle: "Capture Fullscreen"))
        fire(menu.item(withTitle: "Settings…"))
        fire(menu.item(withTitle: "Quit ScreenCap"))
        #expect(recorder.captures == [.window, .fullscreen])
        #expect(recorder.calls == ["settings", "quit"])
    }

    @Test func captureSubmenuHoldsTheRest() throws {
        let recorder = Recorder()
        let menu = MenuBuilder.menu(from: AppMenu.entries(actions(recorder)))
        let submenu = try #require(menu.item(withTitle: "Capture")?.submenu)
        #expect(submenu.items.map(\.title) == [
            "Capture Previous Area", "Self-Timer", "Scrolling Capture", "Capture Text", "",
            "Pin from Clipboard", "Unlock All Pins"
        ])
        let timer = try #require(submenu.item(withTitle: "Self-Timer")?.submenu)
        fire(timer.item(withTitle: "Start"))
        fire(timer.item(withTitle: "10 seconds"))
        #expect(recorder.captures == [.selfTimer])
        #expect(recorder.timers == [10])
    }

    @Test func checkmarksRefreshWhenStateChanges() throws {
        let recorder = Recorder()
        let menu = MenuBuilder.menu(from: AppMenu.entries(actions(recorder)))
        let timer = try #require(menu.item(withTitle: "Capture")?.submenu?.item(withTitle: "Self-Timer")?.submenu)
        #expect(timer.item(withTitle: "5 seconds")?.state == .on)
        #expect(timer.item(withTitle: "3 seconds")?.state == .off)
        recorder.timerSeconds = 3
        MenuBuilder.refreshStates(in: menu)
        #expect(timer.item(withTitle: "3 seconds")?.state == .on)
        #expect(timer.item(withTitle: "5 seconds")?.state == .off)
        #expect(menu.item(withTitle: "Launch at Login")?.state == .on)
    }

    @Test func customEntriesBuild() {
        var fired = false
        let menu = MenuBuilder.menu(from: [
            .item(MenuAction("One") { fired = true }),
            .separator,
            .submenu("More", [.item(MenuAction("Two") {})])
        ])
        #expect(menu.items.count == 3)
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items[2].submenu?.items.first?.title == "Two")
        fire(menu.items[0])
        #expect(fired)
    }
}
