import Foundation

/// Segment Anything 2.1 Tiny: das Modell fuer den Fingertipp.
///
/// Nicht ins Bundle, und das ist dieselbe Linie wie ueberall in diesen Apps: die IPA
/// ist 1,7 MB, das Modell ist 80. Wer Fundus laedt, um eine Schublade aufzuschreiben,
/// soll nicht achtzig Megabyte Gewichte mitziehen, die er vielleicht nie benutzt.
///
/// Apple hat diese Fassung selbst nach Core ML umgesetzt, in float16, unter
/// Apache-2.0, und HuggingFace hat eine Swift-App dazu, aus der die Ein- und
/// Ausgabenamen stammen. Die schnelleren Derivate scheitern an etwas anderem als der
/// Technik: EdgeSAM steht unter einer Lizenz ohne kommerzielle Nutzung, Ultralytics
/// unter AGPL-3.0.
enum SegmentAssets {

    static let model = RemoteModel(
        folder: "sam2",
        source: "https://huggingface.co/apple/coreml-sam2.1-tiny/resolve/main/",
        files: [
            "SAM2_1TinyImageEncoderFLOAT16.mlpackage/Manifest.json",
            "SAM2_1TinyImageEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            "SAM2_1TinyImageEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            "SAM2_1TinyPromptEncoderFLOAT16.mlpackage/Manifest.json",
            "SAM2_1TinyPromptEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            "SAM2_1TinyPromptEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            "SAM2_1TinyMaskDecoderFLOAT16.mlpackage/Manifest.json",
            "SAM2_1TinyMaskDecoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            "SAM2_1TinyMaskDecoderFLOAT16.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
        ],
        approximateBytes: 80_000_000)

    static var looksInstalled: Bool { model.looksInstalled }
    static var compiledDirectory: URL { model.compiledDirectory }
    static func url(for file: String) -> URL { model.url(for: file) }

    static var encoderPackage: URL { url(for: "SAM2_1TinyImageEncoderFLOAT16.mlpackage") }
    static var promptPackage: URL { url(for: "SAM2_1TinyPromptEncoderFLOAT16.mlpackage") }
    static var decoderPackage: URL { url(for: "SAM2_1TinyMaskDecoderFLOAT16.mlpackage") }
}
