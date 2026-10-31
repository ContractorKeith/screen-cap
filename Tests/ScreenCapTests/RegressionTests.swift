import AppKit
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

// Integration-level regression tests for the #38–#63 fixes and #78 (issue #80).
// #53/#72 (Capture Text from the coordinator writes History) is covered by the capture worker's
// coordinator-driven test in CaptureCoordinatorTests.swift (fix/r2-capture), not duplicated here.

/// The repo root, for tests that read shipped sources.
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

// MARK: - #57 Reset All Settings covers every key

@Suite("Regression: #57 settings reset")
@MainActor
struct SettingsResetRegressionTests {
    /// UserDefaults keys that are deliberately not settings (see SettingsKeys' doc comment).
    static let notSettings: Set<String> = ["welcome.dontShowAgain"]

    /// Every UserDefaults key literal declared in App/: `static let …Key = "…"` and string-backed
    /// key enums (`case x = "scrolling.x"`), plus the editor's `editor.<name>` keys.
    static func appDefaultsKeys() throws -> Set<String> {
        let patterns = [
            #"static let \w*[Kk]ey = "([^"]+)""#,
            #"case \w+ = "((?:scrolling|editor)\.[^"]+)""#
        ].map { try? NSRegularExpression(pattern: $0) }.compactMap { $0 }
        var keys = Set<String>()
        let files = FileManager.default.enumerator(at: repoRoot.appendingPathComponent("App"),
                                                   includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for regex in patterns {
                for match in regex.matches(in: source, range: range) {
                    if let key = Range(match.range(at: 1), in: source) { keys.insert(String(source[key])) }
                }
            }
        }
        // Not a UserDefaults key: the Info.plist placeholder for Sparkle's public key.
        keys.remove(UpdaterConfiguration.placeholderKey)
        return keys
    }

    @Test func everyAppDefaultsKeyIsInTheResetRegistry() throws {
        let keys = try Self.appDefaultsKeys()
        #expect(keys.contains("EditorRedactionBakeConfirmed"))
        #expect(keys.contains("scrolling.autoScroll"))
        let missing = keys.subtracting(SettingsKeys.all).subtracting(Self.notSettings)
        #expect(missing.isEmpty, "Reset All Settings misses: \(missing.sorted())")
    }

    @Test func resetRemovesEveryRegistryKey() {
        let name = "screencap.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)! // swiftlint:disable:this force_unwrapping
        defer { UserDefaults().removePersistentDomain(forName: name) }
        for key in SettingsKeys.all { defaults.set(true, forKey: key) }
        defaults.set(true, forKey: "welcome.dontShowAgain")

        SettingsReset.resetAll(settings: AppSettings(store: UserDefaultsSettingsStore(suiteName: name)),
                               scrolling: ScrollingSettings(defaults: defaults),
                               editor: EditorPreferences(store: UserDefaultsSettingsStore(suiteName: name)),
                               defaults: defaults)

        let stored = defaults.persistentDomain(forName: name) ?? [:]
        let left = SettingsKeys.all.filter { stored[$0] != nil }
        #expect(left.isEmpty, "Still stored after reset: \(left)")
        #expect(stored["welcome.dontShowAgain"] as? Bool == true)
    }
}

// MARK: - #41 History Restore reaches Quick Access

@Suite("Regression: #41 restore to Quick Access", .serialized)
@MainActor
struct RestoreToQuickAccessRegressionTests {
    @Test func historyRestoreShowsThePanelAndClearsClosed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory, retentionDays: nil)
        let image = try #require(HistoryViewModelTests.image())
        let record = try await store.add(image: image, kind: .window, metadata: CaptureMetadata(appName: "Notes"))
        try await store.markClosed(id: record.id)

        let settings = AppSettings(store: InMemorySettingsStore())
        let quickAccess = QuickAccessController(settings: settings, output: CaptureOutput(settings: settings),
                                                history: store, router: nil)
        let model = HistoryViewModel(store: store, retentionDays: { 30 })
        await model.reload()

        // The History window's Restore button, through the real notification.
        HistoryActions(settings: settings, model: model).restore([record.id])

        let shown = await poll { quickAccess.items.contains { $0.result.historyRecordID == record.id } }
        #expect(shown, "Restore didn't put the record in Quick Access")
        let cleared = await poll { await store.recentlyClosed().isEmpty }
        #expect(cleared, "Restored record is still in Restore Recently Closed")
        for item in quickAccess.items { quickAccess.remove(item, markClosed: false) }
    }
}

/// Waits up to ~2 s for `condition`.
@MainActor
private func poll(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<100 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

// MARK: - #48 same-second saves

@Suite("Regression: #48 same-second saves")
@MainActor
struct SameSecondSaveRegressionTests {
    @Test func backToBackSavesNeverOverwrite() async throws {
        let folder = try CaptureFlowFixTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Second-resolution name: these all land in the same second or two.
        let output = CaptureFlowFixTests.output(folder: folder, scale: .retina)
        let result = try CaptureFlowFixTests.retinaResult()
        var urls: [URL] = []
        for _ in 0..<3 { urls.append(try await output.save(result)) }
        async let fourth = output.save(result)
        async let fifth = output.save(result)
        urls += try await [fourth, fifth]
        #expect(Set(urls).count == 5)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 5)
    }
}

// MARK: - #78 error handling

@Suite("Regression: #78 pin, history, Quick Access, HUD")
@MainActor
struct ErrorHandlingRegressionTests {
    struct Failure: LocalizedError {
        var errorDescription: String? { "disk full" }
    }

    @Test func pinCopySaysCopiedOnlyOnSuccess() {
        #expect(PinController.copyMessage(error: nil) == "Copied")
        let message = PinController.copyMessage(error: Failure())
        #expect(message != "Copied")
        #expect(message.contains("disk full"))
    }

    private func folder() throws -> URL {
        try CaptureFlowFixTests.temporaryFolder()
    }

    @Test func saveAsReplacesTheTargetOnlyAfterTheCopy() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("record.png")
        let target = folder.appendingPathComponent("chosen.png")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: target)

        try HistoryActions.export(source, to: target)
        #expect(try Data(contentsOf: target) == Data("new".utf8))
        #expect(FileManager.default.fileExists(atPath: source.path), "Save As must copy, not move")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["chosen.png", "record.png"])
    }

    @Test func saveAsOfAPurgedRecordKeepsTheTarget() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = folder.appendingPathComponent("purged.png")
        let target = folder.appendingPathComponent("chosen.png")
        try Data("keep me".utf8).write(to: target)

        #expect(throws: (any Error).self) { try HistoryActions.export(missing, to: target) }
        #expect(try Data(contentsOf: target) == Data("keep me".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["chosen.png"])
    }

    @Test func saveAsToANewName() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("record.png")
        try Data("img".utf8).write(to: source)
        let target = folder.appendingPathComponent("new.png")
        try HistoryActions.export(source, to: target)
        #expect(try Data(contentsOf: target) == Data("img".utf8))
    }

    @Test func concurrentQuickAccessSavesWriteOnce() async {
        let gate = QuickAccessSaveGate<QuickAccessSaveKey>()
        let key = QuickAccessSaveKey.record(UUID())
        var runs = 0
        let url = URL(fileURLWithPath: "/tmp/X.png")
        let save: @MainActor () async -> URL? = {
            runs += 1
            try? await Task.sleep(for: .milliseconds(50))
            return url
        }
        async let first = gate.save(key, save)
        async let second = gate.save(key, save) // double-click
        async let swipe = gate.save(key, save) // save swipe
        let results = await [first, second, swipe]
        #expect(runs == 1)
        #expect(results == [url, url, url])
        #expect(!gate.isSaving(key))
    }

    @Test func deleteDuringSaveSeesTheSavedFile() async {
        let gate = QuickAccessSaveGate<QuickAccessSaveKey>()
        let key = QuickAccessSaveKey.record(UUID())
        #expect(await gate.pending(key) == nil)
        let url = URL(fileURLWithPath: "/tmp/Y.png")
        async let saved = gate.save(key) {
            try? await Task.sleep(for: .milliseconds(50))
            return url
        }
        try? await Task.sleep(for: .milliseconds(10))
        #expect(gate.isSaving(key))
        #expect(await gate.pending(key) == url)
        _ = await saved
    }

    @Test func differentCapturesSaveIndependently() async {
        let gate = QuickAccessSaveGate<QuickAccessSaveKey>()
        var runs = 0
        let save: @MainActor () async -> URL? = { runs += 1; return nil }
        _ = await gate.save(.record(UUID()), save)
        _ = await gate.save(.record(UUID()), save)
        #expect(runs == 2)
    }

    @Test func failedSaveCanBeRetried() async {
        let gate = QuickAccessSaveGate<QuickAccessSaveKey>()
        let key = QuickAccessSaveKey.record(UUID())
        var runs = 0
        #expect(await gate.save(key) { runs += 1; return nil } == nil)
        #expect(await gate.save(key) { runs += 1; return nil } == nil)
        #expect(runs == 2)
    }

    @Test func hudWithAnActionIsNeverReplaced() {
        // A plain message replaces plain ones.
        #expect(CaptureHUDStack.kept(hasButtons: [false]).isEmpty)
        // Fullscreen on two displays, both saves failing: the first recovery HUD stays.
        #expect(CaptureHUDStack.kept(hasButtons: [true]) == [0])
        #expect(CaptureHUDStack.kept(hasButtons: [true, false, true]) == [0, 2])
        // Bounded: the oldest goes past the cap.
        let many = Array(repeating: true, count: CaptureHUDStack.maxVisible + 2)
        #expect(CaptureHUDStack.kept(hasButtons: many).count == CaptureHUDStack.maxVisible - 1)
        #expect(CaptureHUDStack.kept(hasButtons: many).last == many.count - 1)
    }
}

// MARK: - #77 build number

@Suite("Regression: #77 build number")
struct BuildNumberRegressionTests {
    @Test func bundleScriptStampsTheBuildNumber() throws {
        let script = try String(contentsOf: repoRoot.appendingPathComponent("scripts/bundle.sh"), encoding: .utf8)
        #expect(script.contains("git rev-list --count HEAD"))
        #expect(script.contains("Set :CFBundleVersion"))
        #expect(script.contains("scripts/check-bundle.sh"))
    }

    /// When a bundle has been built (`make bundle`, CI), its build number must not be the source "1".
    @Test func builtBundleHasARealBuildNumber() throws {
        let plist = repoRoot.appendingPathComponent("build/ScreenCap.app/Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else { return }
        let build = try #require(Int(info["CFBundleVersion"] as? String ?? ""))
        #expect(build > 1)
        #expect(info["CFBundleShortVersionString"] as? String == ScreenCapKit.version)
    }
}
