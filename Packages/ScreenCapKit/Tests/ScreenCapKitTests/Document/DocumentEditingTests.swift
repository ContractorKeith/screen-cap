import CoreGraphics
import Foundation
@testable import ScreenCapKit
import Testing

@Suite("Document editing")
struct DocumentEditingTests {
    private var document = Document(baseImage: DocumentFixtures.base)

    @Test func removingCounterRenumbersInCreationOrder() {
        var doc = document
        let ids = (1...4).map { doc.add(DocumentFixtures.counter($0, x: Double($0))) }
        doc.add(Annotation(kind: .ellipse(rect: CGRect(x: 0, y: 0, width: 5, height: 5))))
        // z-order changes must not affect numbering.
        doc.sendToBack(ids[3])
        doc.remove(ids[1])
        #expect(DocumentFixtures.counterNumbers(doc) == [1, 2, 3])
        #expect(doc.annotations.count == 4)
        doc.remove([ids[0], ids[3]])
        #expect(DocumentFixtures.counterNumbers(doc) == [1])
        #expect(doc.nextCounterNumber == 2)
    }

    @Test func addPlacesOnTop() {
        var doc = document
        let first = doc.add(DocumentFixtures.counter(1))
        let second = doc.add(DocumentFixtures.counter(2))
        #expect(doc.drawOrder.map(\.id) == [first, second])
    }

    @Test func zOrdering() {
        var doc = document
        let ids = (1...3).map { doc.add(DocumentFixtures.counter($0)) }
        doc.bringForward(ids[0])
        #expect(doc.drawOrder.map(\.id) == [ids[1], ids[0], ids[2]])
        doc.sendBackward(ids[2])
        #expect(doc.drawOrder.map(\.id) == [ids[1], ids[2], ids[0]])
        doc.bringToFront(ids[1])
        #expect(doc.drawOrder.map(\.id) == [ids[2], ids[0], ids[1]])
        doc.sendToBack(ids[1])
        #expect(doc.drawOrder.map(\.id) == [ids[1], ids[2], ids[0]])
        doc.sendToBack(ids[1])
        #expect(doc.drawOrder.map(\.id) == [ids[1], ids[2], ids[0]])
        // Creation order is untouched.
        #expect(doc.annotations.map(\.id) == ids)
    }

    @Test func moveTranslatesEveryKind() {
        for kind in DocumentFixtures.everyKind {
            var doc = document
            let id = doc.add(Annotation(kind: kind))
            let before = kind.bounds
            doc.move(id, by: CGSize(width: 7, height: -3))
            #expect(doc.annotations[0].kind.bounds == before.offsetBy(dx: 7, dy: -3))
        }
    }

    @Test func resizeFitsNewBounds() {
        for kind in DocumentFixtures.everyKind {
            var doc = document
            let id = doc.add(Annotation(kind: kind))
            let target = CGRect(x: 100, y: 200, width: 60, height: 60)
            doc.resize(id, to: target)
            let bounds = doc.annotations[0].kind.bounds
            #expect(abs(bounds.minX - target.minX) < 0.001)
            #expect(abs(bounds.minY - target.minY) < 0.001)
        }
    }

    @Test func resizeScalesArrow() {
        var doc = document
        let id = doc.add(Annotation(kind: .arrow(start: .zero, end: CGPoint(x: 10, y: 10), style: .straight)))
        doc.resize(id, to: CGRect(x: 0, y: 0, width: 20, height: 40))
        #expect(doc.annotations[0].kind == .arrow(start: .zero, end: CGPoint(x: 20, y: 40), style: .straight))
    }

    @Test func duplicateCopiesWithNewIDOnTop() throws {
        var doc = document
        let original = doc.add(Annotation(kind: .ellipse(rect: CGRect(x: 0, y: 0, width: 10, height: 10))))
        doc.add(DocumentFixtures.counter(1))
        let duplicated = doc.duplicate(original, offset: CGSize(width: 5, height: 5))
        let copy = try #require(duplicated)
        #expect(copy != original)
        #expect(doc.drawOrder.last?.id == copy)
        #expect(doc.annotation(withID: copy)?.kind == .ellipse(rect: CGRect(x: 5, y: 5, width: 10, height: 10)))
    }

    @Test func duplicateCounterTakesNextNumber() {
        var doc = document
        let first = doc.add(DocumentFixtures.counter(1))
        doc.add(DocumentFixtures.counter(2))
        let duplicated = doc.duplicate(first)
        #expect(duplicated != nil)
        #expect(DocumentFixtures.counterNumbers(doc) == [1, 2, 3])
    }

    @Test func unknownIDsAreIgnored() {
        var doc = document
        doc.add(DocumentFixtures.counter(1))
        let snapshot = doc
        doc.remove(UUID())
        doc.move(UUID(), by: CGSize(width: 1, height: 1))
        doc.bringForward(UUID())
        let duplicated = doc.duplicate(UUID())
        #expect(duplicated == nil)
        #expect(doc == snapshot)
    }
}

@Suite("Resize by handle")
struct ResizeHandleTests {
    /// The bounds each of the eight box handles produces when dragged 40 px outward.
    static func dragged(_ rect: CGRect) -> [(name: String, target: CGRect)] {
        // Edges moved outward by 40 px: (minX, minY) and (maxX, maxY) deltas per handle.
        let moves: [String: (min: CGPoint, max: CGPoint)] = [
            "topLeft": (CGPoint(x: -40, y: -40), .zero), "top": (CGPoint(x: 0, y: -40), .zero),
            "topRight": (CGPoint(x: 0, y: -40), CGPoint(x: 40, y: 0)), "right": (.zero, CGPoint(x: 40, y: 0)),
            "bottomRight": (.zero, CGPoint(x: 40, y: 40)), "bottom": (.zero, CGPoint(x: 0, y: 40)),
            "bottomLeft": (CGPoint(x: -40, y: 0), CGPoint(x: 0, y: 40)), "left": (CGPoint(x: -40, y: 0), .zero)
        ]
        return moves.map { name, move in
            (name, CGRect(x: rect.minX + move.min.x, y: rect.minY + move.min.y,
                          width: rect.width - move.min.x + move.max.x, height: rect.height - move.min.y + move.max.y))
        }
    }

    @Test func everyHandleResizesACounter() throws {
        let original = Annotation.Kind.counter(number: 1, center: CGPoint(x: 100, y: 100), radius: 18)
        for (name, target) in Self.dragged(original.bounds) {
            var document = Document(baseImage: DocumentFixtures.base)
            let id = document.add(Annotation(kind: original))
            document.resize(id, to: target)
            let result = try #require(document.annotation(withID: id)?.kind)
            guard case let .counter(_, center, radius) = result else { Issue.record("not a counter"); continue }
            // Grows to the full 40 px drag (radius 18 -> 38) and stays centered in the target.
            #expect(abs(radius - 38) < 1e-9, "\(name): radius \(radius)")
            #expect(abs(center.x - target.midX) < 1e-9 && abs(center.y - target.midY) < 1e-9, "\(name): \(center)")
            // The dragged edge follows the pointer.
            let bounds = result.bounds
            if name.contains("right") || name.contains("Right") { #expect(abs(bounds.maxX - target.maxX) < 1e-9) }
            if name.contains("left") || name.contains("Left") { #expect(abs(bounds.minX - target.minX) < 1e-9) }
            if name.hasPrefix("top") { #expect(abs(bounds.minY - target.minY) < 1e-9) }
            if name.hasPrefix("bottom") { #expect(abs(bounds.maxY - target.maxY) < 1e-9) }
        }
    }

    @Test func everyHandleResizesARectangleExactly() throws {
        let original = Annotation.Kind.rectangle(rect: CGRect(x: 50, y: 60, width: 80, height: 40), filled: false,
                                                 cornerRadius: 0)
        for (name, target) in Self.dragged(original.bounds) {
            var document = Document(baseImage: DocumentFixtures.base)
            let id = document.add(Annotation(kind: original))
            document.resize(id, to: target)
            #expect(document.annotation(withID: id)?.kind.bounds == target, "\(name)")
        }
    }

    @Test func unevenCornerDragUsesTheSmallerScale() throws {
        var document = Document(baseImage: DocumentFixtures.base)
        let id = document.add(Annotation(kind: .counter(number: 1, center: CGPoint(x: 100, y: 100), radius: 18)))
        document.resize(id, to: CGRect(x: 82, y: 82, width: 72, height: 54))
        guard case let .counter(_, _, radius)? = document.annotation(withID: id)?.kind else {
            Issue.record("not a counter")
            return
        }
        #expect(radius == 27)
    }
}
