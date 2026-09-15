import XCTest
@testable import Fundus

/// Der von Hand gezogene Kasten.
///
/// Drei Dinge stecken in der Rechnung, und jedes waere ein eigener kleiner Aerger:
/// die Ecken koennen in beliebiger Reihenfolge kommen, sie koennen neben dem Bild
/// liegen, und ein Strich ist kein Kasten. Nichts davon stuerzt ab — es liefert nur
/// einen Ausschnitt an der falschen Stelle, und man haelt die Erkennung fuer schlecht.
final class DrawnBoxTests: XCTestCase {

    /// Das Bild fuellt das Fenster nicht aus: oben und unten bleibt Rand. Genau der
    /// Fall, in dem eine Rechnung ohne Versatz gleichmaessig danebenliegt.
    private let picture = CGRect(x: 0, y: 100, width: 400, height: 200)

    func testACornerDragBecomesANormalisedBox() throws {
        let box = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: 100, y: 150), to: CGPoint(x: 300, y: 250), picture: picture))
        XCTAssertEqual(box.minX, 0.25, accuracy: 0.001)
        XCTAssertEqual(box.minY, 0.25, accuracy: 0.001)
        XCTAssertEqual(box.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(box.height, 0.5, accuracy: 0.001)
    }

    /// Wer von rechts unten nach links oben zieht, meint denselben Kasten.
    func testTheDirectionOfTheDragDoesNotMatter() throws {
        let forward = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: 100, y: 150), to: CGPoint(x: 300, y: 250), picture: picture))
        let backward = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: 300, y: 250), to: CGPoint(x: 100, y: 150), picture: picture))
        XCTAssertEqual(forward, backward)
    }

    /// Ueber den Rand hinaus gezogen heisst „bis zum Rand", nicht „nichts".
    func testDraggingPastTheEdgeIsClipped() throws {
        let box = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: -500, y: -500), to: CGPoint(x: 900, y: 900), picture: picture))
        XCTAssertEqual(box, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Ein Strich ist kein Kasten, und ein Wisch beim Scrollen soll keine Auswahl
    /// erzeugen.
    func testAThinStripeIsNoBox() {
        XCTAssertNil(ObjectPicker.box(from: CGPoint(x: 100, y: 150),
                                      to: CGPoint(x: 300, y: 152), picture: picture))
        XCTAssertNil(ObjectPicker.box(from: CGPoint(x: 100, y: 150),
                                      to: CGPoint(x: 102, y: 250), picture: picture))
    }

    // MARK: Was aus dem Kasten wird

    /// Der gezogene Kasten ist der Kasten — nicht die Anregung fuer ein Modell.
    ///
    /// Er ersetzt, was an seiner Stelle schon gewaehlt war. Ohne das laegen zwei
    /// Ausschnitte uebereinander: zwei bezahlte Aufnahmen fuer ein Ding, und auf der
    /// einen fehlt die Haelfte, weil die Maske das Ding nicht ganz getroffen hat.
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

    /// Ein Kasten um mehrere Funde herum macht daraus **einen** Ausschnitt.
    ///
    /// Genau der Fall, um den es geht: das Modell hat drei Dinge einzeln gefunden,
    /// gemeint ist aber das eine, das sie zusammen bilden.
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

    /// Unter `ObjectFinder.minimumEdge` entsteht kein Ausschnitt mehr. Ohne diese
    /// Pruefung verschwaende ein winziger Kasten stillschweigend und statt seiner
    /// ginge das ganze Brett in die Reihe — gezogen, „1 Ausschnitt" gelesen, das
    /// Regal bekommen.
    func testATinyBoxIsRefusedBeforeItCanVanish() {
        let photo = CGSize(width: 1_400, height: 1_050)
        XCTAssertTrue(ObjectPicker.isUsable(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                                            pixels: photo))
        // 3 Prozent von 1050 sind 32 Pixel — hoch genug fuer den Kasten selbst und
        // zu wenig fuer einen Ausschnitt.
        XCTAssertFalse(ObjectPicker.isUsable(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.03),
                                             pixels: photo))
    }

    private func object(_ box: CGRect) -> SegmentedObject {
        SegmentedObject(id: UUID(), box: box, mask: nil, bits: [], side: 0)
    }

    func testAZeroSizedPictureYieldsNothing() {
        XCTAssertNil(ObjectPicker.box(from: .zero, to: CGPoint(x: 10, y: 10), picture: .zero))
    }

    /// Der Versatz des eingepassten Bildes muss mit hinein: ein Zug am oberen Rand des
    /// Bildes ist 0 und nicht 0,33.
    func testTheLetterboxOffsetIsTakenOut() throws {
        let box = try XCTUnwrap(ObjectPicker.box(
            from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 200), picture: picture))
        XCTAssertEqual(box.minY, 0, accuracy: 0.001, "Oben im Bild ist 0.")
        XCTAssertEqual(box.height, 0.5, accuracy: 0.001)
    }
}
