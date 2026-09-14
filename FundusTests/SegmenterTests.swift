import CoreML
import XCTest
@testable import Fundus

/// Segment Anything, an einem Bild, dessen Antwort man kennt.
///
/// Die Prüfung ist mit Absicht kein Foto aus dem Keller: bei einem echten Regal
/// wüsste niemand, ob eine Maske „richtig" ist, und ein Test, der nur prüft, dass
/// *irgendetwas* zurückkommt, prüft nichts. Hier steht ein dunkles Rechteck an einer
/// bekannten Stelle auf hellem Grund. Tippt man in seine Mitte, muss der Kasten dieses
/// Rechteck sein — und nicht das halbe Bild und nicht ein Fleck daneben.
///
/// Zwei Gründe, warum er sich überspringen kann. Der erste ist harmlos: ohne
/// geladenes Modell gibt es nichts zu prüfen, und die 80 MB liegen nicht im Repo und
/// sollen es auch nicht.
///
/// Der zweite ist ärgerlich und gemessen: **Core ML rechnet im Simulator die Maske
/// nicht aus.** Kodierer und Bewertungen kommen richtig heraus — Einbettungen mit
/// plausiblen Werten, drei Scores zwischen 0,1 und 0,98 —, aber `low_res_masks` ist
/// Byte für Byte null, auf allen drei Rechenwegen. Dasselbe Modell, dieselben
/// Eingaben, dieselben neunzig Zeilen auf dem Mac ausgeführt: Maske von -13,4 bis
/// 10,3 und ein Kasten, der auf zwei Promille auf dem Rechteck liegt.
///
/// Es ist also nicht der Code. Derselbe Simulator schafft auch Vision nicht
/// („Could not create inference context"). Auf dem Gerät läuft der Test mit.
final class SegmenterTests: XCTestCase {

    private func skipWhereCoreMLCannot() throws {
        try XCTSkipUnless(SegmentAssets.looksInstalled,
                          "Das Modell liegt nicht auf diesem Gerät.")
        #if targetEnvironment(simulator)
        throw XCTSkip("Core ML liefert im Simulator eine leere Maske. Auf dem Mac "
                      + "mit denselben Modellen geprüft: Kasten auf zwei Promille genau.")
        #endif
    }

    private func image(rectangle: CGRect, size: CGSize = CGSize(width: 1_200, height: 900)) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.25, green: 0.16, blue: 0.16, alpha: 1).setFill()
            ctx.fill(CGRect(x: rectangle.minX * size.width, y: rectangle.minY * size.height,
                            width: rectangle.width * size.width,
                            height: rectangle.height * size.height))
        }
    }

    func testTappingAnObjectReturnsItsExtent() async throws {
        try skipWhereCoreMLCannot()

        let shape = CGRect(x: 0.30, y: 0.35, width: 0.40, height: 0.40)
        let segmenter = Segmenter()
        try await segmenter.encode(image(rectangle: shape))

        let hit = try await segmenter.object(at: CGPoint(x: shape.midX, y: shape.midY))
        let object = try XCTUnwrap(hit, "Auf ein Rechteck getippt und nichts bekommen.")

        // Grosszügig: die Maske hat 256 Pixel Kantenlänge, das sind vier Promille
        // Auflösung je Schritt, und die Kanten laufen weich aus.
        XCTAssertEqual(object.box.minX, shape.minX, accuracy: 0.06)
        XCTAssertEqual(object.box.minY, shape.minY, accuracy: 0.06)
        XCTAssertEqual(object.box.maxX, shape.maxX, accuracy: 0.06)
        XCTAssertEqual(object.box.maxY, shape.maxY, accuracy: 0.06)
        XCTAssertNotNil(object.mask, "Ohne Umriss gibt es nichts anzuzeigen.")
    }

    /// Derselbe Aufbau, anderes Rechteck: ein Test, der immer denselben Kasten
    /// zurückgäbe, würde auch dann bestehen, wenn die Koordinaten vertauscht wären.
    func testTheExtentFollowsTheObject() async throws {
        try skipWhereCoreMLCannot()

        let shape = CGRect(x: 0.08, y: 0.10, width: 0.26, height: 0.22)
        let segmenter = Segmenter()
        try await segmenter.encode(image(rectangle: shape))

        let hit = try await segmenter.object(at: CGPoint(x: shape.midX, y: shape.midY))
        let object = try XCTUnwrap(hit)
        XCTAssertLessThan(object.box.midX, 0.4, "Links oben getippt, links oben gefunden.")
        XCTAssertLessThan(object.box.midY, 0.4)
        XCTAssertEqual(object.box.width, shape.width, accuracy: 0.08)
        XCTAssertEqual(object.box.height, shape.height, accuracy: 0.08)
    }

    // MARK: Die Auswahl unter den drei Vorschlägen

    func testArgmaxPicksTheHighestScore() throws {
        let scores = try MLMultiArray(shape: [1, 3], dataType: .float32)
        scores[0] = 0.2
        scores[1] = 0.9
        scores[2] = 0.5
        XCTAssertEqual(Segmenter.argmax(scores), 1)
    }

    // MARK: Die Umrechnung der Maske

    /// Dieselbe Falle wie bei der Instanzmaske: eine vertauschte Achse liefert Kästen,
    /// die plausibel aussehen und am falschen Ding liegen.
    func testMaskBoxUsesTopLeftOrigin() throws {
        let side = 64
        let masks = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)],
                                     dataType: .float32)
        for i in 0 ..< masks.count { masks[i] = -10 }
        // Ein Fleck oben links im Kanal 1.
        for y in 0 ..< 16 {
            for x in 0 ..< 16 {
                masks[1 * side * side + y * side + x] = 8
            }
        }
        let object = try XCTUnwrap(Segmenter.object(from: masks, channel: 1))
        XCTAssertEqual(object.box.minX, 0, accuracy: 0.02)
        XCTAssertEqual(object.box.minY, 0, accuracy: 0.02, "Oben ist oben.")
        XCTAssertEqual(object.box.width, 0.25, accuracy: 0.03)
        XCTAssertEqual(object.box.height, 0.25, accuracy: 0.03)
    }

    func testAnEmptyMaskYieldsNoObject() throws {
        let side = 32
        let masks = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)],
                                     dataType: .float32)
        for i in 0 ..< masks.count { masks[i] = -1 }
        XCTAssertNil(Segmenter.object(from: masks, channel: 0))
    }
}
