import CoreImage
import CoreML
import UIKit
import Vision

/// An object the user tapped in the picture.
struct SegmentedObject: Identifiable, Equatable, Sendable {
    let id: UUID
    /// In Bildkoordinaten, 0…1, Ursprung oben links.
    let box: CGRect
    /// Der Umriss zum Anzeigen.
    let mask: UIImage?
    /// The same outline as raw data, square with an edge length of `side`: 0 means
    /// outside, 255 means part of it.
    ///
    /// Kept apart from the image because something other than a display is made from
    /// it — the cut-out that goes to the model is freed along it. Reading the bits back
    /// out of a `UIImage` would work too and would be a detour through two conversions,
    /// in which interpolation and alpha channel would have to be sorted apart again.
    let bits: [UInt8]
    let side: Int
}

/// Segment Anything 2.1 on the device.
///
/// The difference from Apple's instance mask is not accuracy but who decides.
/// `VNGenerateForegroundInstanceMaskRequest` picks out for itself what counts as an
/// object in the picture, and regularly misses on a workbench — it is a model for
/// portraits and pets. SAM does not ask, it answers: the user taps a thing, and it says
/// where that thing stops.
///
/// That fits better here, because the person is standing right there anyway. They know
/// what they mean; all that is needed is the edge.
///
/// Three models, and the split is the reason this flows at all: the image encoder is
/// the expensive part and runs **once per photo**. Every further tap costs only the
/// prompt encoder and the mask decoder — twelve megabytes between them and a fraction
/// of the time.
actor Segmenter {

    /// The model expects a square. Stretched, not cropped — then converting the
    /// coordinates stays a multiplication.
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

    /// Compiles an `.mlpackage` once and keeps the result.
    ///
    /// Core ML compiles a package on load, and at 67 MB that takes noticeably long. The
    /// result lands beside the weights so that it is already there for the second photo.
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

    /// The expensive step, once per photo.
    ///
    /// `scaledDown` first, and that is not an economy measure but the correction of an
    /// error you only see on a device: a camera photo carries its rotation as a flag
    /// beside the pixels, and `cgImage` returns the **unrotated** sensor data. SwiftUI
    /// showed the picture upright, the model got it sideways — mask and display lay in
    /// two different frames, and the mask looked like a large block somewhere in the
    /// picture. `scaledDown` bakes the rotation in.
    func encode(_ image: UIImage) throws {
        try load()
        guard let encoder, let cg = image.scaledDown(maxEdge: 1_400).cgImage else {
            throw Failure.broken(String(localized: "Kein Bild."))
        }
        guard let constraint = encoder.modelDescription
            .inputDescriptionsByName["image"]?.imageConstraint else {
            throw Failure.broken(String(localized: "Der Bildkodierer nennt keine Bildgroesse."))
        }

        // Stretched rather than cropped: otherwise the tap would land somewhere else
        // and the mask would lie beside it.
        let value = try MLFeatureValue(
            cgImage: cg, constraint: constraint,
            options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": value])
        let output = try encoder.prediction(from: input)

        guard let embedded = output.featureValue(for: "image_embedding")?.multiArrayValue,
              let s0 = output.featureValue(for: "feats_s0")?.multiArrayValue,
              let s1 = output.featureValue(for: "feats_s1")?.multiArrayValue else {
            throw Failure.broken(String(localized: "Der Bildkodierer lieferte keine Einbettung."))
        }
        embedding = (embedded, s0, s1)
    }

    func forget() { embedding = nil }

    // MARK: Ein Fingertipp

    /// What lies at this spot. The point in 0…1, origin top left.
    func object(at point: CGPoint) throws -> SegmentedObject? {
        // 1 means: this point belongs to the thing. 0 would mean: it explicitly does
        // not — that would be the refinement that does not exist here yet.
        try predict([(point, 1)])
    }

    /// Label 1 means foreground. SAM also knows 0 ("not that"), 2 and 3 (the two
    /// corners of a box) — neither stands here, because nothing calls for it. The box
    /// has been measured and works; it stays out all the same, because a frame dragged
    /// by hand is precisely **not** meant to be asked about a second time, see
    /// `ObjectPicker.circle`.
    private func predict(_ prompts: [(point: CGPoint, label: Int32)]) throws -> SegmentedObject? {
        guard let promptEncoder, let decoder, let embedding else {
            throw Failure.broken(String(localized: "Es ist kein Foto kodiert."))
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
            throw Failure.broken(String(localized: "Der Prompt-Kodierer lieferte nichts."))
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
            throw Failure.broken(String(localized: "Der Maskendekodierer lieferte nichts."))
        }

        // Three proposals per tap — the whole thing, part of it, part of the part. The
        // one taken is the one the model itself trusts most.
        let best = Self.argmax(scores)
        return Self.object(from: masks, channel: best)
    }

    // MARK: Turning the mask into a box

    static func argmax(_ scores: MLMultiArray) -> Int {
        var best = 0
        var top = -Double.greatestFiniteMagnitude
        for i in 0 ..< scores.count where scores[i].doubleValue > top {
            top = scores[i].doubleValue
            best = i
        }
        return best
    }

    /// The box and the outline from a mask of shape [1, 3, H, W].
    ///
    /// The values are logits: greater than zero means "belongs to it". No threshold to
    /// adjust, because the model is trained exactly that way.
    ///
    /// `internal` and with no Core ML in its head, so that it stays testable: the same
    /// trap sits here as with the instance mask — a swapped axis delivers boxes that
    /// look plausible and lie on the wrong thing.
    static func object(from masks: MLMultiArray, channel: Int) -> SegmentedObject? {
        let shape = masks.shape.map(\.intValue)
        guard shape.count == 4, channel < shape[1] else { return nil }
        let height = shape[2], width = shape[3]
        guard height > 0, width > 0 else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        var inside = [UInt8](repeating: 0, count: width * height)

        /// Both floating-point widths, because the model is converted to float16 but
        /// its output is not necessarily. Assuming the wrong one does not read an error
        /// but nonsense — and nonsense looks like a mask.
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

    /// The outline as an image with an alpha channel, for overlaying.
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
