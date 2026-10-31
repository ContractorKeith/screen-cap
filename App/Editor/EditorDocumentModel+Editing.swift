import CoreGraphics
import Foundation
import ImageIO
import ScreenCapKit

// Object edits: create, move, resize, delete, duplicate, z-order, style, copy/paste.

extension EditorDocumentModel {
    /// Adds an object with the current tool style on top, selects it and returns its id.
    @discardableResult
    func add(_ kind: Annotation.Kind, groupKey: String? = nil) -> UUID {
        var style = options.style
        if case .highlight = kind { style.strokeWidth = max(options.style.strokeWidth * 4, 16) }
        var newID = UUID()
        edit(groupKey: groupKey) { newID = $0.add(Annotation(style: style, kind: kind)) }
        selection = [newID]
        return newID
    }

    /// Replaces an object's geometry (live drags pass a group key so the drag is one undo step).
    func setKind(_ id: UUID, _ kind: Annotation.Kind, groupKey: String? = nil) {
        guard let index = document.index(of: id), document.annotations[index].kind != kind else { return }
        edit(groupKey: groupKey) { $0.annotations[index].kind = kind }
    }

    func moveSelection(by offset: CGSize, groupKey: String? = nil) {
        guard !selection.isEmpty, offset != .zero else { return }
        let ids = selection
        edit(groupKey: groupKey) { document in
            for id in ids { document.move(id, by: offset) }
        }
    }

    func resize(_ id: UUID, to bounds: CGRect, groupKey: String? = nil) {
        edit(groupKey: groupKey) { $0.resize(id, to: bounds) }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        edit { $0.remove(ids) }
        selection = []
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        let ids = document.drawOrder.map(\.id).filter(selection.contains)
        var copies: Set<UUID> = []
        edit { document in
            for id in ids { if let copy = document.duplicate(id) { copies.insert(copy) } }
        }
        selection = copies
    }

    func selectAll() {
        selection = Set(document.annotations.map(\.id))
        touch()
    }

    enum Arrange { case forward, backward, front, back }

    /// Z-order for the selection. Forward/front visit the topmost first so neighbors keep their order.
    func arrange(_ arrange: Arrange) {
        guard !selection.isEmpty else { return }
        var ids = document.drawOrder.map(\.id).filter(selection.contains)
        if arrange == .forward || arrange == .front { ids.reverse() }
        edit { document in
            for id in ids {
                switch arrange {
                case .forward: document.bringForward(id)
                case .backward: document.sendBackward(id)
                case .front: document.bringToFront(id)
                case .back: document.sendToBack(id)
                }
            }
        }
    }

    // MARK: - Style

    /// Changes the style for new objects and for every selected object.
    func updateStyle(groupKey: String? = nil, _ change: (inout Annotation.Style) -> Void) {
        change(&options.style)
        updateSelected(groupKey: groupKey) { change(&$0.style) }
    }

    /// Applies `change` to every selected annotation in one undo step.
    func updateSelected(groupKey: String? = nil, _ change: (inout Annotation) -> Void) {
        let ids = selection
        guard !ids.isEmpty else { touch(); return }
        edit(groupKey: groupKey) { document in
            for index in document.annotations.indices where ids.contains(document.annotations[index].id) {
                change(&document.annotations[index])
            }
        }
    }

    /// Rewrites the selected objects' geometry options (corner radius, font size...); `transform`
    /// returns nil for kinds it doesn't apply to. Callers update `options` for new objects themselves.
    func updateSelectedKinds(groupKey: String? = nil, _ transform: (Annotation.Kind) -> Annotation.Kind?) {
        updateSelected(groupKey: groupKey) { annotation in
            if let kind = transform(annotation.kind) { annotation.kind = kind }
        }
    }

    func setText(_ id: UUID, string: String) {
        guard let index = document.index(of: id),
              case let .text(old, preset, fontSize, rect) = document.annotations[index].kind, old != string
        else { return }
        edit { $0.annotations[index].kind = .text(string: string, preset: preset, fontSize: fontSize, rect: rect) }
    }

    // MARK: - Copy and paste

    /// The selection as a pasteboard payload: annotations in draw order plus their image layers.
    func clipboardPayload() -> AnnotationClipboard? {
        let items = document.drawOrder.filter { selection.contains($0.id) }
        guard !items.isEmpty else { return nil }
        var layers: [String: Data] = [:]
        for case let .imageLayer(name, _) in items.map(\.kind) {
            if let image = snapshot.layers[name], let png = try? Exporter(image: image, format: .png).data() {
                layers[name] = png
            }
        }
        return AnnotationClipboard(annotations: items, layers: layers)
    }

    /// Pastes on top with new ids, offset when the originals are still here, and selects the result.
    func paste(_ payload: AnnotationClipboard) {
        let existing = Set(document.annotations.map(\.id))
        let shift = payload.annotations.contains { existing.contains($0.id) } ? 16.0 : 0
        let images = payload.decodedLayers()
        var pasted: Set<UUID> = []
        perform { snapshot in
            for (name, image) in images where snapshot.layers[name] == nil { snapshot.layers[name] = image }
            for var annotation in payload.annotations {
                if case let .imageLayer(name, _) = annotation.kind, snapshot.layers[name] == nil { continue }
                annotation.id = UUID()
                annotation.kind = annotation.kind.mapped { CGPoint(x: $0.x + shift, y: $0.y + shift) }
                if case let .counter(_, center, radius) = annotation.kind {
                    annotation.kind = .counter(number: snapshot.document.nextCounterNumber, center: center,
                                               radius: radius)
                }
                pasted.insert(snapshot.document.add(annotation))
            }
        }
        selection = pasted
    }

    /// Adds `image` as an image layer centered on `center`, scaled to fit within 60% of the base image.
    @discardableResult
    func addImageLayer(_ image: CGImage, center: CGPoint? = nil) -> UUID {
        let base = snapshot.imageSize
        let fit = min(1, base.width * 0.6 / Double(image.width), base.height * 0.6 / Double(image.height))
        let size = CGSize(width: Double(image.width) * fit, height: Double(image.height) * fit)
        let middle = center ?? CGPoint(x: base.width / 2, y: base.height / 2)
        let rect = CGRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2,
                          width: size.width, height: size.height)
        let name = "layer-\(UUID().uuidString.prefix(8).lowercased())"
        var newID = UUID()
        perform { snapshot in
            snapshot.layers[name] = image
            newID = snapshot.document.add(Annotation(kind: .imageLayer(layerName: name, rect: rect)))
        }
        selection = [newID]
        return newID
    }
}

/// Copied annotations, on the pasteboard as JSON under a private type.
struct AnnotationClipboard: Codable, Sendable {
    static let pasteboardType = "com.contractorkeith.screencap.annotations"

    var annotations: [Annotation]
    /// PNG data for copied image layers, by layer name.
    var layers: [String: Data]

    func decodedLayers() -> [String: CGImage] {
        layers.compactMapValues { data in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }
}
