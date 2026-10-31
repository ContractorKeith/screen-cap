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
}
