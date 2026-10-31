import AppKit
import ScreenCapKit

// Pointer handling: create with drawing tools, select/move/resize with the select tool, crop.

extension CanvasView {
    override func mouseDown(with event: NSEvent) {
        commitTextEditing()
        window?.makeFirstResponder(self)
        let point = imagePoint(event)
        let shift = event.modifierFlags.contains(.shift)

        if model.tool == .crop {
            beginCropDrag(at: point)
        } else if event.clickCount == 2, let id = EditorGeometry.topmost(in: model.document, at: point,
                                                                          tolerance: tolerance),
                  case .text = model.document.annotation(withID: id)?.kind {
            model.selection = [id]
            beginTextEditing(id)
        } else if let resize = handleUnderPointer(point) {
            drag = .resizing(id: resize.annotation.id, handle: resize.handle, original: resize.annotation.kind,
                             group: Self.newGroup())
        } else if model.tool == .select {
            beginSelectDrag(at: point, shift: shift)
        } else if model.tool.isFreehand {
            drag = .freehand(points: [point], id: nil, group: Self.newGroup())
        } else {
            drag = .creating(start: point, id: nil, group: Self.newGroup())
        }
        model.touch()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = imagePoint(event)
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .creating:
            updateCreation(to: point, shift: shift)
        case let .freehand(points, id, group):
            updateFreehand(points + [point], id: id, group: group)
        case let .moving(start, applied, group):
            var offset = CGSize(width: point.x - start.x, height: point.y - start.y)
            if shift { abs(offset.width) > abs(offset.height) ? (offset.height = 0) : (offset.width = 0) }
            model.moveSelection(by: CGSize(width: offset.width - applied.width, height: offset.height - applied.height),
                                groupKey: group)
            drag = .moving(start: start, applied: offset, group: group)
        case .resizing:
            updateResize(to: point, shift: shift)
        case let .rubberBand(start, _, base):
            drag = .rubberBand(start: start, current: point, base: base)
            let hits = EditorGeometry.annotations(in: model.document, intersecting: EditorGeometry.rect(from: start,
                                                                                                         to: point))
            model.selection = base.union(hits)
            model.touch()
        case .cropping, .cropResizing, .cropMoving:
            updateCropDrag(to: point, shift: shift)
        case .idle:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = imagePoint(event)
        switch drag {
        case let .creating(start, id, _) where id == nil && model.tool.acceptsClick:
            let kind = ToolDrag.kind(for: model.tool, from: start, to: point, constrain: false,
                                     options: model.options, nextCounter: model.document.nextCounterNumber)
            if let kind { finishCreation(model.add(kind)) }
        case let .creating(_, id?, _):
            finishCreation(id)
        default:
            break
        }
        drag = .idle
        model.endGrouping()
        model.touch()
    }

    override func magnify(with event: NSEvent) {
        commitTextEditing()
        super.magnify(with: event)
        needsDisplay = true
    }

    static func newGroup() -> String { "drag-\(UUID().uuidString)" }

    // MARK: - Select tool

    /// The single selection's handle under the pointer, if any.
    private func handleUnderPointer(_ point: CGPoint) -> (annotation: Annotation, handle: Handle)? {
        guard let selected = model.singleSelection,
              let handle = EditorGeometry.handle(at: point, for: selected.kind, tolerance: tolerance * 1.3)
        else { return nil }
        return (selected, handle)
    }

    private func beginSelectDrag(at point: CGPoint, shift: Bool) {
        guard let hit = EditorGeometry.topmost(in: model.document, at: point, tolerance: tolerance) else {
            if !shift { model.selection = [] }
            drag = .rubberBand(start: point, current: point, base: model.selection)
            return
        }
        if shift {
            if model.selection.contains(hit) { model.selection.remove(hit) } else { model.selection.insert(hit) }
        } else if !model.selection.contains(hit) {
            model.selection = [hit]
        }
        drag = .moving(start: point, applied: .zero, group: Self.newGroup())
    }

    private func updateResize(to point: CGPoint, shift: Bool) {
        guard case let .resizing(id, handle, original, group) = drag else { return }
        switch handle {
        case .start, .end, .control:
            guard let current = model.document.annotation(withID: id)?.kind else { return }
            model.setKind(id, EditorGeometry.movingPoint(current, handle: handle, to: point, constrain: shift),
                          groupKey: group)
        default:
            var bounds = EditorGeometry.resized(original.bounds, handle: handle, to: point, constrain: shift)
            bounds.size = CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
            // Resize from the original each time so shrinking to a sliver and back loses nothing.
            var restored = model.document
            if let index = restored.index(of: id) {
                restored.annotations[index].kind = original
                restored.resize(id, to: bounds)
                model.setKind(id, restored.annotations[index].kind, groupKey: group)
            }
        }
    }

    // MARK: - Drawing tools

    private func updateCreation(to point: CGPoint, shift: Bool) {
        guard case let .creating(start, id, group) = drag, model.tool != .counter else { return }
        guard let kind = ToolDrag.kind(for: model.tool, from: start, to: point, constrain: shift,
                                       options: model.options, nextCounter: model.document.nextCounterNumber)
        else { return }
        if let id {
            model.setKind(id, kind, groupKey: group)
        } else {
            drag = .creating(start: start, id: model.add(kind, groupKey: group), group: group)
        }
    }

    private func updateFreehand(_ points: [CGPoint], id: UUID?, group: String) {
        guard let kind = ToolDrag.freehand(model.tool, points: points, options: model.options) else {
            drag = .freehand(points: points, id: id, group: group)
            return
        }
        if let id {
            model.setKind(id, kind, groupKey: group)
            drag = .freehand(points: points, id: id, group: group)
        } else {
            drag = .freehand(points: points, id: model.add(kind, groupKey: group), group: group)
        }
    }

    private func finishCreation(_ id: UUID) {
        if case .text = model.document.annotation(withID: id)?.kind {
            beginTextEditing(id)
        }
    }

    // MARK: - Crop

    private func beginCropDrag(at point: CGPoint) {
        let crop = model.cropRect ?? CGRect(origin: .zero, size: model.snapshot.imageSize)
        let near = Handle.boxHandles.first { EditorGeometry.distance($0.point(on: crop), point) <= tolerance * 1.5 }
        if let near {
            drag = .cropResizing(handle: near, original: crop)
        } else if crop.contains(point), crop.size != model.snapshot.imageSize {
            drag = .cropMoving(start: point, original: crop)
        } else {
            drag = .cropping(start: point)
        }
    }

    private func updateCropDrag(to point: CGPoint, shift: Bool) {
        let bounds = CGRect(origin: .zero, size: model.snapshot.imageSize)
        let ratio = model.cropRatio ?? (shift ? 1 : nil)
        let threshold = CropMath.snapThreshold / magnification
        switch drag {
        case let .cropping(start):
            model.cropRect = CropMath.rect(from: start, to: point, ratio: ratio, bounds: bounds,
                                           edges: model.cropEdges, threshold: threshold)
        case let .cropResizing(handle, original):
            var rect = EditorGeometry.resized(original, handle: handle, to: point, constrain: ratio != nil)
            if ratio == nil { rect = CropMath.snapped(rect, to: model.cropEdges, bounds: bounds, threshold: threshold) }
            model.cropRect = rect.intersection(bounds)
        case let .cropMoving(start, original):
            var rect = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            rect.origin.x = min(max(rect.minX, 0), bounds.width - rect.width)
            rect.origin.y = min(max(rect.minY, 0), bounds.height - rect.height)
            model.cropRect = rect
        default:
            return
        }
        model.touch()
    }
}
