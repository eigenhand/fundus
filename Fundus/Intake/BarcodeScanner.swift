import UIKit
import Vision

/// Barcodes aus einem Foto lesen — mit Vision, nicht mit dem Modell.
///
/// Das ist Absicht und kein Umweg. Ein Sprachmodell, dem man Balken zeigt, rät: es
/// sieht eine Ziffernfolge unter dem Code und schreibt sie ab, und wenn sie unscharf
/// ist, schreibt es etwas Plausibles. Vision dekodiert stattdessen die Balken selbst
/// und prüft die Prüfziffer — eine EAN, die hier herauskommt, ist die EAN, die auf
/// dem Ding steht, oder es kommt gar keine heraus.
///
/// Kostet nichts, braucht keine Leitung und läuft, bevor überhaupt ein bezahlter
/// Aufruf stattfindet. Die gefundenen Codes gehen in den Prompt, damit das Modell
/// sie dem richtigen Gegenstand zuordnen kann, statt sie selbst lesen zu müssen.
enum BarcodeScanner {

    /// Alle im Bild dekodierbaren Codes, doppelte entfernt.
    static func scan(_ image: UIImage) async -> [ItemCode] {
        guard let cg = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, _ in
                let found = (request.results as? [VNBarcodeObservation] ?? [])
                    .compactMap { observation -> ItemCode? in
                        guard let payload = observation.payloadStringValue?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                              !payload.isEmpty
                        else { return nil }
                        return ItemCode(value: payload,
                                        kind: kind(for: observation.symbology),
                                        origin: .scanned)
                    }

                // Derselbe Code kann mehrfach im Bild stehen — etwa auf Schachtel und
                // Beipackzettel. Einmal reicht.
                var seen = Set<String>()
                continuation.resume(returning: found.filter { seen.insert($0.value).inserted })
            }

            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation(image))
            do {
                try handler.perform([request])
            } catch {
                // Ein Bild ohne lesbaren Code ist der Normalfall, kein Fehler. Die
                // Aufnahme läuft ohne Codes weiter.
                continuation.resume(returning: [])
            }
        }
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

    /// Vision rechnet auf dem rohen Pixelraster, `UIImage` trägt die Drehung daneben.
    /// Ohne diese Übersetzung findet ein hochkant fotografierter Code nichts.
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
