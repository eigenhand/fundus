import CoreImage
import UIKit
import Vision

/// An object the device recognised in the picture as a thing in its own right.
struct FoundObject: Identifiable, Equatable, Sendable {
    let id: Int
    /// In image coordinates, 0…1, origin top left — the way SwiftUI works.
    let box: CGRect

    /// How far the centre of this object is from the centre of the image.
    var distanceFromCentre: CGFloat {
        let dx = box.midX - 0.5, dy = box.midY - 0.5
        return sqrt(dx * dx + dy * dy)
    }
}

/// Finds the objects in a photo so that the user can tap them.
///
/// With Apple's instance mask and not with YOLO, and that is not convenience:
/// Ultralytics is under AGPL-3.0. It cannot be taken into an Apache-2.0 project — the
/// whole result would then have to stand under the AGPL. That would be a decision
/// about the project and not a dependency. Above all, though, the class list does not
/// help — eighty COCO classes know `person`, `bottle` and `chair`, but no stepper
/// motor and no assortment box. What the thing *is* is something the model reading the
/// photo says anyway. All that is needed here is **where** the things are.
///
/// That is exactly what `VNGenerateForegroundInstanceMaskRequest` has been able to do
/// since iOS 17, on the device, without weights in the bundle: the same technique as
/// "lift subject from background" in the photo library. It finds the prominent objects
/// in the foreground — a handful, not forty screws in a tin. It is not meant for that
/// either.
enum ObjectFinder {

    private static let queue = DispatchQueue(label: "dev.eigenhand.fundus.objekte")
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// How many objects are offered.
    ///
    /// More than a handful stops being a choice and becomes a second task — and every
    /// tapped cut-out is its own paid model call.
    static let maxObjects = 8

    /// The shortest edge from which anything can still be read.
    ///
    /// A cut-out of thirty pixels holds no lettering any more and no edge a model
    /// could name — sending it would mean paying for a call and getting a guess. The
    /// number stands here and not three times over in the code, because the interface
    /// has to know it too: a box that comes to nothing here must not dissolve into air
    /// only at the moment of taking it over.
    static let minimumEdge = 64

    static func find(in image: UIImage) async -> [FoundObject] {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: locate(image)) }
        }
    }

    private static func locate(_ image: UIImage) -> [FoundObject] {
        guard let cg = image.scaledDown(maxEdge: 1_400).cgImage else { return [] }
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let observation = request.results?.first else { return [] }

        var found: [FoundObject] = []
        for instance in observation.allInstances {
            guard let mask = try? observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: instance), from: handler),
                  let box = box(of: mask)
            else { continue }
            // Tiny specks are noise, not objects — and nobody hits a tap target of two
            // per cent of the image area anyway.
            guard box.width * box.height > 0.004 else { continue }
            found.append(FoundObject(id: instance, box: box))
        }
        // Largest first: what stands large in the picture is usually what is meant.
        return Array(found.sorted { $0.box.width * $0.box.height > $1.box.width * $1.box.height }
            .prefix(maxObjects))
    }

    /// The bounding box of a mask, in 0…1 with the origin top left.
    ///
    /// The mask is scaled down before it is scanned. A tap target needs no
    /// pixel-accuracy, and walking a full-size image row by row — eight times, once
    /// per object — would be the only part here that you would feel.
    ///
    /// `internal`, because converting from bottom-left to top-left is exactly the spot
    /// where a sign error goes unnoticed until the frames lie mirrored in the picture.
    /// There is a test for it with a mask whose blob is known.
    static func box(of mask: CVPixelBuffer) -> CGRect? {
        var ci = CIImage(cvPixelBuffer: mask)
        guard ci.extent.width > 0, ci.extent.height > 0 else { return nil }

        let side: CGFloat = 192
        let factor = min(1, side / max(ci.extent.width, ci.extent.height))
        if factor < 1 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        }
        let w = Int(ci.extent.width.rounded()), h = Int(ci.extent.height.rounded())
        guard w > 0, h > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: w * h)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            ciContext.render(ci, toBitmap: base, rowBytes: w,
                             bounds: CGRect(x: ci.extent.minX, y: ci.extent.minY,
                                            width: CGFloat(w), height: CGFloat(h)),
                             format: .R8, colorSpace: nil)
        }

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0 ..< h {
            let row = y * w
            for x in 0 ..< w where bytes[row + x] > 127 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        return CGRect(x: CGFloat(minX) / CGFloat(w),
                      y: CGFloat(minY) / CGFloat(h),
                      width: CGFloat(maxX - minX + 1) / CGFloat(w),
                      height: CGFloat(maxY - minY + 1) / CGFloat(h))
    }

    /// Cuts an object free: keep the outline, everything else white.
    ///
    /// The reason is the same as for cropping at all, only one step further. A cut-out
    /// reads better than a shelf; an object cut free reads better than a cut-out with
    /// half the bed still in it. What is white does not distract and does not get
    /// described along with the rest.
    ///
    /// The margin of two per cent is not a safety distance but content: a mask sits on
    /// the edge, and it is often exactly on the edge that what matters stands — the
    /// rim of the housing, the shadow that separates a thing from what it lies on. The
    /// cut is therefore made at the **widened** outline.
    static func cutOut(_ image: UIImage, object: SegmentedObject,
                       margin: CGFloat = 0.02) -> UIImage? {
        let base = image.scaledDown(maxEdge: 1_400)
        guard let cg = base.cgImage, object.side > 0,
              object.bits.count == object.side * object.side else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }

        // Equally far in every direction, measured against the longer edge — otherwise
        // a flat thing would get much more margin horizontally than vertically.
        let reach = margin * max(object.box.width, object.box.height)
        // Rounded up, and with no margin genuinely zero. The mask is 256 pixels along
        // an edge: two per cent of a medium-sized object comes to one and a half
        // pixels in it, and rounded down the margin would have vanished at exactly the
        // moment it was asked for.
        let radius = margin > 0
            ? max(1, Int((reach * CGFloat(object.side)).rounded(.up)))
            : 0
        let grown = dilate(object.bits, side: object.side, radius: radius)
        guard let area = bounds(of: grown, side: object.side) else { return nil }

        let rect = CGRect(x: (area.minX * CGFloat(width)).rounded(.down),
                          y: (area.minY * CGFloat(height)).rounded(.down),
                          width: (area.width * CGFloat(width)).rounded(),
                          height: (area.height * CGFloat(height)).rounded())
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width >= CGFloat(minimumEdge), rect.height >= CGFloat(minimumEdge)
        else { return nil }

        var source = [UInt8](repeating: 0, count: width * height * 4)
        source.withUnsafeMutableBytes { raw in
            guard let addr = raw.baseAddress,
                  let context = CGContext(data: addr, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let outWidth = Int(rect.width), outHeight = Int(rect.height)
        let left = Int(rect.minX), top = Int(rect.minY)
        var out = [UInt8](repeating: 255, count: outWidth * outHeight * 4)

        for y in 0 ..< outHeight {
            let sourceY = top + y
            // The mask is square and stands for the whole image — the same linear
            // conversion as for the box.
            let maskY = min(object.side - 1, (sourceY * object.side) / height)
            for x in 0 ..< outWidth {
                let sourceX = left + x
                let maskX = min(object.side - 1, (sourceX * object.side) / width)
                let target = (y * outWidth + x) * 4
                guard grown[maskY * object.side + maskX] > 0 else {
                    out[target + 3] = 255      // weiss, undurchsichtig
                    continue
                }
                let from = (sourceY * width + sourceX) * 4
                out[target + 0] = source[from + 0]
                out[target + 1] = source[from + 1]
                out[target + 2] = source[from + 2]
                out[target + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let piece = CGImage(width: outWidth, height: outHeight, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: outWidth * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: piece)
    }

    /// Grow the outline outwards.
    ///
    /// In two passes rather than a square per point: horizontally, then vertically.
    /// The result is the same and the work grows with the radius rather than with its
    /// square.
    static func dilate(_ bits: [UInt8], side: Int, radius: Int) -> [UInt8] {
        guard radius > 0, side > 0, bits.count == side * side else { return bits }
        var wide = [UInt8](repeating: 0, count: bits.count)
        for y in 0 ..< side {
            let row = y * side
            for x in 0 ..< side {
                var on: UInt8 = 0
                for dx in max(0, x - radius) ... min(side - 1, x + radius) where bits[row + dx] > 0 {
                    on = 255
                    break
                }
                wide[row + x] = on
            }
        }
        var out = [UInt8](repeating: 0, count: bits.count)
        for x in 0 ..< side {
            for y in 0 ..< side {
                var on: UInt8 = 0
                for dy in max(0, y - radius) ... min(side - 1, y + radius)
                where wide[dy * side + x] > 0 {
                    on = 255
                    break
                }
                out[y * side + x] = on
            }
        }
        return out
    }

    /// The bounding box of a raw mask, in 0…1 with the origin top left.
    static func bounds(of bits: [UInt8], side: Int) -> CGRect? {
        guard side > 0, bits.count == side * side else { return nil }
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0 ..< side {
            let row = y * side
            for x in 0 ..< side where bits[row + x] > 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: CGFloat(minX) / CGFloat(side), y: CGFloat(minY) / CGFloat(side),
                      width: CGFloat(maxX - minX + 1) / CGFloat(side),
                      height: CGFloat(maxY - minY + 1) / CGFloat(side))
    }

    /// Cuts an object out of the photo.
    ///
    /// With a margin, and it is not cosmetic: what the model needs in order to name a
    /// component often stands just beside it — the lettering on the housing, the plug
    /// on the cable, the label on the lid. A cut-out exactly on the edge cuts that
    /// away.
    static func crop(_ image: UIImage, to box: CGRect, margin: CGFloat = 0.08) -> UIImage? {
        let base = image.scaledDown(maxEdge: 1_400)
        guard let cg = base.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)

        let padded = box.insetBy(dx: -box.width * margin, dy: -box.height * margin)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let rect = CGRect(x: (padded.minX * w).rounded(.down),
                          y: (padded.minY * h).rounded(.down),
                          width: (padded.width * w).rounded(),
                          height: (padded.height * h).rounded())

        // Too small means: the model will read nothing from it either.
        guard rect.width >= CGFloat(minimumEdge), rect.height >= CGFloat(minimumEdge),
              let piece = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: piece)
    }
}
