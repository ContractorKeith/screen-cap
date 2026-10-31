import CoreGraphics

/// Pure size, zoom, opacity and nudge math for pinned screenshots. Unit-tested.
enum PinMath {
    /// Zoom limits, as a multiple of the image's 1x point size.
    static let scaleRange: ClosedRange<CGFloat> = 0.1...8
    /// Each ⌘+ / ⌘− step multiplies or divides by this.
    static let zoomStep: CGFloat = 1.25
    /// Smallest pin edge in points, so a pin can't vanish.
    static let minimumEdge: CGFloat = 40
    /// Share of the screen's visible frame a pin may cover when "fit".
    static let fitFraction: CGFloat = 0.9

    // MARK: Size

    /// The size at `scale` × the 1x point size, never below `minimumEdge` on the short side.
    static func size(for pointSize: CGSize, scale: CGFloat) -> CGSize {
        let scale = clampScale(scale, pointSize: pointSize)
        return CGSize(width: (pointSize.width * scale).rounded(), height: (pointSize.height * scale).rounded())
    }

    static func clampScale(_ scale: CGFloat, pointSize: CGSize) -> CGFloat {
        let shortSide = min(pointSize.width, pointSize.height)
        let floor = shortSide > 0 ? max(scaleRange.lowerBound, minimumEdge / shortSide) : scaleRange.lowerBound
        return min(max(scale, min(floor, scaleRange.upperBound)), scaleRange.upperBound)
    }

    /// A user's edge drag (`proposed`) snapped back to the image aspect ratio.
    /// Follows whichever edge moved more, relative to the current size.
    static func aspectResize(current: CGSize, proposed: CGSize, pointSize: CGSize) -> CGSize {
        guard pointSize.width > 0, pointSize.height > 0, current.width > 0, current.height > 0 else { return proposed }
        let widthChange = abs(proposed.width - current.width) / current.width
        let heightChange = abs(proposed.height - current.height) / current.height
        let scale = widthChange >= heightChange
            ? proposed.width / pointSize.width
            : proposed.height / pointSize.height
        return size(for: pointSize, scale: scale)
    }

    /// The scale of `size` relative to the 1x point size (by width).
    static func scale(of size: CGSize, pointSize: CGSize) -> CGFloat {
        pointSize.width > 0 ? size.width / pointSize.width : 1
    }

    // MARK: Zoom

    /// ⌘+ (`steps` > 0) or ⌘− (`steps` < 0).
    static func zoomed(_ scale: CGFloat, steps: Int, pointSize: CGSize) -> CGFloat {
        clampScale(scale * pow(zoomStep, CGFloat(steps)), pointSize: pointSize)
    }

    /// Largest scale (≤ 1) at which the image fits `fitFraction` of `visibleFrame`.
    static func fitScale(pointSize: CGSize, visibleFrame: CGSize) -> CGFloat {
        guard pointSize.width > 0, pointSize.height > 0 else { return 1 }
        let fit = min(visibleFrame.width * fitFraction / pointSize.width,
                      visibleFrame.height * fitFraction / pointSize.height)
        return min(1, fit)
    }

    /// Double-click: anything but 100% goes to 100%; 100% goes to fit, or half size if it already fits.
    static func doubleClickScale(current: CGFloat, fitScale: CGFloat) -> CGFloat {
        guard abs(current - 1) < 0.01 else { return 1 }
        return fitScale < 0.99 ? fitScale : 0.5
    }

    // MARK: Opacity

    /// Opacity limits; ⌘[ / ⌘] step by `opacityStep`.
    static let opacityRange: ClosedRange<Double> = 0.1...1
    static let opacityStep = 0.1

    /// One ⌘[ (`steps` < 0) or ⌘] (`steps` > 0) away, snapped to tenths and clamped to 10–100%.
    static func opacity(_ current: Double, steps: Int) -> Double {
        let raw = ((current + Double(steps) * opacityStep) * 10).rounded() / 10
        return min(max(raw, opacityRange.lowerBound), opacityRange.upperBound)
    }

    // MARK: Nudge

    // swiftlint:disable:next identifier_name
    enum Arrow { case left, right, up, down }

    /// Arrow-key move in AppKit points (y up): 1 pt, or 10 with ⇧.
    static func nudge(_ arrow: Arrow, shift: Bool) -> CGVector {
        let step: CGFloat = shift ? 10 : 1
        switch arrow {
        case .left: return CGVector(dx: -step, dy: 0)
        case .right: return CGVector(dx: step, dy: 0)
        case .up: return CGVector(dx: 0, dy: step)
        case .down: return CGVector(dx: 0, dy: -step)
        }
    }
}

/// Lock Mode for one pin. Locked pins pass clicks through, so only the menu-bar item unlocks them.
enum PinLockState: Equatable {
    case interactive
    case locked
    case closed

    enum Event { case toggleLock, unlockAll, close }

    func handling(_ event: Event) -> PinLockState {
        switch (self, event) {
        case (.closed, _): .closed
        case (_, .close): .closed
        case (.interactive, .toggleLock): .locked
        case (.locked, .toggleLock), (.locked, .unlockAll): .interactive
        case (.interactive, .unlockAll): .interactive
        }
    }

    /// `NSWindow.ignoresMouseEvents`.
    var ignoresMouseEvents: Bool { self == .locked }
    /// The subtle border that tells a locked pin apart.
    var showsLockBorder: Bool { self == .locked }
    /// Locked pins never become key, so keyboard shortcuts only reach interactive ones.
    var acceptsKeyboard: Bool { self == .interactive }
}
