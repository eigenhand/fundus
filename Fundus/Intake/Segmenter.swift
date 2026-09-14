import CoreImage
import CoreML
import UIKit
import Vision

/// Ein Gegenstand, den der Nutzer im Bild angetippt hat.
struct SegmentedObject: Identifiable, Equatable, Sendable {
    let id: UUID
    /// In Bildkoordinaten, 0…1, Ursprung oben links.
    let box: CGRect
    /// Der Umriss zum Anzeigen.
    let mask: UIImage?
    /// Derselbe Umriss als Rohdaten, quadratisch mit `side` Kantenlänge: 0 heisst
    /// aussen, 255 heisst dazu.
    ///
    /// Getrennt vom Bild, weil daraus etwas anderes wird als eine Anzeige — der
    /// Ausschnitt, der ans Modell geht, wird daran freigestellt. Aus einem `UIImage`
    /// die Bits zurückzulesen ginge auch und wäre ein Umweg über zwei Umrechnungen,
    /// bei dem man Interpolation und Alphakanal wieder auseinandersortieren müsste.
    let bits: [UInt8]
    let side: Int
}

/// Segment Anything 2.1 auf dem Gerät.
///
/// Der Unterschied zu Apples Instanzmaske ist nicht die Genauigkeit, sondern wer
/// entscheidet. `VNGenerateForegroundInstanceMaskRequest` sucht sich selbst aus, was
/// im Bild ein Gegenstand ist, und liegt bei einer Werkbank regelmaessig daneben — es
/// ist ein Modell fuer Portraits und Haustiere. SAM fragt nicht, sondern antwortet:
/// der Nutzer tippt auf ein Ding, und es sagt, wo dieses Ding aufhoert.
///
/// Das passt hier besser, weil der Mensch ohnehin danebensteht. Er weiss, was er
/// meint; gebraucht wird nur die Kante.
///
/// Drei Modelle, und die Aufteilung ist der Grund, warum das ueberhaupt fluessig geht:
/// der Bildkodierer ist der teure Teil und laeuft **einmal je Foto**. Jeder weitere
/// Fingertipp kostet nur den Prompt-Kodierer und den Maskendekodierer — zusammen
/// zwoelf Megabyte und ein Bruchteil der Zeit.
actor Segmenter {

    /// Das Modell erwartet ein Quadrat. Gestreckt, nicht beschnitten — dann bleibt die
    /// Umrechnung der Koordinaten eine Multiplikation.
    static let side = 1_024

    enum Failure: Error, Equatable {
        case notInstalled
        case broken(String)
    }

    private var encoder: MLModel?
    private var promptEncoder: MLModel?
    private var decoder: MLModel?

    /// Die Einbettung des zuletzt kodierten Fotos.
    private var embedding: (image: MLMultiArray, s0: MLMultiArray, s1: MLMultiArray)?

    var isLoaded: Bool { encoder != nil }

    // MARK: Laden

    func load() throws {
        guard encoder == nil else { return }
        guard SegmentAssets.looksInstalled else { throw Failure.notInstalled }
        do {
            encoder = try model(SegmentAssets.encoderPackage, named: "encoder")
            promptEncoder = try model(SegmentAssets.promptPackage, named: "prompt")
            decoder = try model(SegmentAssets.decoderPackage, named: "decoder")
        } catch {
            encoder = nil; promptEncoder = nil; decoder = nil
            throw Failure.broken(error.localizedDescription)
        }
    }

    /// Uebersetzt ein `.mlpackage` einmal und behaelt das Ergebnis.
    ///
    /// Core ML uebersetzt ein Paket beim Laden, und das dauert bei 67 MB spuerbar. Das
    /// Ergebnis landet neben den Gewichten, damit es beim zweiten Foto schon dasteht.
    private func model(_ package: URL, named name: String) throws -> MLModel {
        let compiled = SegmentAssets.compiledDirectory
            .appendingPathComponent(name).appendingPathExtension("mlmodelc")
        if !FileManager.default.fileExists(atPath: compiled.path) {
            let fresh = try MLModel.compileModel(at: package)
            try? FileManager.default.removeItem(at: compiled)
            try FileManager.default.moveItem(at: fresh, to: compiled)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return try MLModel(contentsOf: compiled, configuration: configuration)
    }

    // MARK: Ein Foto vorbereiten

    /// Der teure Schritt, einmal je Foto.
    ///
    /// `scaledDown` zuerst, und das ist keine Sparmassnahme, sondern die Korrektur
    /// eines Fehlers, den man nur auf einem Geraet sieht: ein Kamerafoto traegt seine
    /// Drehung als Merker neben den Pixeln, und `cgImage` gibt die **ungedrehten**
    /// Sensordaten zurueck. SwiftUI zeigt das Bild aufrecht, das Modell bekam es quer
    /// — Maske und Anzeige lagen in zwei verschiedenen Rahmen, und die Maske sah aus
    /// wie ein grosser Block irgendwo im Bild. `scaledDown` zeichnet die Drehung ein.
    func encode(_ image: UIImage) throws {
        try load()
        guard let encoder, let cg = image.scaledDown(maxEdge: 1_400).cgImage else {
            throw Failure.broken("Kein Bild.")
        }
        guard let constraint = encoder.modelDescription
            .inputDescriptionsByName["image"]?.imageConstraint else {
            throw Failure.broken("Der Bildkodierer nennt keine Bildgroesse.")
        }

        // Gestreckt statt beschnitten: sonst faende der Fingertipp an einer anderen
        // Stelle statt und die Maske laege daneben.
        let value = try MLFeatureValue(
            cgImage: cg, constraint: constraint,
            options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": value])
        let output = try encoder.prediction(from: input)

        guard let embedded = output.featureValue(for: "image_embedding")?.multiArrayValue,
              let s0 = output.featureValue(for: "feats_s0")?.multiArrayValue,
              let s1 = output.featureValue(for: "feats_s1")?.multiArrayValue else {
            throw Failure.broken("Der Bildkodierer lieferte keine Einbettung.")
        }
        embedding = (embedded, s0, s1)
    }

    func forget() { embedding = nil }

    // MARK: Ein Fingertipp

    /// Was an dieser Stelle liegt. Der Punkt in 0…1, Ursprung oben links.
    func object(at point: CGPoint) throws -> SegmentedObject? {
        // 1 heisst: dieser Punkt gehoert zum Ding. 0 hiesse: er gehoert ausdruecklich
        // nicht dazu — das waere die Verfeinerung, die es hier noch nicht gibt.
        try predict([(point, 1)])
    }

    /// Was in diesem Kasten liegt. Fuer den Fall, dass ein Tipp das Falsche trifft —
    /// bei einem Ding vor unruhigem Hintergrund oder einem, das ein anderes verdeckt.
    ///
    /// SAM kennt dafuer einen eigenen Prompt: zwei Punkte mit den Marken **2** und
    /// **3** statt 1, also „hier oben links, dort unten rechts". Dass Apples Umsetzung
    /// die behalten hat, ist gemessen und nicht angenommen — mit zwei Rechtecken im
    /// Bild und einem Kasten um das eine kommt genau dieses heraus, Zeichen fuer
    /// Zeichen dasselbe wie bei einem Tipp hinein. Dieselben zwei Punkte als
    /// Vordergrund markiert liefern dagegen das ganze Bild, und das ist die
    /// Gegenprobe: die Marken werden wirklich als Kasten gelesen.
    func object(in box: CGRect) throws -> SegmentedObject? {
        guard box.width > 0.01, box.height > 0.01 else { return nil }
        return try predict([
            (CGPoint(x: box.minX, y: box.minY), 2),
            (CGPoint(x: box.maxX, y: box.maxY), 3),
        ])
    }

    private func predict(_ prompts: [(point: CGPoint, label: Int32)]) throws -> SegmentedObject? {
        guard let promptEncoder, let decoder, let embedding else {
            throw Failure.broken("Es ist kein Foto kodiert.")
        }
        guard !prompts.isEmpty else { return nil }

        let count = NSNumber(value: prompts.count)
        let points = try MLMultiArray(shape: [1, count, 2], dataType: .float32)
        let labels = try MLMultiArray(shape: [1, count], dataType: .int32)
        for (i, prompt) in prompts.enumerated() {
            let index = NSNumber(value: i)
            points[[0, index, 0]] = NSNumber(value: Float(prompt.point.x) * Float(Self.side))
            points[[0, index, 1]] = NSNumber(value: Float(prompt.point.y) * Float(Self.side))
            labels[[0, index]] = NSNumber(value: prompt.label)
        }

        let prompted = try promptEncoder.prediction(from: MLDictionaryFeatureProvider(
            dictionary: ["points": points, "labels": labels]))
        guard let sparse = prompted.featureValue(for: "sparse_embeddings")?.multiArrayValue,
              let dense = prompted.featureValue(for: "dense_embeddings")?.multiArrayValue else {
            throw Failure.broken("Der Prompt-Kodierer lieferte nichts.")
        }

        let decoded = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "image_embedding": embedding.image,
            "sparse_embedding": sparse,
            "dense_embedding": dense,
            "feats_s0": embedding.s0,
            "feats_s1": embedding.s1,
        ]))
        guard let masks = decoded.featureValue(for: "low_res_masks")?.multiArrayValue,
              let scores = decoded.featureValue(for: "scores")?.multiArrayValue else {
            throw Failure.broken("Der Maskendekodierer lieferte nichts.")
        }

        // Drei Vorschlaege je Tipp — ganzes Ding, Teil davon, Teil des Teils. Genommen
        // wird der, dem das Modell selbst am meisten zutraut.
        let best = Self.argmax(scores)
        return Self.object(from: masks, channel: best)
    }

    // MARK: Aus der Maske einen Kasten machen

    static func argmax(_ scores: MLMultiArray) -> Int {
        var best = 0
        var top = -Double.greatestFiniteMagnitude
        for i in 0 ..< scores.count where scores[i].doubleValue > top {
            top = scores[i].doubleValue
            best = i
        }
        return best
    }

    /// Der Kasten und der Umriss aus einer Maske der Form [1, 3, H, B].
    ///
    /// Die Werte sind Logits: groesser als null heisst „gehoert dazu". Kein
    /// Schwellenwert zum Einstellen, weil das Modell genau so trainiert ist.
    ///
    /// `internal` und ohne Core ML im Kopf, damit es prüfbar bleibt: hier steckt
    /// dieselbe Falle wie bei der Instanzmaske — eine vertauschte Achse liefert Kaesten,
    /// die plausibel aussehen und am falschen Ding liegen.
    static func object(from masks: MLMultiArray, channel: Int) -> SegmentedObject? {
        let shape = masks.shape.map(\.intValue)
        guard shape.count == 4, channel < shape[1] else { return nil }
        let height = shape[2], width = shape[3]
        guard height > 0, width > 0 else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        var inside = [UInt8](repeating: 0, count: width * height)

        /// Beide Fliesskommabreiten, weil das Modell in float16 umgesetzt ist, die
        /// Ausgabe aber nicht zwingend. Die falsche anzunehmen liest keinen Fehler,
        /// sondern Unsinn — und Unsinn sieht wie eine Maske aus.
        func scan(_ value: (Int) -> Float) {
            let plane = channel * height * width
            for y in 0 ..< height {
                let row = plane + y * width
                for x in 0 ..< width where value(row + x) > 0 {
                    inside[y * width + x] = 255
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        switch masks.dataType {
        case .float16:
            masks.withUnsafeBufferPointer(ofType: Float16.self) { buffer in
                scan { Float(buffer[$0]) }
            }
        case .float32:
            masks.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                scan { buffer[$0] }
            }
        case .double:
            masks.withUnsafeBufferPointer(ofType: Double.self) { buffer in
                scan { Float($0 < 0 ? 0 : buffer[$0]) }
            }
        default:
            return nil
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let box = CGRect(x: CGFloat(minX) / CGFloat(width),
                         y: CGFloat(minY) / CGFloat(height),
                         width: CGFloat(maxX - minX + 1) / CGFloat(width),
                         height: CGFloat(maxY - minY + 1) / CGFloat(height))
        return SegmentedObject(id: UUID(), box: box,
                               mask: image(from: inside, width: width, height: height),
                               bits: inside, side: width)
    }

    /// Der Umriss als Bild mit Alphakanal, zum Darueberlegen.
    private static func image(from pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0 ..< width * height where pixels[i] > 0 {
            data[i * 4 + 0] = 255
            data[i * 4 + 1] = 255
            data[i * 4 + 2] = 255
            data[i * 4 + 3] = 110
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8,
                               bitsPerPixel: 32, bytesPerRow: width * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
