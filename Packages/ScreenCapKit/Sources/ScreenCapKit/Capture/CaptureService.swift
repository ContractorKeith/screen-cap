// Thin ScreenCaptureKit wrapper: display, area and window stills (PLAN §5.1, §5.2).
// Needs the real screen and Screen Recording permission, so it is not unit-tested;
// the geometry and cropping it relies on are.
import AppKit
import ScreenCaptureKit

/// Captures stills with `SCScreenshotManager`. No persistent streams.
///
/// Our own app's windows (overlays, Quick Access, pins) are always excluded, except the ones
/// `includedOwnWindows` returns (the desktop-icon covers, which must show up in captures).
public actor CaptureService {
    /// Supplies the current display arrangement.
    public typealias GeometryProvider = @Sendable () async -> DisplayGeometry
    /// Supplies our own window IDs that display captures should keep.
    public typealias WindowIDProvider = @Sendable () async -> Set<CGWindowID>

    private let excludedBundleIdentifier: String?
    private let showsCursor: Bool
    private let geometryProvider: GeometryProvider
    private let includedOwnWindows: WindowIDProvider

    /// - Parameters:
    ///   - excludedBundleIdentifier: App whose windows never appear in captures. Defaults to this app.
    ///   - showsCursor: Draw the mouse cursor into display captures.
    ///   - geometryProvider: Source of display frames and scales. Defaults to `NSScreen`.
    ///   - includedOwnWindows: Our own windows to keep in display captures despite the exclusion.
    public init(
        excludedBundleIdentifier: String? = Bundle.main.bundleIdentifier ?? ScreenCapKit.bundleIdentifier,
        showsCursor: Bool = false,
        geometryProvider: @escaping GeometryProvider = { @MainActor in DisplayGeometry.fromCurrentScreens() },
        includedOwnWindows: @escaping WindowIDProvider = { [] }
    ) {
        self.excludedBundleIdentifier = excludedBundleIdentifier
        self.showsCursor = showsCursor
        self.geometryProvider = geometryProvider
        self.includedOwnWindows = includedOwnWindows
    }

    /// Captures one whole display at its native pixel size.
    public func captureDisplay(_ id: CGDirectDisplayID) async throws -> CapturedImage {
        let geometry = await geometryProvider()
        let content = try await Self.shareableContent()
        guard let info = geometry.display(id: id),
              let display = content.value.displays.first(where: { $0.displayID == id }) else {
            throw CaptureError.displayNotFound(id)
        }
        let request = DisplayRequest(display: display, info: info, excluded: excludedApps(in: content.value),
                                     excepted: await exceptedWindows(in: content.value))
        return try await Self.capture(Unchecked(request), showsCursor: showsCursor)
    }

    /// Captures every display in parallel, in `DisplayGeometry` order. Used for the frozen overlay.
    public func captureAllDisplays() async throws -> [CapturedImage] {
        let geometry = await geometryProvider()
        let content = try await Self.shareableContent()
        let excluded = excludedApps(in: content.value)
        let excepted = await exceptedWindows(in: content.value)
        let requests = geometry.displays.compactMap { info -> Unchecked<DisplayRequest>? in
            guard let display = content.value.displays.first(where: { $0.displayID == info.id }) else { return nil }
            return Unchecked(DisplayRequest(display: display, info: info, excluded: excluded, excepted: excepted))
        }
        let showsCursor = showsCursor
        return try await withThrowingTaskGroup(of: (Int, CapturedImage).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask { (index, try await Self.capture(request, showsCursor: showsCursor)) }
            }
            var results: [(Int, CapturedImage)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Captures a global point rect by grabbing every display it touches and compositing them.
    ///
    /// A rect spanning displays comes back whole, at the highest backing scale it touches.
    /// For frozen-screen selection, composite existing stills with `AreaCompositor.image(of:geometry:stills:)`.
    public func captureArea(pointRect: CGRect) async throws -> CapturedImage {
        let geometry = await geometryProvider()
        let slices = geometry.slices(forGlobalPoints: pointRect)
        guard !slices.isEmpty else { throw CaptureError.areaOffScreen(pointRect) }
        var stills: [CapturedImage] = []
        for slice in slices {
            stills.append(try await captureDisplay(slice.display.id))
        }
        guard let image = AreaCompositor.image(of: pointRect, geometry: geometry, stills: stills) else {
            throw CaptureError.areaOffScreen(pointRect)
        }
        return image
    }

    /// Captures one window on its own, so overlapping windows don't show through.
    ///
    /// - Parameter includeShadow: Keep the system window shadow (with transparent surround).
    public func captureWindow(id: CGWindowID, includeShadow: Bool) async throws -> CapturedImage {
        let geometry = await geometryProvider()
        let content = try await Self.shareableContent()
        guard let window = content.value.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError.windowNotFound(id)
        }
        let frame = geometry.appKitRect(fromQuartz: window.frame)
        let displayID = geometry.display(bestFor: frame)?.id
        let request = WindowRequest(window: window, frame: frame, displayID: displayID, includeShadow: includeShadow)
        return try await Self.capture(Unchecked(request))
    }

    /// On-screen windows, front to back, excluding our own app and zero-size windows.
    public func shareableWindows() async throws -> [ShareableWindow] {
        let geometry = await geometryProvider()
        let content = try await Self.shareableContent()
        let windows = content.value.windows.compactMap { window -> ShareableWindow? in
            guard window.isOnScreen, window.frame.width >= 1, window.frame.height >= 1 else { return nil }
            let app = window.owningApplication
            if let excludedBundleIdentifier, app?.bundleIdentifier == excludedBundleIdentifier { return nil }
            return ShareableWindow(
                id: window.windowID,
                frame: geometry.appKitRect(fromQuartz: window.frame),
                title: window.title,
                appName: app?.applicationName,
                bundleIdentifier: app?.bundleIdentifier,
                processID: app?.processID ?? 0,
                layer: window.windowLayer
            )
        }
        return ShareableWindow.orderedFrontToBack(windows, zOrder: Self.windowZOrder())
    }

    // MARK: - ScreenCaptureKit plumbing

    private func excludedApps(in content: SCShareableContent) -> [SCRunningApplication] {
        guard let excludedBundleIdentifier else { return [] }
        return content.applications.filter { $0.bundleIdentifier == excludedBundleIdentifier }
    }

    private func exceptedWindows(in content: SCShareableContent) async -> [SCWindow] {
        let ids = await includedOwnWindows()
        guard !ids.isEmpty else { return [] }
        return content.windows.filter { ids.contains($0.windowID) }
    }

    private static func shareableContent() async throws -> Unchecked<SCShareableContent> {
        Unchecked(try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true))
    }

    /// Window IDs frontmost first. Window metadata only; no pixels are read here.
    private static func windowZOrder() -> [CGWindowID] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }

    private static func capture(_ request: Unchecked<DisplayRequest>, showsCursor: Bool) async throws -> CapturedImage {
        let request = request.value
        let filter = SCContentFilter(
            display: request.display, excludingApplications: request.excluded, exceptingWindows: request.excepted
        )
        let config = SCStreamConfiguration()
        let pixelSize = request.info.pixelSize
        config.width = Int(pixelSize.width)
        config.height = Int(pixelSize.height)
        config.captureResolution = .best
        config.showsCursor = showsCursor
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CapturedImage(
            cgImage: image,
            scale: request.info.backingScale,
            pointRect: request.info.frame,
            displayID: request.info.id
        )
    }

    private static func capture(_ request: Unchecked<WindowRequest>) async throws -> CapturedImage {
        let request = request.value
        let filter = SCContentFilter(desktopIndependentWindow: request.window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = !request.includeShadow
        config.showsCursor = false
        var image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        // With the shadow, the first capture squeezes window + shadow into the frame size; re-capture
        // larger so the window body stays one pixel per pixel (see WindowShadow).
        if request.includeShadow, let body = WindowShadow.opaqueBounds(of: image),
           let size = WindowShadow.fullSize(
               canvas: CGSize(width: image.width, height: image.height),
               body: body,
               bodyPixels: CGSize(width: config.width, height: config.height)
           ) {
            config.width = Int(size.width)
            config.height = Int(size.height)
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
        // Drop canvas past the shadow and even out the margins so the window sits centered (#100).
        if request.includeShadow, let trimmed = WindowShadow.trimmed(image) { image = trimmed }
        return CapturedImage(cgImage: image, scale: scale, pointRect: request.frame, displayID: request.displayID)
    }
}

private struct DisplayRequest {
    let display: SCDisplay
    let info: DisplayInfo
    let excluded: [SCRunningApplication]
    let excepted: [SCWindow]
}

private struct WindowRequest {
    let window: SCWindow
    let frame: CGRect
    let displayID: CGDirectDisplayID?
    let includeShadow: Bool
}

/// Carries ScreenCaptureKit objects across tasks. They are immutable snapshots, but not marked Sendable.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
