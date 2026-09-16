import XCTest
@testable import Fundus

/// The box dragged by hand.
///
/// Three things sit inside the arithmetic, and each would be its own small annoyance:
/// the corners can arrive in any order, they can lie beside the image, and a line is
/// not a box. None of it crashes — it simply delivers a cut-out in the wrong place, and
/// you take the detection to be poor.
final class DrawnBoxTests: XCTestCase {

    /// The image does not fill the window: a margin stays at the top and bottom.
    /// Exactly the case in which arithmetic without an offset is evenly wrong.
    private let picture = CGRect(x: 0, y: 100, width: 400, height: 200)

    func testACornerDragBecomesANormalisedBox() throws {
        let box = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: 100, y: 150), to: CGPoint(x: 300, y: 250), picture: picture))
        XCTAssertEqual(box.minX, 0.25, accuracy: 0.001)
        XCTAssertEqual(box.minY, 0.25, accuracy: 0.001)
        XCTAssertEqual(box.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(box.height, 0.5, accuracy: 0.001)
    }

    /// Dragging from bottom right to top left means the same box.
    func testTheDirectionOfTheDragDoesNotMatter() throws {
        let forward = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: 100, y: 150), to: CGPoint(x: 300, y: 250), picture: picture))
        let backward = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: 300, y: 250), to: CGPoint(x: 100, y: 150), picture: picture))
        XCTAssertEqual(forward, backward)
    }

    /// Dragged past the edge means "up to the edge", not "nothing".
    func testDraggingPastTheEdgeIsClipped() throws {
        let box = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: -500, y: -500), to: CGPoint(x: 900, y: 900), picture: picture))
        XCTAssertEqual(box, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// A line is not a box, and a swipe while scrolling should not produce a selection.
    func testAThinStripeIsNoBox() {
        XCTAssertNil(ObjectPicker.box(from: CGPoint(x: 100, y: 150),
                                      to: CGPoint(x: 300, y: 152), picture: picture))
        XCTAssertNil(ObjectPicker.box(from: CGPoint(x: 100, y: 150),
                                      to: CGPoint(x: 102, y: 250), picture: picture))
    }

    // MARK: What becomes of the box

    /// The dragged box is the box — not a suggestion for a model.
    ///
    /// It replaces whatever was already picked at its spot. Without that, two cut-outs
    /// would lie on top of each other: two paid shots for one thing, and half of it
    /// missing on one of them because the mask did not quite hit the thing.
    func testADrawnBoxReplacesTheFindUnderneathIt() {
        let here = object(CGRect(x: 0.30, y: 0.30, width: 0.20, height: 0.20))
        let overThere = object(CGRect(x: 0.80, y: 0.80, width: 0.10, height: 0.10))

        let after = ObjectPicker.replacing([here, overThere],
                                           by: CGRect(x: 0.25, y: 0.25,
                                                      width: 0.40, height: 0.40))

        XCTAssertEqual(after.count, 2, "Der Fund darunter geht, der am Rand bleibt.")
        XCTAssertEqual(after.first?.id, overThere.id)
        XCTAssertNil(after.first(where: { $0.id == here.id }))
    }

    /// A box drawn around several finds turns them into **one** cut-out.
    ///
    /// Exactly the case this is about: the model found three things separately, but
    /// what is meant is the one thing they form together.
    func testABoxAroundSeveralFindsLeavesOnlyTheBox() {
        let bits = [object(CGRect(x: 0.20, y: 0.20, width: 0.10, height: 0.10)),
                    object(CGRect(x: 0.35, y: 0.25, width: 0.12, height: 0.14)),
                    object(CGRect(x: 0.50, y: 0.30, width: 0.08, height: 0.09))]

        let after = ObjectPicker.replacing(bits, by: CGRect(x: 0.15, y: 0.15,
                                                            width: 0.50, height: 0.40))

        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].box, CGRect(x: 0.15, y: 0.15, width: 0.50, height: 0.40))
        XCTAssertTrue(after[0].bits.isEmpty,
                      "Ohne Umriss wird geschnitten und nicht freigestellt — sonst "
                      + "waere alles ausser einem Ding weiss.")
    }

    // MARK: Zu klein

    /// Below `ObjectFinder.minimumEdge` no cut-out comes about any more. Without this
    /// check a tiny box would vanish silently and the whole board would go into the
    /// queue in its place — dragged, read "1 cut-out", got the shelf.
    func testATinyBoxIsRefusedBeforeItCanVanish() {
        let photo = CGSize(width: 1_400, height: 1_050)
        XCTAssertTrue(ObjectPicker.isUsable(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                                            pixels: photo))
        // 3 per cent of 1050 is 32 pixels — tall enough for the box itself and too
        // little for a cut-out.
        XCTAssertFalse(ObjectPicker.isUsable(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.03),
                                             pixels: photo))
    }

    private func object(_ box: CGRect) -> SegmentedObject {
        SegmentedObject(id: UUID(), box: box, mask: nil, bits: [], side: 0)
    }

    func testAZeroSizedPictureYieldsNothing() {
        XCTAssertNil(ObjectPicker.box(from: .zero, to: CGPoint(x: 10, y: 10), picture: .zero))
    }

    /// The offset of the fitted image has to go in too: a drag at the top edge of the
    /// image is 0 and not 0.33.
    func testTheLetterboxOffsetIsTakenOut() throws {
        let box = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 200), picture: picture))
        XCTAssertEqual(box.minY, 0, accuracy: 0.001, "Oben im Bild ist 0.")
        XCTAssertEqual(box.height, 0.5, accuracy: 0.001)
    }
}
