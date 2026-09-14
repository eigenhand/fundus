import CoreML
import UIKit

/// Ein Treffer der Textsuche im Bild.
struct FoundByName: Identifiable, Equatable, Sendable {
    let id: Int
    /// In Bildkoordinaten, 0…1, Ursprung oben links.
    let box: CGRect
    let score: Double
    let mask: UIImage?
}

/// „Wo sind die Schrauben?" — Segment Anything 3.1 auf dem Gerät.
///
/// SAM 2.1 beantwortet, was an der Stelle liegt, auf die man tippt. Das hier
/// beantwortet eine andere Frage: ein Wort hinein, und heraus kommen alle Stellen im
/// Bild, auf die es passt. Für einen Bestand ist das die nützlichere Frage — man
/// weiß, was man sucht, und nicht, wo es liegt.
///
/// Alles unten ist gemessen und nicht der Dokumentation entnommen, weil es keine
/// gibt: die Umsetzung nach Core ML stammt von einer Privatperson, ihre Ausgaben
/// heißen `var_4734`, und Metas eigene Gewichte liegen hinter einem Antrag. Woher die
/// Zahlen stammen, steht jeweils daneben.
actor Sam3Finder {

    /// 1008 = 72 Felder à 14 Pixel. Steht so in `vision_config.backbone_config`.
    static let side = 1_008
    /// Die Maske kommt in dieser Auflösung; `low_res_mask_size` in der Konfiguration.
    static let maskSide = 288
    /// So viele Anfragen stellt der Detektor je Bild, ob man will oder nicht.
    static let queries = 200

    /// `score_threshold_detection` aus der Konfiguration.
    static let scoreThreshold = 0.5
    /// `det_nms_thresh`. Niedrig heißt: streng aussortieren.
    static let nmsThreshold = 0.1

    enum Failure: Error, Equatable {
        case notInstalled
        case broken(String)
    }

    private var encoder: MLModel?
    private var textEncoder: MLModel?
    private var detector: MLModel?
    private var tokenizer: ClipTokenizer?

    /// Die Merkmalskarten des zuletzt kodierten Fotos. Der teure Teil, einmal je Bild.
    private var features: [String: MLMultiArray] = [:]

    // MARK: Laden

    func load() throws {
        guard encoder == nil else { return }
        guard Sam3Assets.looksInstalled else { throw Failure.notInstalled }
        do {
            encoder = try model(Sam3Assets.encoderPackage, named: "sam3-encoder")
            textEncoder = try model(Sam3Assets.textPackage, named: "sam3-text")
            detector = try model(Sam3Assets.detectorPackage, named: "sam3-detector")
            tokenizer = try ClipTokenizer(
                vocabulary: Sam3Assets.url(for: Sam3Assets.vocabularyFile),
                merges: Sam3Assets.url(for: Sam3Assets.mergesFile))
        } catch {
            encoder = nil; textEncoder = nil; detector = nil; tokenizer = nil
            throw Failure.broken(error.localizedDescription)
        }
    }

    private func model(_ package: URL, named name: String) throws -> MLModel {
        let compiled = Sam3Assets.compiledDirectory
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

    // MARK: Das Bild

    /// Der teure Schritt, einmal je Foto. Danach kostet jede weitere Suche nur noch
    /// den Textturm und den Detektor.
    func encode(_ image: UIImage) throws {
        try load()
        guard let encoder else { throw Failure.broken("Kein Kodierer.") }
        guard let pixels = Self.pixels(from: image) else {
            throw Failure.broken("Das Bild liess sich nicht aufbereiten.")
        }
        let output = try encoder.prediction(
            from: MLDictionaryFeatureProvider(dictionary: ["image": pixels]))

        // Die Zuordnung steht nicht in der Umsetzung — die Ausgaben heissen `x_495`
        // und `const_762`. Die Formen erzwingen sie: 288 → 144 → 72 ist die
        // Merkmalspyramide, und von den beiden Karten mit 72 Feldern ist die aus der
        // Pyramide `x_499`, die andere die Ortskodierung. Nachgemessen: mit dieser
        // Zuordnung kommt auf einem Blumenfoto bei „flower" 0,908 heraus.
        for name in ["x_495", "x_497", "x_499", "const_762"] {
            guard let value = output.featureValue(for: name)?.multiArrayValue else {
                throw Failure.broken("Der Kodierer lieferte \(name) nicht.")
            }
            features[name] = value
        }
    }

    func forget() { features.removeAll() }

    /// Auf 1008×1008 gestreckt, dann `(x/255 − 0,5) / 0,5`.
    ///
    /// Wörtlich die Vorverarbeitung aus `sam3_image_processor.py`: `Resize((1008,
    /// 1008))`, `ToDtype(float32, scale=True)`, `Normalize(mean=0.5, std=0.5)`.
    /// Gestreckt und nicht beschnitten — sonst zeigt ein Kasten aus der Antwort auf
    /// eine andere Stelle im Foto.
    static func pixels(from image: UIImage) -> MLMultiArray? {
        guard let cg = image.cgImage else { return nil }
        let side = Self.side
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        rgba.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        }

        guard let array = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float16)
        else { return nil }

        array.withUnsafeMutableBufferPointer(ofType: Float16.self) { buffer, _ in
            let plane = side * side
            for y in 0 ..< side {
                for x in 0 ..< side {
                    let source = (y * side + x) * 4
                    for c in 0 ..< 3 {
                        let v = Float(rgba[source + c]) / 255
                        buffer[c * plane + y * side + x] = Float16((v - 0.5) / 0.5)
                    }
                }
            }
        }
        return array
    }

    // MARK: Die Suche

    func find(_ phrase: String) throws -> [FoundByName] {
        guard let textEncoder, let detector, let tokenizer, !features.isEmpty else {
            throw Failure.broken("Es ist kein Foto kodiert.")
        }
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let ids = tokenizer.encode(trimmed)
        guard let tokens = try? MLMultiArray(shape: [1, NSNumber(value: ClipTokenizer.contextLength)],
                                             dataType: .int32) else {
            throw Failure.broken("Die Anfrage liess sich nicht kodieren.")
        }
        for (i, id) in ids.enumerated() { tokens[i] = NSNumber(value: id) }

        let text = try textEncoder.prediction(
            from: MLDictionaryFeatureProvider(dictionary: ["token_ids": tokens]))
        guard let textFeatures = text.featureValue(for: "var_2489")?.multiArrayValue,
              let textMask = text.featureValue(for: "var_5")?.multiArrayValue else {
            throw Failure.broken("Der Textturm lieferte nichts.")
        }

        let detected = try detector.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "fpn_feat0": features["x_495"]!,
            "fpn_feat1": features["x_497"]!,
            "fpn_feat2": features["x_499"]!,
            "vis_pos": features["const_762"]!,
            "text_features": textFeatures,
            "text_mask": textMask,
        ]))
        guard let boxes = detected.featureValue(for: "var_4734")?.multiArrayValue,
              let scores = detected.featureValue(for: "var_4806")?.multiArrayValue,
              let masks = detected.featureValue(for: "var_5020")?.multiArrayValue else {
            throw Failure.broken("Der Detektor lieferte nichts.")
        }
        return Self.results(boxes: boxes, scores: scores, masks: masks)
    }

    // MARK: Aus zweihundert Anfragen Treffer machen

    /// Die Kästen kommen als `[Mitte-x, Mitte-y, Breite, Höhe]`, normiert — steht so
    /// im Kommentar von `sam3_image_processor.py`. Hier werden sie zu Rechtecken mit
    /// Ursprung oben links, weil die Oberfläche so rechnet.
    static func rect(cx: Double, cy: Double, w: Double, h: Double) -> CGRect {
        CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Wie stark sich zwei Kästen überschneiden.
    static func overlap(_ a: CGRect, _ b: CGRect) -> Double {
        let cut = a.intersection(b)
        guard !cut.isNull, cut.width > 0, cut.height > 0 else { return 0 }
        let shared = Double(cut.width * cut.height)
        let union = Double(a.width * a.height + b.width * b.height) - shared
        return union > 0 ? shared / union : 0
    }

    static func results(boxes: MLMultiArray, scores: MLMultiArray,
                        masks: MLMultiArray?) -> [FoundByName] {
        var kept: [FoundByName] = []
        let ranked = (0 ..< min(queries, scores.count))
            .map { ($0, scores[$0].doubleValue) }
            .filter { $0.1 >= scoreThreshold }
            .sorted { $0.1 > $1.1 }

        for (index, score) in ranked {
            let box = rect(cx: boxes[index * 4 + 0].doubleValue,
                           cy: boxes[index * 4 + 1].doubleValue,
                           w: boxes[index * 4 + 2].doubleValue,
                           h: boxes[index * 4 + 3].doubleValue)
            guard box.width > 0.004, box.height > 0.004 else { continue }
            // Zweihundert Anfragen finden dasselbe Ding mehrfach. Der beste bleibt.
            guard !kept.contains(where: { overlap($0.box, box) > nmsThreshold }) else { continue }
            kept.append(FoundByName(id: index, box: box, score: score,
                                    mask: masks.flatMap { maskImage(from: $0, query: index) }))
        }
        return kept
    }

    /// Der Umriss einer Anfrage als Bild mit Alphakanal. Werte über null gehören dazu.
    static func maskImage(from masks: MLMultiArray, query: Int) -> UIImage? {
        let side = maskSide
        guard masks.count >= (query + 1) * side * side else { return nil }
        var data = [UInt8](repeating: 0, count: side * side * 4)
        var any = false

        func paint(_ value: (Int) -> Float) {
            let plane = query * side * side
            for i in 0 ..< side * side where value(plane + i) > 0 {
                data[i * 4 + 0] = 255; data[i * 4 + 1] = 255; data[i * 4 + 2] = 255
                data[i * 4 + 3] = 110
                any = true
            }
        }
        switch masks.dataType {
        case .float16: masks.withUnsafeBufferPointer(ofType: Float16.self) { b in paint { Float(b[$0]) } }
        case .float32: masks.withUnsafeBufferPointer(ofType: Float.self) { b in paint { b[$0] } }
        default: return nil
        }
        guard any, let provider = CGDataProvider(data: Data(data) as CFData),
              let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
