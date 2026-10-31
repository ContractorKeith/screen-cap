import CoreGraphics
import ScreenCapKit

/// The screen grabs the coordinator's flows make. `CaptureService` is the live one;
/// tests pass a fake so the flows run headless.
protocol CaptureSource: Sendable {
    func captureDisplay(_ id: CGDirectDisplayID) async throws -> CapturedImage
    func captureAllDisplays() async throws -> [CapturedImage]
    func captureArea(pointRect: CGRect) async throws -> CapturedImage
    func captureWindow(id: CGWindowID, includeShadow: Bool) async throws -> CapturedImage
    func shareableWindows() async throws -> [ShareableWindow]
}

extension CaptureService: CaptureSource {}
