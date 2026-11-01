import CoreGraphics
import Foundation
@testable import ScreenCap
import ScreenCapKit
import Testing

@Suite("Background presets")
@MainActor
struct BackgroundPresetTests {
    private func model() -> EditorDocumentModel {
        EditorDocumentModel(snapshot: EditorSnapshot(image: EditorModelTests.image(), scale: 1))
    }

    @Test func customImageTransfersAfterPreferencesReloadAndProjectReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let images = BackgroundPresetImages(directory: directory.appendingPathComponent("presets"))
        let store = InMemorySettingsStore()
        let preferences = EditorPreferences(store: store, presetImages: images)
        let source = model()
        source.setCustomBackground(EditorModelTests.image(width: 13, height: 9))
        source.updateBackground { $0.padding = 17; $0.cornerRadius = 6 }
        source.setBackground(source.document.background, aspect: 1)
        try preferences.saveBackgroundPreset(name: "Photo", snapshot: source.snapshot)
        let metadata = try #require(store.data(forKey: "editor.backgroundPresets"))
        #expect(metadata.count < 2_048)
        let reloaded = EditorPreferences(store: store, presetImages: images)
        let preset = try #require(reloaded.backgroundPresets.first)
        #expect(FileManager.default.fileExists(atPath: images.url(for: preset.id).path))
        let target = model()
        // An existing target layer with the source name must never be reused or overwritten.
        let sourceName = try #require(source.snapshot.layers.keys.first)
        target.perform { $0.layers[sourceName] = EditorModelTests.image(width: 3, height: 2) }
        try target.applyPreset(preset, preferences: reloaded)
        guard case let .customImage(name) = target.document.background?.fill else {
            Issue.record("Missing custom background")
            return
        }
        #expect(name != sourceName)
        #expect(target.snapshot.layers[sourceName]?.width == 3)
        #expect(target.snapshot.layers[name]?.width == 13)
        #expect(target.snapshot.layers[name]?.height == 9)
        #expect(target.document.background?.padding == 17)
        #expect(target.snapshot.backgroundAspect == 1)
        target.undo()
        #expect(target.document.background == nil)
        #expect(target.snapshot.layers[name] == nil)
        target.redo()
        // The target owns its image, even after the preset is deleted.
        reloaded.backgroundPresets.removeAll()
        let project = directory.appendingPathComponent("B.screencap")
        try target.saveProject(to: project)
        let reopened = try EditorDocumentModel.open(project)
        #expect(reopened.document.background == target.document.background)
        #expect(reopened.snapshot.layers[name]?.width == 13)
        #expect(reopened.snapshot.layers[name]?.height == 9)
        #expect(try reopened.exportData(format: .png).isEmpty == false)
    }

    @Test func legacyMissingImageReportsSentenceAndLeavesDocumentSavable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InMemorySettingsStore()
        // Exact pre-fix JSON schema, including an ordinary preset that must also survive decoding.
        let json = """
        [{"id":"117C3809-F7B1-4546-B9E6-50670D72F349","name":"Old photo",
          "background":{"fill":{"customImage":{"layerName":"preset-photo"}},
          "padding":64,"cornerRadius":12,"alignment":"center"}},
         {"id":"C5A7F61F-4FDB-4B7C-8CBF-144DE5C02CB2","name":"Solid",
          "background":{"fill":{"solid":{"color":{"red":1,"green":1,"blue":1,"alpha":1}}},
          "padding":64,"cornerRadius":12,"alignment":"center"}}]
        """
        store.set(Data(json.utf8), forKey: "editor.backgroundPresets")
        let preferences = EditorPreferences(store: store, presetImages: BackgroundPresetImages(directory: directory))
        #expect(preferences.backgroundPresets.count == 2)
        let preset = try #require(preferences.backgroundPresets.first)
        let target = model()
        let before = target.document
        do {
            try target.applyPreset(preset, preferences: preferences)
            Issue.record("Missing preset image should be rejected")
        } catch {
            #expect(error.localizedDescription ==
                "This preset’s image is unavailable; choose the image again and save a new preset.")
        }
        #expect(target.document == before)
        #expect(!target.canUndo)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try target.saveProject(to: directory.appendingPathComponent("legacy.screencap"))
        try target.applyPreset(preferences.backgroundPresets[1], preferences: preferences)
        #expect(target.document.background == preferences.backgroundPresets[1].background)
    }

    @Test func deletingPresetRemovesOnlyItsImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let images = BackgroundPresetImages(directory: directory)
        let preferences = EditorPreferences(store: InMemorySettingsStore(), presetImages: images)
        let source = model()
        source.setCustomBackground(EditorModelTests.image())
        try preferences.saveBackgroundPreset(name: "One", snapshot: source.snapshot)
        try preferences.saveBackgroundPreset(name: "Two", snapshot: source.snapshot)
        let first = preferences.backgroundPresets[0], second = preferences.backgroundPresets[1]
        preferences.backgroundPresets.removeAll { $0.id == first.id }
        #expect(!FileManager.default.fileExists(atPath: images.url(for: first.id).path))
        #expect(FileManager.default.fileExists(atPath: images.url(for: second.id).path))
    }

    @Test func failedImageSaveDoesNotPublishPreset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A file in place of the presets directory forces an actual filesystem write failure.
        try Data().write(to: directory)
        let store = InMemorySettingsStore()
        let preferences = EditorPreferences(store: store, presetImages: BackgroundPresetImages(directory: directory))
        let source = model()
        source.setCustomBackground(EditorModelTests.image())
        #expect(throws: (any Error).self) {
            try preferences.saveBackgroundPreset(name: "Photo", snapshot: source.snapshot)
        }
        #expect(preferences.backgroundPresets.isEmpty)
        #expect(EditorPreferences(store: store, presetImages: preferences.presetImages).backgroundPresets.isEmpty)
    }

    @Test func corruptAndOversizedFilesAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let images = BackgroundPresetImages(directory: directory)
        let id = UUID()
        try Data("not PNG".utf8).write(to: images.url(for: id))
        #expect(throws: PresetImageError.self) { try images.load(for: id) }
        try Data(repeating: 0, count: BackgroundPresetImages.maxBytes + 1).write(to: images.url(for: id))
        #expect(throws: PresetImageError.self) { try images.load(for: id) }
    }
}
