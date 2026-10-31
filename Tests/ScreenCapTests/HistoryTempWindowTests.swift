import AppKit
import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// History write failures (#113), temp-file cleanup (#114), Settings placement (#115) and the
/// capped Quick Access stack (#116).
@Suite("History failures, temp files, on-screen windows")
@MainActor
struct HistoryTempWindowTests {
    // MARK: - Helpers

    final class WarningLog {
        var messages: [String] = []
    }

    final class ResultSink: CaptureSink {
        var results: [CaptureResult] = []
        func deliver(_ result: CaptureResult, action: AfterCaptureAction) async { results.append(result) }
    }

    private func tempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func setReadOnly(_ url: URL, _ readOnly: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: readOnly ? 0o555 : 0o755], ofItemAtPath: url.path)
    }

    private func contents(_ url: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    }

    private func capture(_ coordinator: CaptureCoordinator) async {
        await coordinator.capture(.area, rect: CGRect(x: 0, y: 0, width: 8, height: 8), action: .overlay)?.value
    }

    private func coordinator(history: HistoryStore?, warnings: WarningLog)
        -> (CaptureCoordinator, ResultSink) {
        let settings = AppSettings(store: InMemorySettingsStore())
        let coordinator = CaptureCoordinator(settings: settings, source: CaptureCoordinatorTests.FakeSource(),
                                             history: history, hasPermission: { true }, showOnboarding: {})
        coordinator.showsQuickAccess = { true }
        let sink = ResultSink()
        coordinator.sink = sink
        coordinator.alerts = CaptureAlerts(busy: {}, outputFailed: { _, _, _, _ in },
                                           historyFailed: { warnings.messages.append($0) })
        return (coordinator, sink)
    }

    /// Closes every panel, including any that URL-scheme tests running alongside open through
    /// notifications, and waits for their drag copies.
    private func closeAll(_ controller: QuickAccessController) async {
        while let item = controller.items.first {
            let task = item.prepareTask
            controller.remove(item, markClosed: false)
            await task?.value
        }
    }

    private func image() throws -> CapturedImage {
        let cgImage = try #require(CaptureLogicTests.solidImage(width: 8, height: 8))
        return CapturedImage(cgImage: cgImage, scale: 1, pointRect: .zero, displayID: nil)
    }

    // MARK: - #113 History write failures

    @Test func readOnlyHistoryFolderNamesTheCause() async throws {
        let directory = try tempDirectory("history-ro")
        let store = try HistoryStore(directory: directory, retentionDays: nil)
        try setReadOnly(directory, true)
        defer { try? setReadOnly(directory, false); try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: HistoryError.self) {
            try await store.add(image: try image().cgImage, kind: .area)
        }
        do {
            try await store.add(image: try image().cgImage, kind: .area)
        } catch {
            #expect(error.localizedDescription.contains("History folder can't be written to"))
        }
    }

    @Test func failedHistoryWriteKeepsCaptureAndWarnsOnce() async throws {
        let directory = try tempDirectory("history-ro")
        let store = try HistoryStore(directory: directory, retentionDays: nil)
        try setReadOnly(directory, true)
        defer { try? setReadOnly(directory, false); try? FileManager.default.removeItem(at: directory) }
        let warnings = WarningLog()
        let (coordinator, sink) = coordinator(history: store, warnings: warnings)
        await capture(coordinator)
        await capture(coordinator)
        // Both still reach Quick Access, marked as not in History.
        #expect(sink.results.count == 2)
        #expect(sink.results.allSatisfy { $0.historyWriteFailed && $0.historyRecordID == nil })
        #expect(warnings.messages.count == 1)
        #expect(warnings.messages.first?.contains("History isn't being saved") == true)
        #expect(warnings.messages.first?.contains("can't be written to") == true)
    }

    @Test func historyThatFailedToOpenWarnsOnFirstCapture() async throws {
        let warnings = WarningLog()
        let (coordinator, sink) = coordinator(history: nil, warnings: warnings)
        coordinator.historyOpenError = HistoryError.folderNotWritable("~/History")
        await capture(coordinator)
        #expect(sink.results.first?.historyWriteFailed == true)
        #expect(warnings.messages.count == 1)
    }

    @Test func noHistoryByDesignDoesNotWarn() async throws {
        let warnings = WarningLog()
        let (coordinator, sink) = coordinator(history: nil, warnings: warnings)
        await capture(coordinator)
        #expect(sink.results.first?.historyWriteFailed == false)
        #expect(warnings.messages.isEmpty)
    }

    @Test func projectFileErrorsAreReadable() {
        let message = ProjectFileError.imageEncodingFailed("x.png").localizedDescription
        #expect(message.contains("x.png"))
        #expect(!message.contains("error 4"))
    }

    @Test func onlyCopyNeverAutoClosesUntilSaved() throws {
        let panel = QuickAccessPanel(image: try image().cgImage, size: CGSize(width: 100, height: 100))
        var result = CaptureResult(image: try image(), kind: .area, context: FilenameTemplate.Context())
        result.historyWriteFailed = true
        let item = QuickAccessItem(result: result, panel: panel, timer: AutoCloseTimer(seconds: nil, now: Date()))
        #expect(item.isOnlyCopy)
        item.savedURL = URL(fileURLWithPath: "/tmp/x.png")
        #expect(!item.isOnlyCopy)
    }

    // MARK: - #114 Temp files

    @Test func releasingAPanelEmptiesItsFolder() async throws {
        let root = try tempDirectory("tempfiles")
        defer { try? FileManager.default.removeItem(at: root) }
        let temp = TempFiles(root: root, processID: 1)
        let settings = AppSettings(store: InMemorySettingsStore())
        let output = CaptureOutput(settings: settings, temp: temp)
        let controller = QuickAccessController(settings: settings, output: output, history: nil, router: nil,
                                               temp: temp)
        controller.show(CaptureResult(image: try image(), kind: .area, context: FilenameTemplate.Context()))
        let item = try #require(controller.items.first)
        await item.prepareTask?.value
        #expect(item.drag.fileURL != nil)
        #expect(!contents(temp.launchFolder).isEmpty)
        let folder = try #require(item.drag.fileURL?.deletingLastPathComponent())
        controller.remove(item, markClosed: false)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        await closeAll(controller)
        #expect(contents(temp.launchFolder).isEmpty)
        #expect(temp.trackedURLs.isEmpty)
    }

    @Test func panelClosedBeforeDragIsReadyLeavesNothing() async throws {
        let root = try tempDirectory("tempfiles")
        defer { try? FileManager.default.removeItem(at: root) }
        let temp = TempFiles(root: root, processID: 1)
        let settings = AppSettings(store: InMemorySettingsStore())
        let output = CaptureOutput(settings: settings, temp: temp)
        let controller = QuickAccessController(settings: settings, output: output, history: nil, router: nil,
                                               temp: temp)
        controller.show(CaptureResult(image: try image(), kind: .area, context: FilenameTemplate.Context()))
        let item = try #require(controller.items.first)
        let task = item.prepareTask
        controller.remove(item, markClosed: false)
        await task?.value
        await closeAll(controller)
        #expect(contents(temp.launchFolder).isEmpty)
    }

    @Test func copyAsFileIsReplacedAndRemovedWithItsRecord() async throws {
        let root = try tempDirectory("tempfiles")
        defer { try? FileManager.default.removeItem(at: root) }
        let temp = TempFiles(root: root, processID: 1)
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.imageFormat = .png
        let output = CaptureOutput(settings: settings, temp: temp)
        var result = CaptureResult(image: try image(), kind: .area, context: FilenameTemplate.Context())
        let record = UUID()
        result.historyRecordID = record
        let first = try await output.writeTemporaryFile(result)
        let second = try await output.writeTemporaryFile(result)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        temp.release(records: [record])
        #expect(contents(temp.launchFolder).isEmpty)
    }

    @Test func quitRemovesTheLaunchFolderAndLaunchPurgesStaleOnes() throws {
        let root = try tempDirectory("tempfiles")
        defer { try? FileManager.default.removeItem(at: root) }
        // Left by an old build, a dead launch and a running copy (this test process).
        try Data().write(to: root.appendingPathComponent("ScreenCap old.png"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("QuickAccess/x"),
                                                withIntermediateDirectories: true)
        let live = "launch-\(ProcessInfo.processInfo.processIdentifier)"
        for name in ["launch-999999", live] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name),
                                                    withIntermediateDirectories: true)
        }
        let temp = TempFiles(root: root, processID: 2)
        let folder = try temp.makeFolder()
        temp.purgeStale()
        #expect(Set(contents(root)) == [live, "launch-2"])
        #expect(FileManager.default.fileExists(atPath: folder.path))
        temp.removeAll()
        #expect(contents(root) == [live])
    }

    // MARK: - #115 Settings window on a 13" display

    /// 1470 × 956 pt with the menu bar (and no Dock) taken off.
    let air13 = CGRect(x: 0, y: 0, width: 1470, height: 956 - 37)

    @Test func settingsOpensFullyOnA13InchDisplay() {
        let frame = WindowPlacement.centered(CGSize(width: SettingsView.contentSize.width,
                                                    height: SettingsView.contentSize.height + 28), in: air13)
        #expect(air13.contains(frame))
        #expect(frame.width == SettingsView.contentSize.width)
        // The issue's frame: x = 734, width 841, 105 pt past the right edge.
        let offscreen = CGRect(x: 734, y: 200, width: 841, height: 608)
        let clamped = WindowPlacement.clamped(offscreen, to: air13)
        #expect(air13.contains(clamped))
        #expect(clamped.size == offscreen.size)
    }

    @Test func settingsShrinksOnAShortScreenButKeepsItsTitleBar() {
        let short = CGRect(x: 0, y: 0, width: 1024, height: 500)
        let minSize = CGSize(width: 841, height: SettingsView.minPaneHeight + 28)
        let clamped = WindowPlacement.clamped(CGRect(x: 400, y: -100, width: 841, height: 608), to: short,
                                              minSize: minSize)
        #expect(short.contains(clamped))
        #expect(clamped.height == 500)
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 300)
        let pinned = WindowPlacement.clamped(CGRect(x: 0, y: 0, width: 841, height: 608), to: tiny, minSize: minSize)
        #expect(pinned.maxY == tiny.maxY)
        #expect(pinned.minX == tiny.minX)
    }

    // MARK: - #116 Quick Access never stacks off-screen

    /// Medium panels of 16:10-ish fullscreen captures, as in the issue.
    private var fullscreenPanel: CGSize {
        QuickAccessLayout.panelSize(imageSize: CGSize(width: 2940, height: 1912), size: .medium)
    }

    @Test(arguments: [1, 5, 12])
    func stackStaysOnScreen(count: Int) {
        for corner in [ScreenCorner.bottomRight, .bottomLeft, .topRight, .topLeft] {
            let stack = QuickAccessLayout.stack(for: Array(repeating: fullscreenPanel, count: count), corner: corner,
                                                in: air13)
            #expect(stack.frames.count == min(count, QuickAccessLayout.maxVisible))
            #expect(stack.hiddenCount == count - stack.frames.count)
            #expect(stack.frames.allSatisfy { air13.contains($0) })
            if let badge = stack.badgeFrame {
                #expect(air13.contains(badge))
            } else {
                #expect(stack.hiddenCount == 0)
            }
        }
    }

    @Test func twelvePanelsShowFiveAndPlusSeven() throws {
        let stack = QuickAccessLayout.stack(for: Array(repeating: fullscreenPanel, count: 12), corner: .bottomRight,
                                            in: air13)
        #expect(stack.frames.count == 5)
        #expect(stack.hiddenCount == 7)
        let badge = try #require(stack.badgeFrame)
        // Beside the oldest shown panel, not on top of the newer ones.
        #expect(stack.frames.dropLast().allSatisfy { !$0.intersects(badge) })
    }

    @Test func panelsThatWouldLeaveTheScreenAreHiddenNotPlacedOffIt() {
        let large = QuickAccessLayout.panelSize(imageSize: CGSize(width: 800, height: 8000), size: .large)
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 700)
        let stack = QuickAccessLayout.stack(for: Array(repeating: large, count: 5), corner: .topLeft, in: narrow)
        #expect(stack.frames.count < 5)
        #expect(stack.frames.allSatisfy { narrow.contains($0) })
        #expect(stack.hiddenCount == 5 - stack.frames.count)
    }

    @Test func newestPanelLargerThanTheScreenIsClamped() {
        let tiny = CGRect(x: 100, y: 50, width: 200, height: 150)
        let stack = QuickAccessLayout.stack(for: [CGSize(width: 332, height: 442)], corner: .bottomRight, in: tiny)
        #expect(stack.frames.count == 1)
        #expect(stack.frames.allSatisfy { tiny.contains($0) })
    }
}
