// Area images that span displays: one canvas composited from each display's still (PLAN §5.1).
import CoreGraphics

/// Builds the image of a global point rect from per-display stills. Pure; no screen access.
public enum AreaCompositor {
    /// The part of `rect` that lies on displays, cut from `stills` (one per display, matched by ID).
    ///
    /// One display: a plain crop of its still. Several: a canvas at the highest backing scale of the
    /// displays touched, each slice drawn where it sits; gaps between displays stay transparent.
    /// Returns nil if the rect touches no display or a touched display has no still.
    public static func image(of rect: CGRect, geometry: DisplayGeometry, stills: [CapturedImage]) -> CapturedImage? {
        let slices = geometry.slices(forGlobalPoints: rect)
        let pieces = slices.compactMap { slice in
            stills.first { $0.displayID == slice.display.id }.map { (slice: slice, still: $0) }
        }
        guard !pieces.isEmpty, pieces.count == slices.count else { return nil }
        if pieces.count == 1 { return pieces[0].still.cropped(toGlobalPoints: rect) }

        let area = slices.reduce(CGRect.null) { $0.union($1.pointRect) }
        let scale = slices.map(\.display.backingScale).max() ?? 1
        let width = Int((area.width * scale).rounded()), height = Int((area.height * scale).rounded())
        guard width > 0, height > 0,
              let space = pieces[0].still.cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        for piece in pieces {
            guard let crop = piece.still.cropped(toGlobalPoints: piece.slice.pointRect) else { return nil }
            // CGContext has a bottom-left origin, like AppKit's global space, so no flip is needed.
            context.draw(crop.cgImage, in: destination(of: piece.slice.pointRect, in: area, scale: scale))
        }
        guard let image = context.makeImage() else { return nil }
        let displayID = geometry.display(bestFor: area)?.id
        return CapturedImage(cgImage: image, scale: scale, pointRect: area, displayID: displayID)
    }

    /// Pixel rect (bottom-left origin) of a slice inside the canvas covering `area`.
    static func destination(of slice: CGRect, in area: CGRect, scale: CGFloat) -> CGRect {
        let minX = ((slice.minX - area.minX) * scale).rounded(), maxX = ((slice.maxX - area.minX) * scale).rounded()
        let minY = ((slice.minY - area.minY) * scale).rounded(), maxY = ((slice.maxY - area.minY) * scale).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
