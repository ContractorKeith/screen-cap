import CoreGraphics
import Foundation
import ScreenCapKit

// Whole-image edits: crop, rotate, flip, resize, and the Background tool.

extension EditorDocumentModel {
    // MARK: - Crop

    /// Starts crop mode with the whole image selected and detects UI edges to snap to.
    func beginCrop() {
        tool = .crop
        selection = []
        cropRect = CGRect(origin: .zero, size: snapshot.imageSize)
        cropEdges = CropEdges()
        let image = baseImage
        let revisionAtStart = revision
        Task.detached(priority: .userInitiated) {
            let edges = CropEdgeDetector.edges(in: image)
            await MainActor.run { [weak self] in
                guard let self, self.revision == revisionAtStart else { return }
                self.cropEdges = edges
            }
        }
        touch()
    }

    var cropRatio: Double? { cropAspect.ratio(custom: customAspect) }

    /// Crops the base image to `cropRect` and leaves crop mode.
    func applyCrop() {
        guard let rect = cropRect else { return }
        let full = CGRect(origin: .zero, size: snapshot.imageSize)
        if CropMath.pixelRect(rect, imageSize: full.size) != full, let result = ImageOps.crop(baseImage, to: rect) {
            apply(result)
        }
        tool = .select
        touch()
    }

    func cancelCrop() {
        tool = .select
        touch()
    }

    /// Re-fits the crop rect to the chosen aspect, centered on the current one.
    func setCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        guard let ratio = cropRatio, let rect = cropRect else { touch(); return }
        var width = rect.width, height = rect.height
        if width / max(height, 1) > ratio { width = height * ratio } else { height = width / ratio }
        cropRect = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
            .intersection(CGRect(origin: .zero, size: snapshot.imageSize))
        touch()
    }

    // MARK: - Rotate, flip, resize

    func rotate(clockwise: Bool) {
        if let result = ImageOps.rotate(baseImage, clockwise: clockwise) { apply(result) }
    }

    func flip(horizontal: Bool) {
        if let result = ImageOps.flip(baseImage, horizontal: horizontal) { apply(result) }
    }

    /// Resamples the base image to `size` pixels; annotations scale with it. Sizes outside
    /// `ResizeLimits` are ignored (the dialog already refuses them).
    func resizeImage(to size: CGSize) {
        guard let size = ResizeLimits.validate(size).size, size != snapshot.imageSize else { return }
        if let result = ImageOps.resize(baseImage, to: size) { apply(result) }
    }

    private func apply(_ result: ImageOps.Result) {
        perform { $0.replaceBase(with: result.image, scale: result.scale, mapping: result.map) }
    }

    // MARK: - Background

    /// Sets or clears the background and refits the canvas. Slider drags pass a group key.
    /// Auto Balance's per-edge padding survives other edits until `padding` itself changes.
    func setBackground(_ background: Document.Background?, aspect: Double?, groupKey: String? = nil) {
        var background = background
        if let old = document.background, background?.padding != old.padding { background?.edgePadding = nil }
        perform(groupKey: groupKey) { snapshot in
            snapshot.document.background = background
            snapshot.backgroundAspect = background == nil ? nil : aspect
            snapshot.refitCanvas()
        }
    }

    /// Edits the current background (adding a default one first if there is none).
    func updateBackground(groupKey: String? = nil, _ change: (inout Document.Background) -> Void) {
        var background = document.background ?? Self.defaultBackground
        change(&background)
        setBackground(background, aspect: snapshot.backgroundAspect, groupKey: groupKey)
    }

    /// Uses `image` as the background fill, stored as a layer in the project.
    func setCustomBackground(_ image: CGImage) {
        let name = "background-\(UUID().uuidString.prefix(8).lowercased())"
        perform { snapshot in
            snapshot.layers[name] = image
            var background = snapshot.document.background ?? Self.defaultBackground
            background.fill = .customImage(layerName: name)
            snapshot.document.background = background
            snapshot.refitCanvas()
        }
    }

    /// Auto Balance (PLAN §5.5): padding and alignment that visually center the content.
    func autoBalance() {
        let shadow = document.background?.shadow
        guard let insets = try? AutoBalance.padding(for: baseImage, shadow: shadow) else { return }
        let balanced = BackgroundMath.balanced(insets)
        perform { snapshot in
            var background = snapshot.document.background ?? Self.defaultBackground
            background.padding = balanced.padding
            background.alignment = balanced.alignment
            // The canvas takes the per-edge padding; padding plus alignment place the image in it.
            background.edgePadding = balanced.edges
            snapshot.document.background = background
            snapshot.backgroundAspect = nil
            snapshot.refitCanvas()
        }
    }

    func applyPreset(_ preset: BackgroundPreset, preferences: EditorPreferences = .shared) throws {
        guard case .customImage = preset.background.fill else {
            setBackground(preset.background, aspect: preset.aspect)
            return
        }
        // Load before editing: legacy or missing images must not leave a dangling layer reference.
        let image = try preferences.presetImages.load(for: preset.id)
        let name = "background-\(UUID().uuidString.lowercased())"
        var background = preset.background
        background.fill = .customImage(layerName: name)
        perform { snapshot in
            snapshot.layers[name] = image
            snapshot.document.background = background
            snapshot.backgroundAspect = preset.aspect
            snapshot.refitCanvas()
        }
    }

    static let defaultBackground = Document.Background(fill: .bundled(name: BundledBackgrounds.names[0]))
}

/// Finds strong straight horizontal and vertical edges (window borders, panels) for crop snapping.
enum CropEdgeDetector {
    /// Rows and columns whose average brightness step to the next one exceeds `threshold`
    /// (0...255), thinned so snaps are at least `spacing` pixels apart. Downsamples large images.
    static func edges(in image: CGImage, threshold: Double = 24, spacing: Double = 6) -> CropEdges {
        let maxSide = 1200.0
        let factor = min(1, maxSide / Double(max(image.width, image.height)))
        let width = max(2, Int(Double(image.width) * factor)), height = max(2, Int(Double(image.height) * factor))
        guard let gray = grayscale(image, width: width, height: height) else { return CropEdges() }
        func value(_ x: Int, _ y: Int) -> Double { Double(gray[y * width + x]) }

        var yEdges: [Double] = []
        for row in 0..<(height - 1) {
            let step = (0..<width).reduce(0.0) { $0 + abs(value($1, row + 1) - value($1, row)) } / Double(width)
            if step > threshold { yEdges.append(Double(row + 1) / factor) }
        }
        var xEdges: [Double] = []
        for column in 0..<(width - 1) {
            let step = (0..<height).reduce(0.0) { $0 + abs(value(column + 1, $1) - value(column, $1)) } / Double(height)
            if step > threshold { xEdges.append(Double(column + 1) / factor) }
        }
        let gap = spacing / factor
        return CropEdges(xEdges: thinned(xEdges, spacing: gap), yEdges: thinned(yEdges, spacing: gap))
    }

    private static func thinned(_ values: [Double], spacing: Double) -> [Double] {
        values.reduce(into: [Double]()) { result, value in
            if let last = result.last, value - last < spacing { return }
            result.append(value.rounded())
        }
    }

    private static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
