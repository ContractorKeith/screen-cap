import CoreGraphics
import Foundation

// DocumentEditing: the mutations the editor performs on a Document.
// Each is a plain value mutation, so callers wrap them in UndoStack.record.

extension Document {
    public func index(of id: UUID) -> Int? {
        annotations.firstIndex { $0.id == id }
    }

    public func annotation(withID id: UUID) -> Annotation? {
        index(of: id).map { annotations[$0] }
    }

    /// Number the next counter should get: one past the highest existing counter.
    public var nextCounterNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case let .counter(number, _, _) = annotation.kind { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    /// Appends `annotation` on top of everything else and returns its id.
    @discardableResult
    public mutating func add(_ annotation: Annotation) -> UUID {
        var annotation = annotation
        annotation.zIndex = topZIndex + 1
        annotations.append(annotation)
        return annotation.id
    }

    /// Removes the annotations with the given ids, then renumbers the remaining counters
    /// 1...n in creation order so the sequence stays gap-free.
    public mutating func remove(_ ids: Set<UUID>) {
        let before = annotations.count
        annotations.removeAll { ids.contains($0.id) }
        if annotations.count != before { renumberCounters() }
    }

    public mutating func remove(_ id: UUID) {
        remove([id])
    }

    /// Renumbers counters 1...n in creation (array) order.
    public mutating func renumberCounters() {
        var next = 1
        for index in annotations.indices {
            if case let .counter(_, center, radius) = annotations[index].kind {
                annotations[index].kind = .counter(number: next, center: center, radius: radius)
                next += 1
            }
        }
    }

    /// Translates an annotation by `offset` pixels.
    public mutating func move(_ id: UUID, by offset: CGSize) {
        guard let index = index(of: id) else { return }
        annotations[index].kind = annotations[index].kind.mapped {
            CGPoint(x: $0.x + offset.width, y: $0.y + offset.height)
        }
    }

    /// Scales an annotation so its bounds become `newBounds`.
    /// Zero-width or zero-height bounds (a horizontal line) keep that axis's scale at 1.
    public mutating func resize(_ id: UUID, to newBounds: CGRect) {
        guard let index = index(of: id) else { return }
        let old = annotations[index].kind.bounds
        guard !old.isNull else { return }
        let target = newBounds.standardized
        let scaleX = old.width > 0 ? target.width / old.width : 1
        let scaleY = old.height > 0 ? target.height / old.height : 1
        annotations[index].kind = annotations[index].kind.mapped(scale: min(scaleX, scaleY)) {
            CGPoint(x: target.minX + ($0.x - old.minX) * scaleX,
                    y: target.minY + ($0.y - old.minY) * scaleY)
        }
    }

    /// Moves one step up in draw order (swaps with the annotation just above it).
    public mutating func bringForward(_ id: UUID) {
        shiftInDrawOrder(id, by: 1)
    }

    /// Moves one step down in draw order.
    public mutating func sendBackward(_ id: UUID) {
        shiftInDrawOrder(id, by: -1)
    }

    public mutating func bringToFront(_ id: UUID) {
        shiftInDrawOrder(id, by: annotations.count)
    }

    public mutating func sendToBack(_ id: UUID) {
        shiftInDrawOrder(id, by: -annotations.count)
    }

    /// Copies an annotation with a new id, offset by `offset`, placed on top. A duplicated
    /// counter takes the next number. Returns the new id.
    @discardableResult
    public mutating func duplicate(_ id: UUID, offset: CGSize = CGSize(width: 16, height: 16)) -> UUID? {
        guard var copy = annotation(withID: id) else { return nil }
        copy.id = UUID()
        copy.kind = copy.kind.mapped { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        if case let .counter(_, center, radius) = copy.kind {
            copy.kind = .counter(number: nextCounterNumber, center: center, radius: radius)
        }
        return add(copy)
    }

    private var topZIndex: Int {
        annotations.map(\.zIndex).max() ?? -1
    }

    /// Reorders draw order and rewrites zIndex as 0..<n so it stays dense.
    private mutating func shiftInDrawOrder(_ id: UUID, by steps: Int) {
        var order = drawOrder.map(\.id)
        guard let from = order.firstIndex(of: id) else { return }
        let destination = max(0, min(order.count - 1, from + steps))
        order.remove(at: from)
        order.insert(id, at: destination)
        let zByID = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        for index in annotations.indices {
            annotations[index].zIndex = zByID[annotations[index].id] ?? 0
        }
    }
}
