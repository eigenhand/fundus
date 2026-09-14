import CoreML
import XCTest
@testable import Fundus

/// Was aus zweihundert Anfragen Treffer macht — und wie das Bild hineingeht.
///
/// Beides ohne Modell prüfbar, und beides ist genau die Sorte Rechnung, bei der ein
/// Fehler nicht auffällt: ein vertauschtes Vorzeichen in der Normierung, eine
/// gespiegelte Zeile, ein Kasten von der Mitte statt von der Ecke. Nichts davon
/// stürzt ab. Es liefert nur schlechtere Treffer, und man haelt das Modell fuer
/// schlecht.
final class Sam3FinderTests: XCTestCase {

    // MARK: Das Bild hinein

    private func halves(top: UIColor, bottom: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200),
                                       format: format).image { ctx in
            top.setFill();    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
            bottom.setFill(); ctx.fill(CGRect(x: 0, y: 100, width: 200, height: 100))
        }
    }

    /// `(x/255 − 0,5) / 0,5` bildet auf −1 … 1 ab. Weiss ist 1, Schwarz ist −1.
    func testNormalisationMapsToMinusOneToOne() throws {
        let white = try XCTUnwrap(Sam3Finder.pixels(from: halves(top: .white, bottom: .white)))
        let side = Sam3Finder.side
        XCTAssertEqual(white.shape.map(\.intValue), [1, 3, side, side])

        white.withUnsafeBufferPointer(ofType: Float16.self) { buffer in
            XCTAssertEqual(Float(buffer[0]), 1, accuracy: 0.02)
            XCTAssertEqual(Float(buffer[side * side * 3 - 1]), 1, accuracy: 0.02)
        }

        let black = try XCTUnwrap(Sam3Finder.pixels(from: halves(top: .black, bottom: .black)))
        black.withUnsafeBufferPointer(ofType: Float16.self) { buffer in
            XCTAssertEqual(Float(buffer[0]), -1, accuracy: 0.02)
        }
    }

    /// Die Zeile, an der eine Spiegelung unbemerkt bliebe. Oben weiss, unten schwarz —
    /// und genau so muss es im Puffer stehen, sonst sucht das Modell im gespiegelten
    /// Bild und jeder Kasten liegt falsch herum.
    func testTheTopOfThePictureIsTheTopOfTheBuffer() throws {
        let array = try XCTUnwrap(Sam3Finder.pixels(from: halves(top: .white, bottom: .black)))
        let side = Sam3Finder.side
        array.withUnsafeBufferPointer(ofType: Float16.self) { buffer in
            let nearTop = Float(buffer[(side / 10) * side + side / 2])
            let nearBottom = Float(buffer[(side * 9 / 10) * side + side / 2])
            XCTAssertGreaterThan(nearTop, 0.5, "Oben ist weiss.")
            XCTAssertLessThan(nearBottom, -0.5, "Unten ist schwarz.")
        }
    }

    // MARK: Die Kaesten

    /// `[Mitte-x, Mitte-y, Breite, Hoehe]` in ein Rechteck von oben links.
    func testCentreFormatBecomesACorneredRectangle() {
        let r = Sam3Finder.rect(cx: 0.5, cy: 0.5, w: 0.4, h: 0.2)
        XCTAssertEqual(r.minX, 0.3, accuracy: 0.001)
        XCTAssertEqual(r.minY, 0.4, accuracy: 0.001)
        XCTAssertEqual(r.width, 0.4, accuracy: 0.001)
        XCTAssertEqual(r.height, 0.2, accuracy: 0.001)
    }

    func testBoxesAreClippedToThePicture() {
        let r = Sam3Finder.rect(cx: 0.1, cy: 0.9, w: 0.6, h: 0.6)
        XCTAssertGreaterThanOrEqual(r.minX, 0)
        XCTAssertLessThanOrEqual(r.maxY, 1)
    }

    func testOverlapIsTheSharedShareOfBoth() {
        let a = CGRect(x: 0, y: 0, width: 0.4, height: 0.4)
        XCTAssertEqual(Sam3Finder.overlap(a, a), 1, accuracy: 0.001)
        XCTAssertEqual(Sam3Finder.overlap(a, CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2)), 0,
                       accuracy: 0.001)
        // Haelfte geteilt: 0,08 gemeinsam von 0,24 zusammen.
        let b = CGRect(x: 0.2, y: 0, width: 0.4, height: 0.4)
        XCTAssertEqual(Sam3Finder.overlap(a, b), 0.08 / 0.24, accuracy: 0.01)
    }

    // MARK: Zweihundert Anfragen aussortieren

    private func detection(_ entries: [(score: Double, box: CGRect)])
        throws -> (MLMultiArray, MLMultiArray) {
        let n = Sam3Finder.queries
        let boxes = try MLMultiArray(shape: [1, NSNumber(value: n), 4], dataType: .float32)
        let scores = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .float32)
        for i in 0 ..< n { scores[i] = 0 }
        for i in 0 ..< n * 4 { boxes[i] = 0 }
        for (i, e) in entries.enumerated() {
            scores[i] = NSNumber(value: e.score)
            boxes[i * 4 + 0] = NSNumber(value: Double(e.box.midX))
            boxes[i * 4 + 1] = NSNumber(value: Double(e.box.midY))
            boxes[i * 4 + 2] = NSNumber(value: Double(e.box.width))
            boxes[i * 4 + 3] = NSNumber(value: Double(e.box.height))
        }
        return (boxes, scores)
    }

    func testOnlyConfidentDetectionsSurvive() throws {
        let (boxes, scores) = try detection([
            (0.9, CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)),
            (0.49, CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2)),
            (0.6, CGRect(x: 0.6, y: 0.1, width: 0.2, height: 0.2)),
        ])
        let hits = Sam3Finder.results(boxes: boxes, scores: scores, masks: nil)
        XCTAssertEqual(hits.count, 2, "0,49 liegt unter der Schwelle 0,5.")
        XCTAssertEqual(hits[0].score, 0.9, accuracy: 0.001, "Der sicherste zuerst.")
        XCTAssertEqual(hits[1].score, 0.6, accuracy: 0.001)
    }

    /// Zweihundert Anfragen finden dasselbe Ding mehrfach. Uebrig bleibt der beste.
    func testTheSameObjectIsReportedOnce() throws {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)
        let (boxes, scores) = try detection([
            (0.7, box),
            (0.95, box.insetBy(dx: 0.01, dy: 0.01)),
            (0.8, box.offsetBy(dx: 0.01, dy: 0)),
            (0.6, CGRect(x: 0.05, y: 0.8, width: 0.1, height: 0.1)),
        ])
        let hits = Sam3Finder.results(boxes: boxes, scores: scores, masks: nil)
        XCTAssertEqual(hits.count, 2, "Drei Anfragen auf demselben Ding sind ein Treffer.")
        XCTAssertEqual(try XCTUnwrap(hits.first).score, 0.95, accuracy: 0.001)
    }

    func testNothingFoundIsAnEmptyList() throws {
        let (boxes, scores) = try detection([(0.2, CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))])
        XCTAssertTrue(Sam3Finder.results(boxes: boxes, scores: scores, masks: nil).isEmpty)
    }

    /// Ein Kasten von vier Promille Kantenlaenge ist Rauschen, kein Gegenstand.
    func testSpecksAreDropped() throws {
        let (boxes, scores) = try detection([
            (0.99, CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001)),
        ])
        XCTAssertTrue(Sam3Finder.results(boxes: boxes, scores: scores, masks: nil).isEmpty)
    }
}
