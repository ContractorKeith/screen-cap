import AppKit
import ScreenCapKit

// Mouse and keyboard handling. Views forward events here in global AppKit points.
extension SelectionOverlay {
    private enum KeyCode {
        static let escape: UInt16 = 53
        static let space: UInt16 = 49
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
    }

    func mouseMoved(to point: CGPoint) {
        state.mouse = point
        switch state.mode {
        case .window:
            state.hoveredWindow = picker.window(at: point)
        case .area:
            if let size = state.fixedSize, let display = geometry.display(containing: point) {
                state.rect = SelectionMath.fixedRect(size: size, centeredAt: point, within: display.frame)
            }
        }
        requestLiveSample()
        redraw()
    }

    func mouseDown(at point: CGPoint) {
        removeSizeField()
        state.mouse = point
        switch state.mode {
        case .window:
            if let window = state.hoveredWindow ?? picker.window(at: point) { finish(.window(window)) }
        case .area:
            if state.fixedSize != nil, let rect = state.rect {
                confirm(rect)
                return
            }
            hideToolbar()
            state.dragStart = point
            state.rect = nil
            state.lockedAspect = nil
            redraw()
        }
    }

    func mouseDragged(to point: CGPoint, shift: Bool) {
        state.mouse = point
        requestLiveSample()
        guard state.dragStart != nil else { return }
        updateDrag(shift: shift)
    }

    func mouseUp(at point: CGPoint) {
        guard state.dragStart != nil else { return }
        state.dragStart = nil
        state.lockedAspect = nil
        guard SelectionMath.isSelection(state.rect), let rect = state.rect else {
            state.rect = nil
            redraw()
            return
        }
        confirm(rect)
    }

    /// ⇧ pressed or released mid-drag: lock to the current ratio, or unlock.
    func modifiersChanged(shift: Bool) {
        if state.isDragging { updateDrag(shift: shift) }
    }

    private func updateDrag(shift: Bool) {
        guard let start = state.dragStart else { return }
        if shift, state.lockedAspect == nil {
            state.lockedAspect = SelectionMath.lockedAspect(current: state.rect, fallback: state.lastSelection)
        } else if !shift {
            state.lockedAspect = nil
        }
        state.rect = SelectionMath.rect(from: start, to: state.mouse, aspect: state.lockedAspect,
                                        within: geometry.unionFrame)
        redraw()
    }

    /// Returns true if the key was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case KeyCode.escape: escape()
        case KeyCode.space: toggleMode()
        case KeyCode.returnKey, KeyCode.enter: confirmCurrent()
        default:
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "k" else { return false }
            showSizeField()
        }
        return true
    }

    private func escape() {
        if state.toolbarVisible {
            hideToolbar()
            state.rect = nil
        } else if state.fixedSize != nil {
            state.fixedSize = nil
            state.rect = nil
        } else {
            finish(.cancelled)
            return
        }
        redraw()
    }

    private func toggleMode() {
        hideToolbar()
        removeSizeField()
        state.dragStart = nil
        state.fixedSize = nil
        state.rect = nil
        state.mode = state.mode == .area ? .window : .area
        state.hoveredWindow = state.mode == .window ? picker.window(at: state.mouse) : nil
        redraw()
    }

    /// Return: capture the hovered window, the current rect, or the previous area.
    private func confirmCurrent() {
        if state.mode == .window {
            if let window = state.hoveredWindow { finish(.window(window)) }
            return
        }
        guard let rect = state.rect ?? state.previousRect, SelectionMath.isSelection(rect) else { return }
        if state.toolbarVisible {
            finish(.area(rect))
        } else {
            confirm(rect)
        }
    }

    /// A finished selection: All-In-One shows its toolbar; everything else captures it.
    private func confirm(_ rect: CGRect) {
        state.rect = rect
        state.lastSelection = rect
        state.fixedSize = nil
        if options.allInOne {
            showToolbar(for: rect)
        } else {
            finish(.area(rect))
        }
    }

    // MARK: - All-In-One toolbar

    private func showToolbar(for rect: CGRect) {
        hideToolbar()
        guard let view = view(for: rect) else { return }
        let bar = AllInOneToolbar { [weak self] choice in self?.choose(choice) }
        let local = view.localRect(rect)
        let size = bar.fittingSize
        var origin = CGPoint(x: local.midX - size.width / 2, y: local.minY - size.height - 10)
        if origin.y < 8 { origin.y = local.minY + 10 }
        origin.x = max(8, min(origin.x, view.bounds.maxX - size.width - 8))
        bar.frame = CGRect(origin: origin, size: size)
        view.addSubview(bar)
        toolbar = bar
        state.toolbarVisible = true
        redraw()
    }

    func hideToolbar() {
        toolbar?.removeFromSuperview()
        toolbar = nil
        state.toolbarVisible = false
    }

    private func choose(_ choice: AllInOneChoice) {
        guard let rect = state.rect else { return }
        switch choice {
        case .area:
            finish(.area(rect))
        case .window:
            toggleMode()
        case .fullscreen, .scrolling, .text, .timer:
            finish(.allInOne(choice, rect))
        }
    }

    // MARK: - Fixed size (⌘K)

    private func showSizeField() {
        removeSizeField()
        hideToolbar()
        state.mode = .area
        guard let view = view(for: nil) else { return }
        let field = FixedSizeField(
            initial: state.fixedSize ?? state.rect?.size ?? state.previousRect?.size,
            onCommit: { [weak self] size in self?.applyFixedSize(size) },
            onCancel: { [weak self] in self?.removeSizeField() }
        )
        let local = view.localPoint(state.mouse)
        let size = field.fittingSize
        let origin = CGPoint(
            x: max(8, min(local.x + 16, view.bounds.maxX - size.width - 8)),
            y: max(8, min(local.y - size.height - 16, view.bounds.maxY - size.height - 8))
        )
        field.frame = CGRect(origin: origin, size: size)
        view.addSubview(field)
        sizeField = field
        focusPanel(at: state.mouse)
        view.window?.makeFirstResponder(field.textField)
    }

    func removeSizeField() {
        guard let field = sizeField else { return }
        field.removeFromSuperview()
        sizeField = nil
        focusPanel(at: state.mouse)
    }

    private func applyFixedSize(_ size: CGSize) {
        removeSizeField()
        state.fixedSize = size
        mouseMoved(to: state.mouse)
    }
}
