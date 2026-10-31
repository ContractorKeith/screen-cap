import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

/// Drives the real coordinator flows with a fake screen source (#72, #75, #79).
@Suite("Capture coordinator flows")
@MainActor
struct CaptureCoordinatorTests {
    /// Hands back a solid image for any grab, after an optional delay, and logs the area rects.
    actor FakeSource: CaptureSource {
        let delay: Duration
        private(set) var areas: [CGRect] = []

        init(delay: Duration = .zero) {
            self.delay = delay
        }

        private func image(_ rect: CGRect) throws -> CapturedImage {
            let cgImage = try #require(CaptureLogicTests.solidImage(width: 8, height: 8))
            return CapturedImage(cgImage: cgImage, scale: 1, pointRect: rect, displayID: 1)
        }

        func captureArea(pointRect: CGRect) async throws -> CapturedImage {
            areas.append(pointRect)
            if delay > .zero { try await Task.sleep(for: delay) }
            return try image(pointRect)
        }

        func captureDisplay(_ id: CGDirectDisplayID) async throws -> CapturedImage { try image(.zero) }
        func captureAllDisplays() async throws -> [CapturedImage] { [try image(.zero)] }
        func captureWindow(id: CGWindowID, includeShadow: Bool) async throws -> CapturedImage { try image(.zero) }
        func shareableWindows() async throws -> [ShareableWindow] { [] }
    }

    /// Records what reaches the sink instead of showing UI.
    final class RecordingSink: CaptureSink {
        var delivered: [(rect: CGRect, action: AfterCaptureAction)] = []

        func deliver(_ result: CaptureResult, action: AfterCaptureAction) async {
            delivered.append((result.image.pointRect, action))
        }
    }

    final class AlertLog {
        var busy = 0
        var outputFailed: [AfterCaptureAction] = []
    }

    struct Harness {
        let coordinator: CaptureCoordinator
        let sink: RecordingSink
        let alerts: AlertLog
        let source: FakeSource
    }

    private func harness(source: FakeSource = FakeSource(), history: HistoryStore? = nil,
                         saveFolder: URL? = nil) -> Harness {
        let settings = AppSettings(store: InMemorySettingsStore())
        if let saveFolder { settings.saveFolder = saveFolder }
        settings.imageFormat = .png
        let coordinator = CaptureCoordinator(settings: settings, source: source, history: history,
                                             hasPermission: { true }, showOnboarding: {})
        let sink = RecordingSink()
        coordinator.sink = sink
        let log = AlertLog()
        coordinator.alerts = CaptureAlerts(busy: { log.busy += 1 },
                                           outputFailed: { action, _, _, _ in log.outputFailed.append(action) })
        return Harness(coordinator: coordinator, sink: sink, alerts: log, source: source)
    }

    private func makeStore() throws -> (HistoryStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)")
        return (try HistoryStore(directory: directory, retentionDays: nil), directory)
    }

    private let rect = CGRect(x: 10, y: 20, width: 30, height: 40)

    // MARK: - #72 Capture Text writes History

    @Test func captureTextWritesATextRecordWithItsOCRText() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let setup = harness(history: store)
        var recognized: [CGImage] = []
        setup.coordinator.textHandler = { image in
            recognized.append(image)
            return "Hello Zebra"
        }

        await setup.coordinator.capture(.text, rect: rect)?.value

        #expect(recognized.count == 1)
        let records = await store.records()
        #expect(records.map(\.kind) == [.text])
        #expect(records.first?.ocrText == "Hello Zebra")
        #expect(await store.records(query: "zebra").count == 1)
        #expect(setup.coordinator.lastOutcome == .delivered)
    }

    @Test func captureTextWithNoTextStillRecordsTheGrab() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let setup = harness(history: store)
        setup.coordinator.textHandler = { _ in nil }

        await setup.coordinator.capture(.text, rect: rect)?.value

        let records = await store.records()
        #expect(records.map(\.kind) == [.text])
        #expect(records.first?.ocrText == nil)
    }

    @Test func failedRecognitionFailsTheCapture() async throws {
        struct OCRFailed: Error {}
        let setup = harness()
        setup.coordinator.textHandler = { _ in throw OCRFailed() }
        await setup.coordinator.capture(.text, rect: rect)?.value
        #expect(setup.coordinator.lastOutcome?.exitStatus == 1)
    }

    // MARK: - #75 Quick Access off

    @Test func quickAccessOffSaveFailureShowsHUDAndFails() async throws {
        let parent = try CaptureFlowFixTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        // A file where a folder is needed, so creating the save folder fails.
        let blocker = parent.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let setup = harness(saveFolder: blocker.appendingPathComponent("Screenshots"))
        setup.coordinator.showsQuickAccess = { false }

        await setup.coordinator.capture(.area, rect: rect, action: .overlay)?.value

        #expect(setup.alerts.outputFailed == [.save])
        #expect(setup.sink.delivered.isEmpty)
        // `--quit` exits with this status.
        #expect(setup.coordinator.lastOutcome?.exitStatus == 1)
    }

    @Test func quickAccessOffSavesTheFile() async throws {
        let folder = try CaptureFlowFixTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let setup = harness(saveFolder: folder)
        setup.coordinator.showsQuickAccess = { false }

        await setup.coordinator.capture(.area, rect: rect, action: .overlay)?.value

        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
        #expect(setup.sink.delivered.isEmpty)
        #expect(setup.alerts.outputFailed.isEmpty)
        #expect(setup.coordinator.lastOutcome == .delivered)
    }

    @Test func quickAccessOnHandsTheCaptureToTheOverlay() async throws {
        let setup = harness()
        setup.coordinator.showsQuickAccess = { true }
        await setup.coordinator.capture(.area, rect: rect, action: .overlay)?.value
        #expect(setup.sink.delivered.map(\.action) == [.overlay])
        #expect(setup.coordinator.lastOutcome == .delivered)
    }

    // MARK: - #79 URL captures queue

    private func waitUntilIdle(_ coordinator: CaptureCoordinator) async throws {
        for _ in 0..<200 where !coordinator.isIdle {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.isIdle)
    }

    private func region(_ index: Int) -> CGRect {
        CGRect(x: index * 50, y: 100, width: 100, height: 100)
    }

    @Test func queuedCapturesRunInArrivalOrder() async throws {
        let setup = harness(source: FakeSource(delay: .milliseconds(30)))
        for index in 1...4 {
            setup.coordinator.capture(.area, rect: region(index), action: .pin, queueIfBusy: true)
        }
        #expect(setup.coordinator.queuedCount == 3)

        try await waitUntilIdle(setup.coordinator)

        #expect(setup.sink.delivered.map(\.rect) == (1...4).map(region))
        #expect(await setup.source.areas == (1...4).map(region))
        #expect(setup.alerts.busy == 0)
    }

    @Test func queueIsBoundedAndOverflowShowsBusy() async throws {
        let setup = harness(source: FakeSource(delay: .milliseconds(30)))
        let total = CaptureCoordinator.queueLimit + 3
        for index in 1...total {
            setup.coordinator.capture(.area, rect: region(index), action: .pin, queueIfBusy: true)
        }
        #expect(setup.coordinator.queuedCount == CaptureCoordinator.queueLimit)
        #expect(setup.alerts.busy == 2)

        try await waitUntilIdle(setup.coordinator)

        #expect(setup.sink.delivered.map(\.rect) == (1...(CaptureCoordinator.queueLimit + 1)).map(region))
    }

    @Test func shortcutsStillRefuseWhileBusy() async throws {
        let setup = harness(source: FakeSource(delay: .milliseconds(30)))
        let first = setup.coordinator.capture(.area, rect: region(1), action: .pin)
        #expect(setup.coordinator.capture(.area, rect: region(2), action: .pin) == nil)
        #expect(setup.coordinator.queuedCount == 0)
        #expect(setup.alerts.busy == 1)
        await first?.value
        #expect(setup.sink.delivered.count == 1)
    }

    // MARK: - #79 front app

    @Test func frontAppSkipsScreenCapItself() {
        let own: pid_t = 42
        let notes = FrontApp(name: "Notes", processID: 7)
        let screenCap = FrontApp(name: "ScreenCap", processID: own)
        #expect(FrontAppTracker.resolve(frontmost: screenCap, previous: notes, ownPID: own) == notes)
        #expect(FrontAppTracker.resolve(frontmost: notes, previous: nil, ownPID: own) == notes)
        #expect(FrontAppTracker.resolve(frontmost: screenCap, previous: nil, ownPID: own) == nil)
        #expect(FrontAppTracker.resolve(frontmost: nil, previous: notes, ownPID: own) == notes)
    }

    @Test func contextUsesTheAppTakenAtRequestTime() {
        let setup = harness()
        let context = setup.coordinator.frontContext(windows: [], app: FrontApp(name: "Safari", processID: 9))
        #expect(context.app == "Safari")
        #expect(setup.coordinator.frontContext(windows: [], app: nil).app == nil)
    }
}
