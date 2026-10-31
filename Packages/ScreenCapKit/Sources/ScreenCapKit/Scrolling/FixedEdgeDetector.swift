// Sticky header and footer detection across scrolled frames (PLAN §5.4 step 4).
import CoreGraphics

/// Thickness, in pixels, of the lines that never change at each end of the frame.
public struct FixedEdges: Equatable, Sendable {
    /// Top rows (vertical) or left columns (horizontal), e.g. a sticky header or sidebar.
    public var leading: Int
    /// Bottom rows (vertical) or right columns (horizontal), e.g. a sticky footer.
    public var trailing: Int

    public init(leading: Int = 0, trailing: Int = 0) {
        self.leading = leading
        self.trailing = trailing
    }

    public static let none = FixedEdges()
}

/// Finds lines identical in every frame at the leading and trailing edges.
public enum FixedEdgeDetector {
    /// Detects fixed edges across `frames` (all the same size, ideally all scrolled apart).
    /// Fewer than two frames, or frames that are entirely identical, give `.none`.
    public static func detect(frames: [CGImage], axis: ScrollAxis) -> FixedEdges {
        guard let first = frames.first,
              frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else { return .none }
        let space = PixelFrame.workingSpace(for: first)
        let hashes = frames.compactMap { PixelFrame(image: $0, colorSpace: space)?.lineHashes(along: axis) }
        guard hashes.count == frames.count else { return .none }
        return detect(lineHashes: hashes)
    }

    /// Hash-level detection used by the stitcher.
    static func detect(lineHashes frames: [[LineHash]]) -> FixedEdges {
        guard frames.count >= 2, let first = frames.first, !first.isEmpty else { return .none }
        let count = first.count
        guard frames.allSatisfy({ $0.count == count }) else { return .none }
        func isFixed(_ line: Int) -> Bool { frames.allSatisfy { $0[line] == first[line] } }

        var leading = 0
        while leading < count, isFixed(leading) { leading += 1 }
        if leading == count { return .none } // nothing moved; no evidence either way
        var trailing = 0
        while trailing < count - leading, isFixed(count - 1 - trailing) { trailing += 1 }
        return FixedEdges(leading: leading, trailing: trailing)
    }
}
