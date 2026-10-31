import CoreGraphics
import ScreenCapKit

extension ScreenCorner {
    var isLeft: Bool { self == .bottomLeft || self == .topLeft }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
}

/// Pure geometry for the Quick Access stack. All rects are AppKit screen points (origin bottom-left).
enum QuickAccessLayout {
    /// Gap between the stack and the screen edges.
    static let margin: CGFloat = 16
    /// Gap between neighbouring panels.
    static let spacing: CGFloat = 12
    /// Inset of the thumbnail inside its panel.
    static let padding: CGFloat = 6
    /// Height of the two-line file info under the thumbnail.
    static let infoHeight: CGFloat = 30

    /// Thumbnail width in points for each size setting.
    static func thumbnailWidth(_ size: QuickAccessSize) -> CGFloat {
        switch size {
        case .small: 180
        case .medium: 240
        case .large: 320
        }
    }

    /// Thumbnail size for an image: fixed width, height from the aspect ratio, clamped so very
    /// wide or very tall captures (scrolling) don't make unusable panels.
    static func thumbnailSize(imageSize: CGSize, size: QuickAccessSize) -> CGSize {
        let width = thumbnailWidth(size)
        let aspect = imageSize.width > 0 ? imageSize.height / imageSize.width : 1
        let height = min(max(width * aspect, width * 0.5), width * 1.25)
        return CGSize(width: width, height: height.rounded())
    }

    /// Whole panel: thumbnail plus padding plus the info line.
    static func panelSize(imageSize: CGSize, size: QuickAccessSize) -> CGSize {
        let thumb = thumbnailSize(imageSize: imageSize, size: size)
        return CGSize(width: thumb.width + 2 * padding, height: thumb.height + 2 * padding + infoHeight)
    }

    /// Frames for a stack of panels, newest first (index 0 sits nearest the corner).
    ///
    /// Panels stack away from the corner along the vertical edge; when a column is full the
    /// next panel starts a new column further from the side edge.
    static func frames(for sizes: [CGSize], corner: ScreenCorner, in visible: CGRect) -> [CGRect] {
        var frames: [CGRect] = []
        var columnOffset: CGFloat = 0
        var columnWidth: CGFloat = 0
        var along = margin
        for size in sizes {
            let fits = along + size.height <= visible.height - margin
            if !fits, columnWidth > 0 {
                columnOffset += columnWidth + spacing
                columnWidth = 0
                along = margin
            }
            let x = corner.isLeft
                ? visible.minX + margin + columnOffset
                : visible.maxX - margin - columnOffset - size.width
            let y = corner.isBottom
                ? visible.minY + along
                : visible.maxY - along - size.height
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            along += size.height + spacing
            columnWidth = max(columnWidth, size.width)
        }
        return frames
    }

    /// Where a panel starts its slide-in: pushed past the side edge it docks against.
    static func entryFrame(for frame: CGRect, corner: ScreenCorner) -> CGRect {
        let shift = frame.width + margin
        return frame.offsetBy(dx: corner.isLeft ? -shift : shift, dy: 0)
    }
}
