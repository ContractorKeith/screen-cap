import CoreGraphics
import Foundation
import ImageIO
@testable import ScreenCapKit
import Testing

@Suite("Exporter")
struct ExporterTests {
    private let image = RenderFixtures.solidImage(RenderFixtures.blue, width: 120, height: 80)

    static let imageFormats: [ExportFormat] = [.png, .jpeg(quality: 0.8), .heic(quality: 0.8), .tiff]

    @Test(arguments: imageFormats)
    func roundTripsThroughImageSource(format: ExportFormat) throws {
        let data = try Exporter(image: image, format: format).data()
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 1)
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 120 && decoded.height == 80)
        #expect(RenderedPixels(decoded)[60, 40].matches(RenderFixtures.blue, tolerance: 12))
    }

    @Test(arguments: imageFormats)
    func doubleScaleSetsDPI(format: ExportFormat) throws {
        let data = try Exporter(image: image, format: format, scale: 2).data()
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyDPIWidth] as? Double).map { abs($0 - 144) < 1 } == true)
        #expect((properties[kCGImagePropertyDPIHeight] as? Double).map { abs($0 - 144) < 1 } == true)
    }

    @Test(arguments: [1.0, 2.0])
    func pdfHasOnePageSizedInPoints(scale: Double) throws {
        let data = try Exporter(image: image, format: .pdf, scale: scale).data()
        let provider = try #require(CGDataProvider(data: data as CFData))
        let pdf = try #require(CGPDFDocument(provider))
        #expect(pdf.numberOfPages == 1)
        let box = try #require(pdf.page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.size == CGSize(width: 120 / scale, height: 80 / scale))
    }

    @Test func writesToURL() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("shot.png")
        try Exporter(image: image, format: .png).write(to: url)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 120)
    }

    @Test func mapsSavedFormats() {
        #expect(ExportFormat(.jpeg, quality: 0.7) == .jpeg(quality: 0.7))
        #expect(ExportFormat(.png, quality: 0.7) == .png)
        for format in ImageFormat.allCases {
            #expect(ExportFormat(format, quality: 1).fileExtension == format.fileExtension)
        }
    }

    @Test func invalidScaleThrows() {
        #expect(throws: ExportError.invalidScale(0)) { try Exporter(image: image, format: .png, scale: 0).data() }
    }
}

extension ExportFormat: CustomTestStringConvertible {
    public var testDescription: String { fileExtension }
}
