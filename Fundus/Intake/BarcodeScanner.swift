import UIKit
import Vision

/// Reading barcodes out of a photo — with Vision, not with the model.
///
/// That is deliberate and not a detour. A language model shown bars guesses: it sees a
/// row of digits under the code and copies it out, and when that is blurred it writes
/// something plausible. Vision instead decodes the bars themselves and checks the check
/// digit — an EAN that comes out here is the EAN that stands on the thing, or nothing
/// comes out at all.
///
/// Costs nothing, needs no connection and runs before any paid call takes place at all.
/// The codes it finds go into the prompt so that the model can assign them to the right
/// object instead of having to read them itself.
enum BarcodeScanner {

    /// Every code in the picture that can be decoded, duplicates removed.
    ///
    /// Without a completion block and without a continuation, and that is a correction,
    /// not taste. `VNImageRequestHandler.perform` works synchronously anyway: by the
    /// time it returns, the results stand on the request. The earlier version took the
    /// completion block all the same **and** caught `perform`'s error beside it — and
    /// Vision calls the block even when it throws afterwards. Both routes resumed the
    /// same continuation:
    ///
    ///     Fatal error: SWIFT TASK CONTINUATION MISUSE:
    ///     scan(_:) tried to resume its continuation more than once
    ///
    /// Not an error path but a crash, and one before the paid call: the shot was gone
    /// before it had begun. In the simulator a "Could not create inference context" set
    /// it off; on a device memory pressure is enough.
    static func scan(_ image: UIImage) async -> [ItemCode] {
        guard let cg = image.cgImage else { return [] }

        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation(image))
        do {
            try handler.perform([request])
        } catch {
            // A picture without a readable code is the normal case, not an error — and
            // if Vision does not even start, the shot simply carries on without codes.
            return []
        }

        let found = (request.results ?? [])
            .compactMap { observation -> ItemCode? in
                guard let payload = observation.payloadStringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !payload.isEmpty
                else { return nil }
                return ItemCode(value: payload,
                                kind: kind(for: observation.symbology),
                                origin: .scanned)
            }

        // The same code can stand in the picture several times — on the box and on the
        // leaflet, say. Once is enough.
        var seen = Set<String>()
        return found.filter { seen.insert($0.value).inserted }
    }

    private static func kind(for symbology: VNBarcodeSymbology) -> ItemCode.Kind {
        switch symbology {
        case .ean13, .ean8:      return .ean
        case .upce:              return .upc
        case .qr:                return .qr
        case .dataMatrix:        return .dataMatrix
        case .code128:           return .code128
        default:                 return .unknown
        }
    }

    /// Vision works on the raw pixel grid, `UIImage` carries the rotation beside it.
    /// Without this translation a code photographed upright finds nothing.
    private static func orientation(_ image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
