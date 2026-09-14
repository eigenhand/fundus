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
