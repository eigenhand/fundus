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

    /// Stellt einen Gegenstand frei: Umriss behalten, alles andere weiss.
    ///
    /// Der Grund ist derselbe wie beim Zuschneiden überhaupt, nur eine Stufe weiter.
    /// Ein Ausschnitt liest sich besser als ein Regal; ein freigestellter Gegenstand
    /// liest sich besser als ein Ausschnitt, in dem noch das halbe Bett liegt. Was
    /// weiss ist, lenkt nicht ab und wird nicht mitbeschrieben.
    ///
    /// Der Rand von zwei Prozent ist kein Sicherheitsabstand, sondern Inhalt: eine
    /// Maske sitzt auf der Kante, und genau auf der Kante steht oft, worauf es
    /// ankommt — der Rand des Gehäuses, der Schatten, der ein Ding vom Untergrund
    /// trennt. Geschnitten wird deshalb am **erweiterten** Umriss.
    static func cutOut(_ image: UIImage, object: SegmentedObject,
                       margin: CGFloat = 0.02) -> UIImage? {
        let base = image.scaledDown(maxEdge: 1_400)
        guard let cg = base.cgImage, object.side > 0,
              object.bits.count == object.side * object.side else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }

        // Gleich weit in alle Richtungen, gemessen an der laengeren Kante — sonst
        // bekaeme ein flaches Ding waagerecht viel mehr Rand als senkrecht.
        let reach = margin * max(object.box.width, object.box.height)
        // Aufgerundet, und ohne Rand wirklich null. Die Maske hat 256 Pixel
        // Kantenlaenge: zwei Prozent eines mittelgrossen Gegenstands sind darin
        // anderthalb Pixel, und abgerundet waere der Rand genau dann verschwunden,
        // wenn er verlangt wurde.
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
        guard rect.width >= 64, rect.height >= 64 else { return nil }

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
            // Die Maske ist quadratisch und steht fuer das ganze Bild — dieselbe
            // lineare Umrechnung wie beim Kasten.
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

    /// Den Umriss nach aussen wachsen lassen.
    ///
    /// In zwei Durchgaengen statt einem Quadrat je Punkt: waagerecht, dann senkrecht.
    /// Das Ergebnis ist dasselbe und die Arbeit waechst mit dem Radius statt mit
    /// seinem Quadrat.
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

    /// Der umschliessende Kasten einer Rohmaske, in 0…1 mit Ursprung oben links.
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
