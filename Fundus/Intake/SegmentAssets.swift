import Foundation

/// Segment Anything 2.1 Tiny: the model for tapping.
///
/// Not in the bundle, and that is the same line as everywhere in these apps: the IPA is
/// 1.7 MB, the model is 80. Whoever downloads Fundus to write down a drawer should not
/// have to drag eighty megabytes of weights along that they may never use.
///
/// Apple converted this version to Core ML themselves, in float16, under Apache-2.0,
/// and HuggingFace has a Swift app to go with it, which is where the input and output
/// names come from. The faster derivatives fail on something other than the technology:
/// EdgeSAM is under a licence without commercial use, Ultralytics under AGPL-3.0.
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
