import CoreVideo
import XCTest
@testable import Fundus

/// Converting the masks.
///
/// The one place where an error can sit here without anybody noticing: CoreImage
/// reckons from the bottom left, SwiftUI from the top left. A swapped sign delivers
/// frames that look clean and lie on the wrong object — and whoever then taps the
/// motor gets the spool.
///
/// Hence a mask whose blob is known, rather than an assumption about the direction.
final class ObjectFinderTests: XCTestCase {

    /// A mask with a white blob in the given rows and columns. Row 0 is at the top —
    /// that is how the bytes of a pixel buffer lie.
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

    /// A blob at the top left has to come out at the top left — not the bottom left.
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

    /// "Only the middle thing" is the commonest case: you hold something in your hand
    /// and aim at it. That is why it is preselected, and why the arithmetic has to be
    /// right.
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

    /// The error you only see on a device.
    ///
    /// A camera photo stands upright because a flag sits beside it, not because the
    /// pixels lie that way. `UIImage.size` and every display read the flag; `cgImage`
    /// does not and returns the sensor data sideways. Mixing the two means working in
    /// two frames ninety degrees apart — and the mask then lies as a large block
    /// somewhere in the picture instead of on the object.
    ///
    /// `scaledDown` bakes the rotation into the pixels. Everything now hangs on it:
    /// display, tap, box and cut-out.
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

    /// An image that is already small enough has to go through the rotation too —
    /// otherwise correctness hangs on the size of the photo.
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

    // MARK: The frames in the picture

    /// `aspectRatio(.fit)` leaves a margin that the surrounding geometry knows nothing
    /// about. Without the arithmetic every frame is off by the same amount — evenly
    /// enough that it looks as if the detection were wrong.
    func testBoxesLandInsideTheLetterboxedImage() {
        // A landscape picture in a tall window: a margin stays at the top and bottom.
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

    /// Portrait in a wide window — the same case, the other axis.
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

    // MARK: Freistellen

    /// A square mask with a blob in a known place.
    private func bits(side: Int, rows: Range<Int>, cols: Range<Int>) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: side * side)
        for y in rows { for x in cols { out[y * side + x] = 255 } }
        return out
    }

    /// A round outline — the case in which the box has corners that do not belong to it.
    private func disc(side: Int, centre: Int, radius: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: side * side)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let dx = x - centre, dy = y - centre
                if dx * dx + dy * dy <= radius * radius { out[y * side + x] = 255 }
            }
        }
        return out
    }

    func testDilationGrowsInEveryDirection() {
        let side = 32
        let dot = bits(side: side, rows: 15 ..< 17, cols: 15 ..< 17)
        let grown = ObjectFinder.dilate(dot, side: side, radius: 3)

        let before = try? XCTUnwrap(ObjectFinder.bounds(of: dot, side: side))
        let after = try? XCTUnwrap(ObjectFinder.bounds(of: grown, side: side))
        guard let before, let after else { return XCTFail("kein Kasten") }

        XCTAssertLessThan(after.minX, before.minX)
        XCTAssertLessThan(after.minY, before.minY)
        XCTAssertGreaterThan(after.maxX, before.maxX)
        XCTAssertGreaterThan(after.maxY, before.maxY)
        // Drei Punkte auf jeder Seite, an beiden Achsen dieselben.
        XCTAssertEqual(after.width * CGFloat(side), 8, accuracy: 0.01)
        XCTAssertEqual(after.height * CGFloat(side), 8, accuracy: 0.01)
    }

    func testDilationStopsAtTheEdge() {
        let side = 16
        let corner = ObjectFinder.dilate(bits(side: side, rows: 0 ..< 2, cols: 0 ..< 2),
                                         side: side, radius: 5)
        let box = ObjectFinder.bounds(of: corner, side: side)
        XCTAssertEqual(box?.minX, 0)
        XCTAssertEqual(box?.minY, 0)
    }

    func testDilationWithoutRadiusChangesNothing() {
        let side = 16
        let dot = bits(side: side, rows: 4 ..< 6, cols: 4 ..< 6)
        XCTAssertEqual(ObjectFinder.dilate(dot, side: side, radius: 0), dot)
    }

    func testEmptyMaskHasNoBounds() {
        XCTAssertNil(ObjectFinder.bounds(of: [UInt8](repeating: 0, count: 64), side: 8))
    }

    /// The core of it: whatever does not belong to the object turns white — and the
    /// object stays as it was.
    func testEverythingOutsideTheObjectTurnsWhite() throws {
        let size = 400
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1; format.opaque = true
        // Red ground, in the middle a blue square from 0.4 to 0.6.
        let source = UIGraphicsImageRenderer(size: CGSize(width: size, height: size),
                                             format: format).image { ctx in
            UIColor.red.setFill();  ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 160, y: 160, width: 80, height: 80))
        }

        // A **round** outline, and that is the point: with a rectangular one the
        // cut-out is exactly the mask and there would be nothing left to paint white.
        // Only the corners of a box around a circle show whether it was cut free.
        let side = 100
        let object = SegmentedObject(
            id: UUID(),
            box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            mask: nil,
            bits: disc(side: side, centre: 50, radius: 10),
            side: side)

        let piece = try XCTUnwrap(ObjectFinder.cutOut(source, object: object, margin: 0.02))
        let pixels = try XCTUnwrap(rgba(of: piece))

        // At the centre of the cut-out stands the object: blue, not white.
        let middle = pixels.colour(atFraction: CGPoint(x: 0.5, y: 0.5))
        XCTAssertLessThan(middle.r, 60, "Die Mitte ist blau geblieben.")
        XCTAssertGreaterThan(middle.b, 190)

        // In the corner of the cut-out there was red — it does not belong to the
        // circle. Now there is white.
        let corner = pixels.colour(atFraction: CGPoint(x: 0.02, y: 0.02))
        XCTAssertGreaterThan(corner.r, 240, "Die Ecke ist weiss.")
        XCTAssertGreaterThan(corner.g, 240)
        XCTAssertGreaterThan(corner.b, 240)
    }

    /// The margin is not a safety distance but content — it has to be measurably there.
    func testTheCutOutCarriesTheTwoPercentMargin() throws {
        let size = 400
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1; format.opaque = true
        let source = UIGraphicsImageRenderer(size: CGSize(width: size, height: size),
                                             format: format).image { _ in }

        let side = 256
        let object = SegmentedObject(
            id: UUID(), box: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), mask: nil,
            bits: bits(side: side, rows: 77 ..< 179, cols: 77 ..< 179), side: side)

        let tight = try XCTUnwrap(ObjectFinder.cutOut(source, object: object, margin: 0))
        let padded = try XCTUnwrap(ObjectFinder.cutOut(source, object: object, margin: 0.02))
        XCTAssertGreaterThan(padded.size.width, tight.size.width,
                             "Zwei Prozent mehr sind zwei Prozent mehr.")
        XCTAssertLessThan(padded.size.width, tight.size.width * 1.3,
                          "Aber kein halbes Bild dazu.")
    }

    /// Pixel eines Bildes, zum Nachsehen.
    private struct Pixels {
        let data: [UInt8]
        let width: Int
        let height: Int
        func colour(atFraction p: CGPoint) -> (r: Int, g: Int, b: Int) {
            let x = min(width - 1, max(0, Int(p.x * CGFloat(width))))
            let y = min(height - 1, max(0, Int(p.y * CGFloat(height))))
            let o = (y * width + x) * 4
            return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]))
        }
    }

    private func rgba(of image: UIImage) -> Pixels? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            guard let addr = raw.baseAddress,
                  let ctx = CGContext(data: addr, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Pixels(data: data, width: w, height: h)
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

    /// With a margin, and that is not cosmetic: the lettering by which a component can
    /// be recognised often stands just beside the component.
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

    /// The model reads nothing from a blob of twenty pixels either.
    func testTinyCropIsRefused() {
        let source = image(1_000, 1_000)
        XCTAssertNil(ObjectFinder.crop(source, to: CGRect(x: 0.5, y: 0.5, width: 0.01, height: 0.01)))
    }
}
