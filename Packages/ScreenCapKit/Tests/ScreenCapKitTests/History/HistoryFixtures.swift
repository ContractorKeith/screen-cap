import CoreGraphics
import Foundation
@testable import ScreenCapKit

/// Shared helpers for the History tests.
enum HistoryFixtures {
    static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenCapHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// A settable clock for retention and ordering tests. Starts at the real time because
/// rebuilt records take their dates from the files on disk.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date()) { current = start }

    var now: Date { lock.withLock { current } }

    func advance(days: Double = 0, seconds: Double = 0) {
        lock.withLock { current = current.addingTimeInterval(days * 86_400 + seconds) }
    }

    var function: @Sendable () -> Date { { [self] in now } }
}
