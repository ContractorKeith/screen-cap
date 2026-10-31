@testable import ScreenCap
import Testing

@Suite("CountdownState")
struct CountdownStateTests {
    @Test func countsDownToZeroAndStops() {
        var state = CountdownState(seconds: 3)
        #expect(state.remaining == 3)
        #expect(!state.isFinished)
        #expect(state.progress == 0)
        state.tick()
        state.tick()
        #expect(state.remaining == 1)
        state.tick()
        #expect(state.isFinished)
        #expect(state.progress == 1)
        state.tick()
        #expect(state.remaining == 0)
    }

    @Test(arguments: [0, -4])
    func clampsToOneSecond(seconds: Int) {
        let state = CountdownState(seconds: seconds)
        #expect(state.total == 1)
        #expect(state.remaining == 1)
    }
}
