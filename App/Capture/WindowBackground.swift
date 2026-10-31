import AppKit
import ScreenCapKit

/// "Window with background" (PLAN §3.1, #89): a window capture composited onto the Wallpaper
/// settings. The result stays full resolution; the output scale applies later, at save/copy.
enum WindowBackground {
    /// Composites off the main actor; on failure logs and returns the plain window image.
    @MainActor
    static func apply(_ options: WallpaperOptions, to image: CapturedImage, around frame: CGRect) async
        -> CapturedImage {
        let wallpaper = wallpaperURL(options, near: frame)
        do {
            return try await Task.detached(priority: .userInitiated) {
                try composite(image, options: options, wallpaper: wallpaper.flatMap(loadImage))
            }.value
        } catch {
            appLog.error("Window background failed: \(error.localizedDescription, privacy: .public)")
            return image
        }
    }

    /// `image` on the options' fill with `padding` points on every side. `wallpaper` is the
    /// desktop picture or custom image; without one those styles fall back to the gradient.
    /// The window keeps its own corners and system shadow, so none are added here.
    static func composite(_ image: CapturedImage, options: WallpaperOptions, wallpaper: CGImage?) throws
        -> CapturedImage {
        var background = options.background(hasImage: wallpaper != nil)
        background.padding = (background.padding * Double(image.scale)).rounded()
        background.cornerRadius = 0
        background.shadow = nil
        let layers = wallpaper.map { [WallpaperOptions.imageLayerName: $0] } ?? [:]
        let output = try BackgroundCompositor.render(image.cgImage, background: background, layers: layers)
        let pad = CGFloat(background.padding) / image.scale
        return CapturedImage(cgImage: output, scale: image.scale,
                             pointRect: image.pointRect.insetBy(dx: -pad, dy: -pad), displayID: image.displayID)
    }

    /// Custom image, or the desktop picture of the screen holding most of the window.
    @MainActor
    static func wallpaperURL(_ options: WallpaperOptions, near frame: CGRect) -> URL? {
        switch options.style {
        case .solid, .gradient:
            return nil
        case .image:
            return options.imageURL
        case .desktop:
            let screen = NSScreen.screens.max {
                area($0.frame.intersection(frame)) < area($1.frame.intersection(frame))
            }
            return (screen ?? NSScreen.main).flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
