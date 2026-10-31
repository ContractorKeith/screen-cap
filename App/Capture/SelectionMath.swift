import CoreGraphics
import Foundation

/// Pure geometry for the selection overlay. All rects are global AppKit points.
enum SelectionMath {
    /// Smallest drag that counts as a selection, in points; anything less is a click.
    static let minimumSize: CGFloat = 4

    /// Smallest side, in points, a selection needs before ⇧ locks its own aspect ratio.
    static let minimumAspectSide: CGFloat = 8

    /// The rect between a drag's start and current point, snapped to whole points.
    ///
    /// With `aspect` (width ÷ height), the rect keeps that ratio, anchored at `start`
    /// and growing toward `end` along whichever axis was dragged further.
    /// With `bounds` (the display union), the rect stops at its edges, shrinking both sides
    /// together when an aspect is locked.
    static func rect(from start: CGPoint, to end: CGPoint, aspect: CGFloat? = nil, within bounds: CGRect? = nil)
        -> CGRect {
        var width = abs(end.x - start.x)
        var height = abs(end.y - start.y)
        if let aspect, aspect > 0 {
            if width / aspect > height { height = width / aspect } else { width = height * aspect }
        }
        if let bounds, !bounds.isNull {
            let roomX = max(end.x >= start.x ? bounds.maxX - start.x : start.x - bounds.minX, 0)
            let roomY = max(end.y >= start.y ? bounds.maxY - start.y : start.y - bounds.minY, 0)
            if let aspect, aspect > 0 {
                let fit = min(1, width > 0 ? roomX / width : 1, height > 0 ? roomY / height : 1)
                width *= fit
                height *= fit
            } else {
                width = min(width, roomX)
                height = min(height, roomY)
            }
        }
        let x = end.x >= start.x ? start.x : start.x - width
        let y = end.y >= start.y ? start.y : start.y - height
        return snapped(CGRect(x: x, y: y, width: width, height: height))
    }

    /// The ratio ⇧ locks: the current selection's if both sides are at least `minimumAspectSide`,
    /// else the last known selection's (same rule), else 1:1.
    static func lockedAspect(current: CGRect?, fallback: CGRect?) -> CGFloat {
        for rect in [current, fallback] {
            if let rect, rect.width >= minimumAspectSide, rect.height >= minimumAspectSide {
                return rect.width / rect.height
            }
        }
        return 1
    }

    /// A rect of `size` centered on `point`, kept inside `bounds` when it fits.
    static func fixedRect(size: CGSize, centeredAt point: CGPoint, within bounds: CGRect) -> CGRect {
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        return snapped(clamp(rect, to: bounds))
    }

    /// Moves `rect` (without resizing) so it lies inside `bounds`; pins to the min edge if too big.
    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var rect = rect
        rect.origin.x = max(bounds.minX, min(rect.minX, bounds.maxX - rect.width))
        rect.origin.y = max(bounds.minY, min(rect.minY, bounds.maxY - rect.height))
        return rect
    }

    /// Rounds edges to whole points so crops are pixel-exact at any integer scale.
    static func snapped(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        let maxX = rect.maxX.rounded(), maxY = rect.maxY.rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// True if a dragged rect is big enough to capture.
    static func isSelection(_ rect: CGRect?) -> Bool {
        guard let rect else { return false }
        return rect.width >= minimumSize && rect.height >= minimumSize
    }

    /// Parses a typed size such as `800x600`, `800 × 600` or `800,600`. Nil if not two positive numbers.
    static func parseSize(_ text: String) -> CGSize? {
        let separators = CharacterSet(charactersIn: "xX×*, ")
        let parts = text.components(separatedBy: separators).filter { !$0.isEmpty }
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
              width >= 1, height >= 1 else { return nil }
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    /// Label for a size badge, e.g. `800 × 600`.
    static func sizeLabel(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    /// `#RRGGBB` from 8-bit components.
    static func hex(red: UInt8, green: UInt8, blue: UInt8) -> String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// A global point as display-local points with a top-left origin, for the magnifier readout.
    static func localTopLeft(_ point: CGPoint, in display: CGRect) -> CGPoint {
        CGPoint(x: (point.x - display.minX).rounded(.down), y: (display.maxY - point.y).rounded(.down))
    }
}
