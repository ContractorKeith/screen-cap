// "Capture previous area": remembers the last area selection.
import CoreGraphics

/// Where `PreviousArea` keeps its rect. Settings can provide a persistent store later.
@MainActor
public protocol PreviousAreaStore: AnyObject {
    /// The last area in global AppKit points, or nil if none.
    var lastRect: CGRect? { get set }
}

/// Keeps the rect in memory only; forgotten on quit.
@MainActor
public final class InMemoryPreviousAreaStore: PreviousAreaStore {
    public var lastRect: CGRect?

    public init(lastRect: CGRect? = nil) {
        self.lastRect = lastRect
    }
}

/// Remembers the last captured area (global AppKit points) for "Capture previous area".
@MainActor
public final class PreviousArea {
    private let store: PreviousAreaStore

    public init(store: PreviousAreaStore = InMemoryPreviousAreaStore()) {
        self.store = store
    }

    /// The remembered rect, or nil if nothing has been captured yet.
    public var rect: CGRect? { store.lastRect }

    /// Remembers `rect`. Empty or degenerate rects are ignored so a stray click can't replace a real area.
    public func remember(_ rect: CGRect) {
        let rect = rect.standardized
        guard !rect.isNull, !rect.isInfinite, rect.width >= 1, rect.height >= 1 else { return }
        store.lastRect = rect
    }

    /// Forgets the remembered rect.
    public func clear() {
        store.lastRect = nil
    }

    /// The remembered rect if it still overlaps a display in `geometry`, else nil.
    ///
    /// Use this after a display is unplugged, so the previous area doesn't point off-screen.
    public func rect(validIn geometry: DisplayGeometry) -> CGRect? {
        guard let rect, !geometry.slices(forGlobalPoints: rect).isEmpty else { return nil }
        return rect
    }
}
