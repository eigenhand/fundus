import CoreVideo
import XCTest
@testable import Fundus

/// Die Umrechnung der Masken.
///
/// Die eine Stelle, an der hier ein Fehler sitzen kann, ohne dass es jemandem
/// auffällt: CoreImage rechnet von unten links, SwiftUI von oben links. Ein
/// vertauschtes Vorzeichen liefert Rahmen, die sauber aussehen und am falschen
/// Gegenstand liegen — und wer dann auf den Motor tippt, bekommt die Spule.
///
/// Deshalb eine Maske, deren Fleck man kennt, statt einer Annahme über die
/// Richtung.
final class ObjectFinderTests: XCTestCase {

    /// Eine Maske mit einem weissen Fleck in den angegebenen Zeilen und Spalten.
    /// Zeile 0 ist oben — so liegen die Bytes eines Pixelpuffers.
    private func mask(size: Int = 100, rows: Range<Int>, cols: Range<Int>) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_OneComponent8,
                                         [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
                                         &buffer)
        let pixels = try XCTUnwrap(buffer, "Pixelpuffer nicht angelegt (\(status))")

        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        for y in 0 ..< size {
            for x in 0 ..< size {
                base[y * stride + x] = (rows.contains(y) && cols.contains(x)) ? 255 : 0
            }
        }
        return pixels
    }

    /// Ein Fleck oben links muss oben links herauskommen — nicht unten links.
    func testBoxUsesTopLeftOrigin() throws {
        let box = try XCTUnwrap(ObjectFinder.box(of: mask(rows: 0 ..< 25, cols: 0 ..< 25)))
        XCTAssertEqual(box.minX, 0, accuracy: 0.04)
        XCTAssertEqual(box.minY, 0, accuracy: 0.04, "Oben ist oben.")
        XCTAssertEqual(box.width, 0.25, accuracy: 0.05)
        XCTAssertEqual(box.height, 0.25, accuracy: 0.05)
    }

    func testBoxFindsABlobAtTheBottomRight() throws {
        let box = try XCTUnwrap(ObjectFinder.box(of: mask(rows: 75 ..< 100, cols: 75 ..< 100)))
        XCTAssertEqual(box.maxX, 1, accuracy: 0.04)
        XCTAssertEqual(box.maxY, 1, accuracy: 0.04)
        XCTAssertEqual(box.minX, 0.75, accuracy: 0.05)
        XCTAssertEqual(box.minY, 0.75, accuracy: 0.05)
    }

    func testEmptyMaskHasNoBox() throws {
        XCTAssertNil(ObjectFinder.box(of: try mask(rows: 0 ..< 0, cols: 0 ..< 0)))
    }

    // MARK: Die Mitte

    /// „Nur das mittlere Ding" ist der häufigste Fall: man hält etwas in der Hand und
    /// zielt darauf. Deshalb ist es vorgewählt, und deshalb muss die Rechnung stimmen.
    func testTheCentreObjectIsTheOneNearestTheMiddle() {
        let edge = FoundObject(id: 1, box: CGRect(x: 0.02, y: 0.02, width: 0.2, height: 0.2))
        let middle = FoundObject(id: 2, box: CGRect(x: 0.4, y: 0.42, width: 0.2, height: 0.2))
        let corner = FoundObject(id: 3, box: CGRect(x: 0.75, y: 0.75, width: 0.2, height: 0.2))

        let nearest = [edge, middle, corner].min { $0.distanceFromCentre < $1.distanceFromCentre }
        XCTAssertEqual(nearest?.id, 2)
        XCTAssertLessThan(middle.distanceFromCentre, edge.distanceFromCentre)
        XCTAssertLessThan(middle.distanceFromCentre, corner.distanceFromCentre)
    }

    // MARK: Die Drehung

    /// Der Fehler, den man nur auf einem Gerät sieht.
    ///
    /// Ein Kamerafoto steht aufrecht, weil ein Merker danebensteht, nicht weil die
    /// Pixel so liegen. `UIImage.size` und jede Anzeige lesen den Merker; `cgImage`
    /// liest ihn nicht und gibt die Sensordaten quer zurück. Wer beides mischt,
    /// rechnet in zwei Rahmen, die neunzig Grad auseinanderliegen — und die Maske
    /// liegt dann als grosser Block irgendwo im Bild statt auf dem Gegenstand.
    ///
    /// `scaledDown` zeichnet die Drehung in die Pixel. Daran haengt jetzt alles:
    /// Anzeige, Fingertipp, Kasten und Ausschnitt.
    func testScalingDownBakesTheOrientationIntoThePixels() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1; format.opaque = true
        // Quer, links rot, rechts blau.
        let landscape = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100),
                                                format: format).image { ctx in
            UIColor.red.setFill();  ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        let sideways = UIImage(cgImage: try XCTUnwrap(landscape.cgImage),
                               scale: 1, orientation: .right)

        XCTAssertEqual(sideways.size, CGSize(width: 100, height: 200),
                       "Mit Merker gelesen ist es hochkant …")
        XCTAssertEqual(try XCTUnwrap(sideways.cgImage).width, 200,
                       "… ohne Merker liegt es quer. Genau diese Luecke war der Fehler.")

        let upright = sideways.scaledDown(maxEdge: 1_400)
        XCTAssertEqual(upright.imageOrientation, .up)
        XCTAssertEqual(upright.size, CGSize(width: 100, height: 200))
        XCTAssertEqual(try XCTUnwrap(upright.cgImage).width, 100,
                       "Jetzt stimmen Pixel und Merker ueberein.")
        XCTAssertEqual(try XCTUnwrap(upright.cgImage).height, 200)
    }

    /// Auch ein Bild, das klein genug ist, muss durch die Drehung gehen — sonst haengt
    /// die Richtigkeit an der Groesse des Fotos.
    func testASmallImageIsStraightenedToo() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1; format.opaque = true
        let small = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 30),
                                            format: format).image { ctx in
            UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 30))
        }
        let sideways = UIImage(cgImage: try XCTUnwrap(small.cgImage), scale: 1, orientation: .left)
        let upright = sideways.scaledDown(maxEdge: 1_400)
        XCTAssertEqual(upright.imageOrientation, .up)
        XCTAssertEqual(try XCTUnwrap(upright.cgImage).width, 30)
    }

    // MARK: Die Rahmen im Bild

    /// `aspectRatio(.fit)` laesst einen Rand, den die umgebende Geometrie nicht kennt.
    /// Ohne die Rechnung liegen alle Rahmen um denselben Betrag daneben — gleichmaessig
    /// genug, dass es aussieht, als stimme die Erkennung nicht.
    func testBoxesLandInsideTheLetterboxedImage() {
        // Ein Bild im Querformat in einem hohen Fenster: oben und unten bleibt Rand.
        let area = CGSize(width: 400, height: 800)
        let picture = CGSize(width: 1_000, height: 500)   // Verhaeltnis 2:1
        let full = ObjectPicker.frame(for: CGRect(x: 0, y: 0, width: 1, height: 1),
                                      image: picture, in: area)

        XCTAssertEqual(full.width, 400, accuracy: 0.5, "In der Breite fuellt es aus.")
        XCTAssertEqual(full.height, 200, accuracy: 0.5, "In der Hoehe nicht.")
        XCTAssertEqual(full.minY, 300, accuracy: 0.5, "Der Rand liegt gleich verteilt.")
        XCTAssertEqual(full.minX, 0, accuracy: 0.5)
    }

    func testABoxKeepsItsPlaceWithinThePicture() {
        let area = CGSize(width: 400, height: 800)
        let picture = CGSize(width: 1_000, height: 500)
        let middle = ObjectPicker.frame(for: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                                        image: picture, in: area)
        XCTAssertEqual(middle.midX, 200, accuracy: 0.5, "Die Bildmitte ist die Fenstermitte.")
        XCTAssertEqual(middle.midY, 400, accuracy: 0.5)
        XCTAssertEqual(middle.width, 200, accuracy: 0.5)
        XCTAssertEqual(middle.height, 100, accuracy: 0.5)
    }

    /// Hochformat im breiten Fenster — derselbe Fall, andere Achse.
    func testTallPictureInAWideWindow() {
        let full = ObjectPicker.frame(for: CGRect(x: 0, y: 0, width: 1, height: 1),
                                      image: CGSize(width: 500, height: 1_000),
                                      in: CGSize(width: 800, height: 400))
        XCTAssertEqual(full.height, 400, accuracy: 0.5)
        XCTAssertEqual(full.width, 200, accuracy: 0.5)
        XCTAssertEqual(full.minX, 300, accuracy: 0.5)
    }

    func testDegenerateSizesDoNotCrash() {
        XCTAssertEqual(ObjectPicker.frame(for: .zero, image: .zero, in: .zero), .zero)
        XCTAssertEqual(ObjectPicker.frame(for: CGRect(x: 0, y: 0, width: 1, height: 1),
                                          image: CGSize(width: 100, height: 100),
                                          in: .zero), .zero)
    }

    // MARK: Der Ausschnitt

    private func image(_ width: Int, _ height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                       format: format).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Mit Rand, und das ist nicht Kosmetik: der Aufdruck, an dem ein Bauteil erkennbar
    /// ist, steht oft knapp neben dem Bauteil.
    func testCropTakesAMarginAroundTheObject() throws {
        let source = image(1_000, 1_000)
        let box = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let piece = try XCTUnwrap(ObjectFinder.crop(source, to: box))
        XCTAssertGreaterThan(piece.size.width, 200, "200 Pixel wären der Kasten ohne Rand.")
        XCTAssertLessThan(piece.size.width, 280)
    }

    func testCropStaysInsideTheImage() throws {
        let source = image(1_000, 1_000)
        let piece = try XCTUnwrap(ObjectFinder.crop(
            source, to: CGRect(x: 0, y: 0, width: 0.3, height: 0.3)))
        XCTAssertLessThanOrEqual(piece.size.width, 1_000)
        XCTAssertLessThanOrEqual(piece.size.height, 1_000)
    }

    /// Aus einem Fleck von zwanzig Pixeln liest auch das Modell nichts mehr.
    func testTinyCropIsRefused() {
        let source = image(1_000, 1_000)
        XCTAssertNil(ObjectFinder.crop(source, to: CGRect(x: 0.5, y: 0.5, width: 0.01, height: 0.01)))
    }
}
