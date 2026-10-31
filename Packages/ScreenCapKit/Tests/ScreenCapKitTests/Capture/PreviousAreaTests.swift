import CoreGraphics
@testable import ScreenCapKit
import Testing

@Suite("PreviousArea")
@MainActor
struct PreviousAreaTests {
    @Test func remembersLastRectInStore() {
        let store = InMemoryPreviousAreaStore()
        let area = PreviousArea(store: store)
        #expect(area.rect == nil)

        area.remember(CGRect(x: 10, y: 20, width: 300, height: 200))
        area.remember(CGRect(x: 50, y: 60, width: -100, height: 80)) // negative width is standardized
        #expect(area.rect == CGRect(x: -50, y: 60, width: 100, height: 80))
        #expect(store.lastRect == area.rect)

        // A store with a saved value (e.g. from Settings) is picked up.
        #expect(PreviousArea(store: store).rect == CGRect(x: -50, y: 60, width: 100, height: 80))

        area.clear()
        #expect(store.lastRect == nil)
    }

    @Test func ignoresDegenerateRects() {
        let area = PreviousArea()
        area.remember(CGRect(x: 0, y: 0, width: 100, height: 100))
        area.remember(CGRect(x: 5, y: 5, width: 0, height: 40))
        area.remember(.null)
        #expect(area.rect == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func dropsRectThatIsNoLongerOnAnyDisplay() {
        let main = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), backingScale: 2)
        let external = DisplayInfo(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), backingScale: 1)
        let area = PreviousArea()
        area.remember(CGRect(x: 2000, y: 100, width: 300, height: 200))

        #expect(area.rect(validIn: DisplayGeometry(displays: [main, external])) != nil)
        #expect(area.rect(validIn: DisplayGeometry(displays: [main])) == nil)
    }
}
