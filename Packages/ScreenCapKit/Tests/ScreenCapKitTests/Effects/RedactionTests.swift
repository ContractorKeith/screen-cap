import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

// Serialized: concurrent Vision + Core Image requests deadlock on GitHub's paravirtualized macOS runners.
@Suite("Redaction", .serialized)
struct RedactionTests {
    static let text = "Secret payroll password hunter"
    static let words = Set(text.lowercased().split(separator: " ").map(String.init))
    static let textRect = CGRect(x: 10, y: 10, width: 740, height: 80)

    /// PLAN §5.6: no recognized token of 3+ characters may match an original word.
    static func leakedWords(in image: CGImage) throws -> [String] {
        let recognized = try EffectsFixtures.recognizedText(in: image)
        let tokens = recognized.flatMap { string in
            string.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        let exact = tokens.filter { $0.count >= 3 && words.contains($0) }
        let joined = recognized.joined(separator: " ").lowercased()
        let contained = words.filter { joined.contains($0) }
        return exact + contained
    }

    @Test func visionReadsUnredactedFixture() throws {
        // Guards the redaction tests: the fixture must be readable before redaction.
        let image = try EffectsFixtures.textImage(Self.text)
        #expect(try Self.leakedWords(in: image).count >= 2)
    }

    @Test func secureBlurDefeatsOCR() throws {
        let image = try EffectsFixtures.textImage(Self.text)
        let redacted = try Redaction.blur(image, rect: Self.textRect, radius: 8, mode: .secure, seed: 7)
        #expect(try Self.leakedWords(in: redacted).isEmpty)
    }

    @Test func randomizedPixelateDefeatsOCR() throws {
        let image = try EffectsFixtures.textImage(Self.text)
        let redacted = try Redaction.pixelate(image, rect: Self.textRect, blockSize: 14, randomize: true, seed: 7)
        #expect(try Self.leakedWords(in: redacted).isEmpty)
    }

    @Test func pixelateIsDeterministicPerSeed() throws {
        let image = try EffectsFixtures.textImage(Self.text)
        let first = try Redaction.pixelate(image, rect: Self.textRect, blockSize: 10, randomize: true, seed: 42)
        let second = try Redaction.pixelate(image, rect: Self.textRect, blockSize: 10, randomize: true, seed: 42)
        let other = try Redaction.pixelate(image, rect: Self.textRect, blockSize: 10, randomize: true, seed: 43)
        #expect(try EffectsFixtures.bytes(first) == EffectsFixtures.bytes(second))
        #expect(try EffectsFixtures.bytes(first) != EffectsFixtures.bytes(other))
    }

    @Test func pixelateLeavesPixelsOutsideRectUntouched() throws {
        let image = try EffectsFixtures.textImage(Self.text)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let redacted = try Redaction.pixelate(image, rect: rect, blockSize: 10, randomize: true, seed: 1)
        for x in [200, 400, 700] {
            for y in [5, 50, 95] {
                #expect(try EffectsFixtures.pixel(redacted, x: x, y: y) == EffectsFixtures.pixel(image, x: x, y: y))
            }
        }
    }

    @Test func plainPixelateFillsBlocksWithAverage() throws {
        // Left half black, right half white: a block straddling the edge averages to mid gray.
        let image = try EffectsFixtures.image(width: 20, height: 10, fill: .white) { context in
            context.setFillColor(RGBAColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let rect = CGRect(x: 5, y: 0, width: 10, height: 10)
        let redacted = try Redaction.pixelate(image, rect: rect, blockSize: 10, randomize: false)
        let value = try EffectsFixtures.pixel(redacted, x: 9, y: 5)
        #expect((126...129).contains(value[0]))
        #expect(try EffectsFixtures.pixel(redacted, x: 14, y: 5) == value)
        #expect(try EffectsFixtures.pixel(redacted, x: 2, y: 5)[0] == 0)
    }

    @Test func smoothBlurChangesOnlyTheRect() throws {
        let image = try EffectsFixtures.textImage(Self.text)
        let rect = CGRect(x: 0, y: 0, width: 300, height: 100)
        let blurred = try Redaction.blur(image, rect: rect, radius: 6, mode: .smooth)
        #expect(blurred.width == image.width && blurred.height == image.height)
        #expect(try EffectsFixtures.pixel(blurred, x: 500, y: 50) == EffectsFixtures.pixel(image, x: 500, y: 50))
        #expect(try EffectsFixtures.bytes(blurred) != EffectsFixtures.bytes(image))
    }
}
