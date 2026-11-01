import AppKit
@testable import ScreenCap
import ScreenCapKit
import Testing

/// Exercise the controller wiring, rather than rebuilding its deletion decision (#150, #158).
@Suite("Quick Access delete routes", .serialized)
@MainActor
struct QuickAccessDeleteRouteTests {
    enum Route: CaseIterable {
        case command, toolbar, backspace, forwardDelete

        @MainActor func send(to controller: QuickAccessController, item: QuickAccessItem) throws {
            switch self {
            case .command:
                controller.perform(.delete, on: item)
            case .toolbar:
                let toolbar = item.panel.thumbnail.toolbar
                let button = try #require(toolbar.subviews.compactMap { $0 as? NSButton }
                    .first { $0.toolTip == QuickAccessCommand.delete.title })
                #expect(button.target === toolbar)
                let action = try #require(button.action)
                _ = toolbar.perform(action, with: button)
            case .backspace, .forwardDelete:
                let code = self == .backspace ? QuickAccessKeys.KeyCode.delete : QuickAccessKeys.KeyCode.forwardDelete
                let event = try Self.key(code)
                #expect(item.panel.onKey?(event) == true)
            }
        }

        static func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                         timestamp: 0, windowNumber: 0, context: nil, characters: "\u{8}",
                                         charactersIgnoringModifiers: "\u{8}", isARepeat: false, keyCode: code))
        }
    }

    @MainActor
    final class Fixture {
        let directory: URL
        let controller: QuickAccessController
        let item: QuickAccessItem
        let history: HistoryStore

        init() async throws {
            _ = NSApplication.shared
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("delete-route-\(UUID())")
            let temp = TempFiles(root: directory, processID: 1)
            let settings = AppSettings(store: InMemorySettingsStore())
            settings.quickAccess.autoCloseSeconds = nil
            history = try HistoryStore(directory: directory.appendingPathComponent("history"), retentionDays: nil)
            let output = CaptureOutput(settings: settings, temp: temp)
            controller = QuickAccessController(settings: settings, output: output,
                                               history: history, router: nil, temp: temp)
            let image = try #require(CaptureLogicTests.solidImage(width: 8, height: 8))
            let record = try await history.add(image: image, kind: .area)
            controller.show(QuickAccessItem.result(image: image, scale: 1, kind: .area,
                                                  context: FilenameTemplate.Context(), recordID: record.id))
            item = try #require(controller.items.first)
            // Match a focused panel without requiring a real keyboard or screen capture.
            item.panel.onFocusChange?(true)
            await item.prepareTask?.value
        }

        func cleanUp() {
            controller.remove(item, markClosed: false)
            item.panel.orderOut(nil)
            try? FileManager.default.removeItem(at: directory)
        }

        func settle() async throws {
            // Deletion is launched in a MainActor task; allow it to run before checking the panel.
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test(arguments: Route.allCases, [false, true])
    func unsavedCaptureAsksAndHonorsTheAnswer(route: Route, answer: Bool) async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        var promptCount = 0
        fixture.controller.askDelete = { [weak fixture] in
            guard let fixture else { return false }
            promptCount += 1
            #expect(fixture.controller.items.contains { $0 === fixture.item })
            return answer
        }
        try route.send(to: fixture.controller, item: fixture.item)
        try await fixture.settle()
        #expect(promptCount == 1)
        #expect(fixture.controller.items.contains { $0 === fixture.item } == !answer)
        #expect(await fixture.history.records().isEmpty == answer)
    }

    @Test(arguments: Route.allCases)
    func savedCaptureDeletesWithoutAsking(route: Route) async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        // A real, uniquely named file exercises the Trash path too.
        let url = fixture.directory.appendingPathComponent("delete-route-\(UUID()).png")
        try Data([0]).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash").appendingPathComponent(url.lastPathComponent))
        }
        fixture.item.savedURL = url
        var promptCount = 0
        fixture.controller.askDelete = { promptCount += 1; return false }
        try route.send(to: fixture.controller, item: fixture.item)
        try await fixture.settle()
        #expect(promptCount == 0)
        #expect(fixture.controller.items.isEmpty)
        #expect(await fixture.history.records().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: [QuickAccessKeys.KeyCode.delete, QuickAccessKeys.KeyCode.forwardDelete])
    func commandDeleteSkipsThePrompt(code: UInt16) async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        var promptCount = 0
        fixture.controller.askDelete = { promptCount += 1; return false }
        #expect(fixture.item.panel.onKey?(try Route.key(code, modifiers: .command)) == true)
        try await fixture.settle()
        #expect(promptCount == 0)
        #expect(fixture.controller.items.isEmpty)
        #expect(await fixture.history.records().isEmpty)
    }
}
