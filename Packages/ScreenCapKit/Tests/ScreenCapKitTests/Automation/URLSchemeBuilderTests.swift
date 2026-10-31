import Foundation
@testable import ScreenCapKit
import Testing

@Suite("URL scheme: builder round-trips")
struct URLSchemeBuilderTests {
    static let region = Region(x: 10, y: 20.25, width: 300, height: 200, display: 2)
    static let spaced = URL(fileURLWithPath: "/tmp/My Shots/shot 1.jpg")

    /// At least one value per command, covering optional parameters both given and omitted.
    static let commands: [AutomationCommand] = [
        .allInOne(region: nil),
        .allInOne(region: region),
        .captureArea(region: nil, action: nil),
        .captureArea(region: region, action: .annotate),
        .capturePreviousArea(action: .copy),
        .captureFullscreen(action: .save),
        .captureWindow(action: nil),
        .selfTimer(action: .overlay),
        .scrollingCapture(region: region, start: true, autoscroll: false),
        .scrollingCapture(region: nil, start: false, autoscroll: true),
        .captureText(source: nil, lineBreaks: true),
        .captureText(source: .file(stubPNG), lineBreaks: false),
        .captureText(source: .region(region), lineBreaks: true),
        .openAnnotate(file: spaced),
        .openAnnotate(file: nil),
        .pin(file: stubPNG),
        .pin(file: nil),
        .openFromClipboard,
        .openHistory,
        .restoreRecentlyClosed,
        .addQuickAccessOverlay(file: spaced),
        .toggleDesktopIcons,
        .hideDesktopIcons,
        .showDesktopIcons,
        .openSettings(tab: nil),
        .openSettings(tab: .quickAccess),
        .openSettings(tab: .scrolling),
        .pin(file: reserved),
        .captureText(source: .file(reserved), lineBreaks: false),
        .addQuickAccessOverlay(file: reserved)
    ]

    /// Query delimiters and escapes in a path (#61).
    static let reserved = URL(fileURLWithPath: "/Users/me/a&b=c+d#e%f.png")

    @Test(arguments: commands)
    func roundTrips(_ command: AutomationCommand) throws {
        let url = URLSchemeBuilder.url(for: command)
        #expect(url.scheme == "screencap")
        #expect(try schemeStubParser.parse(url) == command)
    }

    @Test func canonicalOutput() {
        #expect(URLSchemeBuilder.url(for: .captureArea(region: Self.region, action: .pin)).absoluteString
            == "screencap://capture-area?x=10&y=20.25&width=300&height=200&display=2&action=pin")
        #expect(URLSchemeBuilder.url(for: .openHistory).absoluteString == "screencap://open-history")
    }

    @Test func encodesQueryDelimitersInValues() throws {
        let url = URLSchemeBuilder.url(for: .pin(file: Self.reserved))
        #expect(url.absoluteString == "screencap://pin?filepath=/Users/me/a%26b%3Dc%2Bd%23e%25f.png")
        #expect(try schemeStubParser.parse(url) == .pin(file: Self.reserved))
    }
}

extension AutomationCommand: CustomTestStringConvertible {
    public var testDescription: String { URLSchemeBuilder.url(for: self).absoluteString }
}
