import Foundation
@testable import ScreenCapKit
import Testing

@Suite("FilenameTemplate")
struct FilenameTemplateTests {
    /// 2026-03-07 09:05:04 UTC.
    static let fixedDate = Date(timeIntervalSince1970: 1_772_874_304)
    static let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)

    func make(_ template: String, format: ImageFormat = .png) -> FilenameTemplate {
        FilenameTemplate(template, format: format, clock: { Self.fixedDate }, timeZone: .gmt)
    }

    @Test func defaultTemplate() {
        let name = make(AppSettings.Defaults.filenameTemplate).filename()
        #expect(name == "ScreenCap 2026-03-07 at 09.05.04.png")
    }

    @Test(arguments: [
        ("{date}", "2026-03-07"),
        ("{time}", "09.05.04"),
        ("{datetime}", "2026-03-07 09.05.04"),
        ("{app}", "Safari"),
        ("{window}", "Apple Developer"),
        ("{kind}", "window"),
        ("{counter}", "1")
    ])
    func everyToken(template: String, expected: String) {
        let context = FilenameTemplate.Context(app: "Safari", window: "Apple Developer", kind: .window)
        #expect(make(template).filename(context: context) == "\(expected).png")
    }

    @Test func everyKind() {
        for kind in FilenameTemplate.Kind.allCases {
            let name = make("{kind}").filename(context: .init(kind: kind))
            #expect(name == "\(kind.rawValue).png")
        }
    }

    @Test func timeZoneIsInjected() {
        let template = FilenameTemplate(
            "{datetime}", format: .png, clock: { Self.fixedDate },
            timeZone: TimeZone(secondsFromGMT: -5 * 3600) ?? .gmt
        )
        #expect(template.filename() == "2026-03-07 04.05.04.png")
    }

    @Test func extensionFollowsFormat() {
        #expect(make("a", format: .jpeg).filename() == "a.jpg")
        #expect(make("a", format: .heic).filename() == "a.heic")
        #expect(make("a", format: .tiff).filename() == "a.tiff")
    }

    @Test func missingContextCollapsesSpaces() {
        #expect(make("Shot {app} {window} {date}").filename() == "Shot 2026-03-07.png")
    }

    @Test func unknownTokensStayLiteral() {
        #expect(make("{nope} {date}").filename() == "{nope} 2026-03-07.png")
    }

    @Test func tokenLikeValuesAreNotExpandedTwice() {
        let name = make("{app}").filename(context: .init(app: "{date}"))
        #expect(name == "{date}.png")
    }

    @Test func stripsIllegalCharacters() {
        let context = FilenameTemplate.Context(app: "A/B:C", window: "x\\y*z?\"<>|\ttab\nline")
        #expect(make("{app} {window}").filename(context: context) == "ABC xyz tab line.png")
    }

    @Test func stripsLeadingDots() {
        #expect(make("..hidden {date}").filename() == "hidden 2026-03-07.png")
        #expect(make(". .x").filename() == "x.png")
    }

    @Test func emptyRenderFallsBack() {
        #expect(make("{app}").filename() == "ScreenCap.png")
        #expect(make("///").filename() == "ScreenCap.png")
    }

    @Test func truncatesTo200Characters() {
        let name = make(String(repeating: "a", count: 500)).filename()
        #expect(name == String(repeating: "a", count: 200) + ".png")
    }

    /// 200 CJK characters are 600 UTF-8 bytes, over APFS's 255-byte name limit (#58).
    @Test func truncatesCJKByBytes() {
        let name = make(String(repeating: "日", count: 200)).filename()
        let stem = String(name.dropLast(4))
        #expect(stem.utf8.count <= FilenameTemplate.maxLength)
        #expect(stem == String(repeating: "日", count: 66)) // 66 × 3 = 198 bytes; a 67th would be 201
        #expect(name.utf8.count <= 255)
    }

    /// A skin-toned emoji is one 8-byte grapheme of two scalars; truncation never splits it.
    @Test func truncationKeepsWholeGraphemes() {
        let thumb = "👍🏽"
        let name = make("a" + String(repeating: thumb, count: 40)).filename()
        let stem = String(name.dropLast(4))
        #expect(stem == "a" + String(repeating: thumb, count: 24)) // 1 + 24 × 8 = 193 bytes; 25 would be 201
        // A 25-byte family emoji (ZWJ sequence) is kept whole or dropped whole.
        let family = "👨‍👩‍👧‍👦"
        #expect(FilenameTemplate.prefix("a" + family, maxBytes: 25) == "a")
        #expect(FilenameTemplate.prefix("a" + family, maxBytes: 26) == "a" + family)
        #expect(FilenameTemplate.prefix("é👍x", maxBytes: 5) == "é")
        #expect(FilenameTemplate.prefix("short", maxBytes: 200) == "short")
    }

    @Test func collisionSuffixFitsByteLimit() {
        let template = make(String(repeating: "日", count: 200))
        let first = template.filename()
        let url = template.uniqueURL(in: Self.folder) { $0.lastPathComponent == first }
        let stem = url.deletingPathExtension().lastPathComponent
        #expect(stem.utf8.count <= FilenameTemplate.maxLength)
        #expect(stem.hasSuffix("日 2"))
    }

    @Test func truncationKeepsCollisionSuffixWithinLimit() {
        let template = make(String(repeating: "b", count: 300))
        let first = template.filename()
        let url = template.uniqueURL(in: Self.folder) { $0.lastPathComponent == first }
        let stem = url.deletingPathExtension().lastPathComponent
        #expect(stem.count == 200)
        #expect(stem.hasSuffix("b 2"))
    }

    @Test func uniqueURLReturnsBaseWhenFree() {
        let url = make("Shot {date}").uniqueURL(in: Self.folder) { _ in false }
        #expect(url == Self.folder.appendingPathComponent("Shot 2026-03-07.png"))
    }

    @Test func uniqueURLAppendsSuffixOnCollision() {
        let taken: Set<String> = ["Shot.png", "Shot 2.png", "Shot 3.png"]
        let url = make("Shot").uniqueURL(in: Self.folder) { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "Shot 4.png")
        #expect(url.deletingLastPathComponent().standardizedFileURL == Self.folder.standardizedFileURL)
    }

    @Test func counterTokenIncrementsInsteadOfSuffix() {
        let taken: Set<String> = ["Shot 1 area.png", "Shot 2 area.png"]
        let url = make("Shot {counter} {kind}")
            .uniqueURL(in: Self.folder, context: .init(kind: .area)) { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "Shot 3 area.png")
    }

    @Test func uniqueURLUsesRealFileSystemByDefault() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let template = make("Shot")
        try Data().write(to: folder.appendingPathComponent("Shot.png"))
        #expect(template.uniqueURL(in: folder).lastPathComponent == "Shot 2.png")
    }

    @Test func reserveClaimsDistinctNamesUnderConcurrency() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let template = make(AppSettings.Defaults.filenameTemplate)
        let urls = try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<8 {
                group.addTask { try template.reserveUniqueURL(in: folder) }
            }
            return try await group.reduce(into: [URL]()) { $0.append($1) }
        }
        #expect(Set(urls).count == 8)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.count == 8)
        #expect(names.contains("ScreenCap 2026-03-07 at 09.05.04.png"))
        #expect(names.contains("ScreenCap 2026-03-07 at 09.05.04 2.png"))
    }

    @Test func reserveSkipsExistingFiles() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("keep".utf8).write(to: folder.appendingPathComponent("Shot.png"))
        let url = try make("Shot").reserveUniqueURL(in: folder)
        #expect(url.lastPathComponent == "Shot 2.png")
        #expect(try Data(contentsOf: folder.appendingPathComponent("Shot.png")) == Data("keep".utf8))
    }
}
