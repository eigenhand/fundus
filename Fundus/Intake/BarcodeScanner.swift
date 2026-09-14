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
    ///
    /// Ohne Abschlussblock und ohne Continuation, und das ist eine Korrektur, kein
    /// Geschmack. `VNImageRequestHandler.perform` arbeitet ohnehin synchron: wenn es
    /// zurückkommt, stehen die Ergebnisse an der Anfrage. Die frühere Fassung nahm
    /// trotzdem den Abschlussblock **und** fing daneben den Fehler von `perform` ab —
    /// und Vision ruft den Block auch dann, wenn es danach wirft. Beide Wege lösten
    /// dieselbe Continuation aus:
    ///
    ///     Fatal error: SWIFT TASK CONTINUATION MISUSE:
    ///     scan(_:) tried to resume its continuation more than once
    ///
    /// Kein Fehlerpfad, sondern ein Absturz, und zwar vor dem bezahlten Aufruf: die
    /// Aufnahme war weg, bevor sie begonnen hatte. Ausgelöst hat es im Simulator ein
    /// „Could not create inference context“; auf einem Gerät genügt Speicherdruck.
    static func scan(_ image: UIImage) async -> [ItemCode] {
        guard let cg = image.cgImage else { return [] }

        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation(image))
        do {
            try handler.perform([request])
        } catch {
            // Ein Bild ohne lesbaren Code ist der Normalfall, kein Fehler — und wenn
            // Vision gar nicht erst anläuft, läuft die Aufnahme eben ohne Codes weiter.
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

        // Derselbe Code kann mehrfach im Bild stehen — etwa auf Schachtel und
        // Beipackzettel. Einmal reicht.
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
