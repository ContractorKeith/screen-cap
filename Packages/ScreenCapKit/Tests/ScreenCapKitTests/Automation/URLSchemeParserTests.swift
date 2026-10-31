import Foundation
@testable import ScreenCapKit
import Testing
import UniformTypeIdentifiers

/// In-memory filesystem: readable files and their content types.
struct StubFileChecker: FileChecker {
    var files: [String: UTType]

    func isReadableFile(at url: URL) -> Bool { files[url.path] != nil }
    func contentType(of url: URL) -> UTType? { files[url.path] }
}

let stubFiles = StubFileChecker(files: [
    "/tmp/shot.png": .png,
    "/tmp/My Shots/shot 1.jpg": .jpeg,
    "/tmp/notes.txt": .plainText
])
let schemeStubParser = URLSchemeParser(fileChecker: stubFiles)
let stubPNG = URL(fileURLWithPath: "/tmp/shot.png")

func parseScheme(_ string: String) throws -> AutomationCommand {
    try schemeStubParser.parse(try #require(URL(string: string)))
}

func expectParseError(
    _ string: String, _ expected: URLSchemeParseError, sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(throws: expected, sourceLocation: sourceLocation) { try parseScheme(string) }
}

@Suite("URL scheme: one parse per command")
struct URLSchemeCommandTests {
    let region = Region(x: 10, y: 20, width: 300, height: 200.5, display: 2)

    @Test func allInOne() throws {
        #expect(try parseScheme("screencap://all-in-one") == .allInOne(region: nil))
        #expect(try parseScheme("screencap://all-in-one?x=10&y=20&width=300&height=200.5&display=2")
            == .allInOne(region: region))
    }

    @Test func captureArea() throws {
        #expect(try parseScheme("screencap://capture-area") == .captureArea(region: nil, action: nil))
        #expect(try parseScheme("screencap://capture-area?x=10&y=20&width=300&height=200.5&display=2&action=pin")
            == .captureArea(region: region, action: .pin))
    }

    @Test func displayDefaultsToOne() throws {
        #expect(try parseScheme("screencap://capture-area?x=0&y=0&width=1&height=1")
            == .captureArea(region: Region(x: 0, y: 0, width: 1, height: 1, display: 1), action: nil))
    }

    @Test func actionCommands() throws {
        #expect(try parseScheme("screencap://capture-previous-area?action=copy") == .capturePreviousArea(action: .copy))
        #expect(try parseScheme("screencap://capture-fullscreen?action=save") == .captureFullscreen(action: .save))
        #expect(try parseScheme("screencap://capture-window?action=annotate") == .captureWindow(action: .annotate))
        #expect(try parseScheme("screencap://self-timer?action=overlay") == .selfTimer(action: .overlay))
        #expect(try parseScheme("screencap://self-timer") == .selfTimer(action: nil))
    }

    @Test func scrollingCapture() throws {
        #expect(try parseScheme("screencap://scrolling-capture")
            == .scrollingCapture(region: nil, start: false, autoscroll: false))
        #expect(try parseScheme("screencap://scrolling-capture?x=10&y=20&width=300&height=200.5&display=2&start=true&autoscroll=1")
            == .scrollingCapture(region: region, start: true, autoscroll: true))
    }

    @Test func captureText() throws {
        #expect(try parseScheme("screencap://capture-text") == .captureText(source: nil, lineBreaks: true))
        #expect(try parseScheme("screencap://capture-text?filepath=/tmp/shot.png&linebreaks=false")
            == .captureText(source: .file(stubPNG), lineBreaks: false))
        #expect(try parseScheme("screencap://capture-text?x=10&y=20&width=300&height=200.5&display=2")
            == .captureText(source: .region(region), lineBreaks: true))
    }

    @Test func fileCommands() throws {
        #expect(try parseScheme("screencap://open-annotate?filepath=/tmp/shot.png") == .openAnnotate(file: stubPNG))
        #expect(try parseScheme("screencap://open-annotate") == .openAnnotate(file: nil))
        #expect(try parseScheme("screencap://pin?filepath=/tmp/shot.png") == .pin(file: stubPNG))
        #expect(try parseScheme("screencap://pin") == .pin(file: nil))
        #expect(try parseScheme("screencap://add-quick-access-overlay?filepath=/tmp/shot.png")
            == .addQuickAccessOverlay(file: stubPNG))
    }

    @Test func percentEncodedFilepath() throws {
        let url = URL(fileURLWithPath: "/tmp/My Shots/shot 1.jpg")
        #expect(try parseScheme("screencap://pin?filepath=%2Ftmp%2FMy%20Shots%2Fshot%201.jpg") == .pin(file: url))
    }

    @Test func noParameterCommands() throws {
        #expect(try parseScheme("screencap://open-from-clipboard") == .openFromClipboard)
        #expect(try parseScheme("screencap://open-history") == .openHistory)
        #expect(try parseScheme("screencap://restore-recently-closed") == .restoreRecentlyClosed)
        #expect(try parseScheme("screencap://toggle-desktop-icons") == .toggleDesktopIcons)
        #expect(try parseScheme("screencap://hide-desktop-icons") == .hideDesktopIcons)
        #expect(try parseScheme("screencap://show-desktop-icons") == .showDesktopIcons)
        #expect(try parseScheme("screencap://open-history/") == .openHistory)
    }

    @Test func openSettings() throws {
        #expect(try parseScheme("screencap://open-settings") == .openSettings(tab: nil))
        #expect(try parseScheme("screencap://open-settings?tab=quickaccess") == .openSettings(tab: .quickAccess))
        #expect(try parseScheme("screencap://open-settings?tab=shortcuts") == .openSettings(tab: .shortcuts))
    }

    @Test func staticParseUsesRealFilesystem() throws {
        let url = try #require(URL(string: "screencap://open-history"))
        #expect(try URLSchemeParser.parse(url) == .openHistory)
    }
}

@Suite("URL scheme: errors")
struct URLSchemeErrorTests {
    @Test func wrongScheme() {
        expectParseError("https://capture-area", .wrongScheme("https"))
    }

    @Test func unknownCommand() {
        expectParseError("screencap://capture-everything", .unknownCommand("capture-everything"))
        expectParseError("screencap://capture-area/extra", .unknownCommand("capture-area/extra"))
        expectParseError("screencap:", .unknownCommand(""))
    }

    @Test func missingParameter() {
        expectParseError("screencap://add-quick-access-overlay", .missingParameter("filepath"))
    }

    @Test func partialRegionIsAnError() {
        expectParseError("screencap://capture-area?x=1&y=2&width=3", .missingParameter("height"))
        expectParseError("screencap://capture-area?width=3&height=4", .missingParameter("x"))
        expectParseError("screencap://capture-area?display=2", .missingParameter("x"))
    }

    @Test func invalidParameter() {
        expectParseError("screencap://capture-area?action=print", .invalidParameter(name: "action", value: "print"))
        expectParseError("screencap://capture-area?x=a&y=0&width=1&height=1", .invalidParameter(name: "x", value: "a"))
        expectParseError("screencap://capture-area?x=-1&y=0&width=1&height=1", .invalidParameter(name: "x", value: "-1"))
        expectParseError("screencap://capture-area?x=0&y=0&width=0&height=1", .invalidParameter(name: "width", value: "0"))
        expectParseError("screencap://all-in-one?x=0&y=0&width=1&height=1&display=0",
                    .invalidParameter(name: "display", value: "0"))
        expectParseError("screencap://scrolling-capture?start=yes", .invalidParameter(name: "start", value: "yes"))
        expectParseError("screencap://open-settings?tab=nope", .invalidParameter(name: "tab", value: "nope"))
        expectParseError("screencap://capture-fullscreen?action=", .invalidParameter(name: "action", value: ""))
        expectParseError("screencap://capture-fullscreen?action=copy&action=save",
                    .invalidParameter(name: "action", value: "save"))
        expectParseError("screencap://pin?filepath=relative/shot.png",
                    .invalidParameter(name: "filepath", value: "relative/shot.png"))
        expectParseError("screencap://capture-text?filepath=/tmp/shot.png&x=0&y=0&width=1&height=1",
                    .invalidParameter(name: "filepath", value: "/tmp/shot.png"))
    }

    @Test func unreadableFile() {
        expectParseError("screencap://pin?filepath=/tmp/missing.png", .unreadableFile(path: "/tmp/missing.png"))
    }

    @Test func notAnImage() {
        expectParseError("screencap://open-annotate?filepath=/tmp/notes.txt", .notAnImage(path: "/tmp/notes.txt"))
    }

    @Test func unknownParameter() {
        expectParseError("screencap://capture-fullscreen?acton=copy", .unknownParameter("acton"))
        expectParseError("screencap://open-history?x=1", .unknownParameter("x"))
    }

    @Test func errorsHaveMessages() {
        #expect(URLSchemeParseError.unknownParameter("acton").localizedDescription.contains("acton"))
    }
}

@Suite("URL scheme: case sensitivity")
struct URLSchemeCaseTests {
    // Decision: scheme, command names and parameter keys are case-insensitive; values are not.
    @Test func namesAndKeysIgnoreCase() throws {
        #expect(try parseScheme("SCREENCAP://Capture-Area?ACTION=copy") == .captureArea(region: nil, action: .copy))
        #expect(try parseScheme("screencap://OPEN-SETTINGS?Tab=general") == .openSettings(tab: .general))
    }

    @Test func valuesAreCaseSensitive() {
        expectParseError("screencap://capture-area?action=Copy", .invalidParameter(name: "action", value: "Copy"))
        expectParseError("screencap://scrolling-capture?start=TRUE", .invalidParameter(name: "start", value: "TRUE"))
        expectParseError("screencap://open-settings?tab=General", .invalidParameter(name: "tab", value: "General"))
    }

    @Test func keysCollideAcrossCase() {
        expectParseError("screencap://self-timer?action=copy&Action=pin", .invalidParameter(name: "action", value: "pin"))
    }
}

@Suite("Disk file checker")
struct DiskFileCheckerTests {
    @Test func readsRealFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = dir.appendingPathComponent("a.png")
        let text = dir.appendingPathComponent("a.txt")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
        try Data("hi".utf8).write(to: text)

        let checker = DiskFileChecker()
        #expect(checker.isReadableFile(at: image))
        #expect(!checker.isReadableFile(at: dir))
        #expect(!checker.isReadableFile(at: dir.appendingPathComponent("missing.png")))
        #expect(checker.contentType(of: image)?.conforms(to: .image) == true)
        #expect(checker.contentType(of: text)?.conforms(to: .image) == false)

        let parser = URLSchemeParser()
        #expect(try parser.parse(URLSchemeBuilder.url(for: .pin(file: image))) == .pin(file: image.standardizedFileURL))
        #expect(throws: URLSchemeParseError.self) {
            try parser.parse(URLSchemeBuilder.url(for: .pin(file: text)))
        }
    }
}
