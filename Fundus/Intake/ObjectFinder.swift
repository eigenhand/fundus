import CoreImage
import UIKit
import Vision

/// Ein Gegenstand, den das Gerät im Bild als eigenes Ding erkannt hat.
struct FoundObject: Identifiable, Equatable, Sendable {
    let id: Int
    /// In Bildkoordinaten, 0…1, Ursprung oben links — wie SwiftUI rechnet.
    let box: CGRect

    /// Wie weit die Mitte dieses Gegenstands von der Bildmitte entfernt ist.
    var distanceFromCentre: CGFloat {
        let dx = box.midX - 0.5, dy = box.midY - 0.5
        return sqrt(dx * dx + dy * dy)
    }
}

/// Findet die Gegenstände auf einem Foto, damit der Nutzer sie antippen kann.
///
/// Mit Apples Instanzmaske und nicht mit YOLO, und das ist keine Bequemlichkeit:
/// Ultralytics steht unter AGPL-3.0, was für ein GPL-3.0-Repo eine Entscheidung wäre
/// und nicht eine Abhängigkeit. Vor allem aber hilft die Klassenliste nicht — achtzig
/// COCO-Klassen kennen `person`, `bottle` und `chair`, aber keinen Schrittmotor und
/// keine Sortimentsbox. Was das Ding *ist*, sagt ohnehin das Modell, das das Foto
/// liest. Hier wird nur gebraucht, **wo** die Dinge sind.
///
/// Genau das kann `VNGenerateForegroundInstanceMaskRequest` seit iOS 17, auf dem
/// Gerät, ohne Gewichte im Bundle: dieselbe Technik wie „Motiv ausschneiden" im
/// Fotoalbum. Sie findet die auffälligen Gegenstände im Vordergrund — eine Handvoll,
/// nicht vierzig Schrauben in einer Dose. Dafür ist sie auch nicht gedacht.
enum ObjectFinder {

    private static let queue = DispatchQueue(label: "dev.eigenhand.fundus.objekte")
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Wie viele Gegenstände angeboten werden.
    ///
    /// Mehr als eine Handvoll ist keine Auswahl mehr, sondern eine zweite Aufgabe —
    /// und jeder angetippte Ausschnitt ist ein eigener, bezahlter Modellaufruf.
    static let maxObjects = 8

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
            // Winzige Flecken sind Rauschen, kein Gegenstand — und ein Tippziel von
            // zwei Prozent Bildfläche trifft ohnehin niemand.
            guard box.width * box.height > 0.004 else { continue }
            found.append(FoundObject(id: instance, box: box))
        }
        // Die grössten zuerst: was gross im Bild steht, ist meistens gemeint.
        return Array(found.sorted { $0.box.width * $0.box.height > $1.box.width * $1.box.height }
            .prefix(maxObjects))
    }

    /// Der umschliessende Kasten einer Maske, in 0…1 mit Ursprung oben links.
    ///
    /// Die Maske wird vor dem Abtasten klein gerechnet. Ein Tippziel braucht keine
    /// Pixelgenauigkeit, und ein Bild in voller Grösse Zeile für Zeile durchzugehen —
    /// achtmal, einmal je Gegenstand — wäre der einzige Teil hier, den man spürt.
    ///
    /// `internal`, weil die Umrechnung von unten-links nach oben-links genau die
    /// Stelle ist, an der ein Vorzeichenfehler niemandem auffällt, bis die Rahmen im
    /// Bild gespiegelt liegen. Dafür gibt es einen Test mit einer Maske, deren Fleck
    /// man kennt.
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

    /// Schneidet einen Gegenstand aus dem Foto.
    ///
    /// Mit Rand, und der ist nicht Kosmetik: was das Modell braucht, um ein Bauteil zu
    /// benennen, steht oft knapp daneben — der Aufdruck auf dem Gehäuse, der Stecker
    /// am Kabel, die Beschriftung auf dem Deckel. Ein Ausschnitt genau an der Kante
    /// schneidet das weg.
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

        // Zu klein heisst: daraus liest auch das Modell nichts mehr.
        guard rect.width >= 64, rect.height >= 64,
              let piece = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: piece)
    }
}
