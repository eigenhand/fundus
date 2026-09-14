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

/// Segment Anything 3.1: das Modell fuer die Textsuche.
///
/// Der Unterschied zu SAM 2.1 ist nicht die Genauigkeit, sondern die Frage. SAM 2.1
/// beantwortet „was liegt hier, wo ich hintippe". SAM 3.1 beantwortet „wo sind die
/// Schrauben" — offener Wortschatz, ein Satz als Eingabe, bis zu zweihundert Treffer
/// mit Kasten und Maske.
///
/// Der Preis steht offen daneben und ist kein Detail:
///
///  - **1,7 GB** statt 80 MB. Ueber Mobilfunk ist das eine Entscheidung, kein Klick.
///  - Meta gibt die Gewichte nur nach Antrag heraus (`gated: manual`, HTTP 401). Was
///    hier geladen wird, ist die Core-ML-Umsetzung einer Privatperson — offen
///    erreichbar, aber ohne Zusage, dass sie morgen noch dasteht.
///  - Die SAM License ist nicht OSI-anerkannt und hat Nutzungsbeschraenkungen. Fundus
///    verteilt nichts davon: geladen wird zur Laufzeit, auf Wunsch des Nutzers.
///
/// Die Ein- und Ausgaben sind in der Umsetzung teils unbenannt (`var_4734`), es gibt
/// keine Dokumentation und keinen Referenzcode. Beides — die Zuordnung der
/// Merkmalskarten ueber ihre Formen und die Bedeutung der drei Ausgaben — ist
/// gemessen und nicht geraten: gegen ein echtes Foto mit dem Wort „flower" kommt ein
/// Treffer mit 0,908 heraus, und die Maske liegt auf der Bluete.
enum Sam3Assets {

    static let vocabularyFile = "clip_vocab.json"
    static let mergesFile = "clip_merges.txt"

    static let model = RemoteModel(
        folder: "sam3",
        source: "https://huggingface.co/AllanVester/SAM3.1-CoreML-FP16/resolve/main/",
        files: [
            "SAM3.1_ImageEncoder_FP16.mlpackage/Manifest.json",
            "SAM3.1_ImageEncoder_FP16.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            "SAM3.1_ImageEncoder_FP16.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            "SAM3.1_TextEncoder_FP16.mlpackage/Manifest.json",
            "SAM3.1_TextEncoder_FP16.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            "SAM3.1_TextEncoder_FP16.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            "SAM3.1_Detector_FP16.mlpackage/Manifest.json",
            "SAM3.1_Detector_FP16.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            "SAM3.1_Detector_FP16.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
        ],
        approximateBytes: 1_700_000_000)

    /// Die CLIP-Tabellen kommen von OpenAI und nicht aus dem Modellordner: Metas
    /// eigene liegen hinter derselben Sperre wie die Gewichte, und der Textturm ist
    /// wortwoertlich CLIPs — `vocab_size 49408`.
    static let tokenizer = RemoteModel(
        folder: "sam3",
        source: "https://huggingface.co/openai/clip-vit-base-patch32/resolve/main/",
        files: ["vocab.json", "merges.txt"],
        approximateBytes: 1_600_000)

    static var looksInstalled: Bool {
        model.looksInstalled
            && FileManager.default.fileExists(atPath: url(for: vocabularyFile).path)
            && FileManager.default.fileExists(atPath: url(for: mergesFile).path)
    }

    static var compiledDirectory: URL { model.compiledDirectory }
    static func url(for file: String) -> URL { model.url(for: file) }

    static var encoderPackage: URL { url(for: "SAM3.1_ImageEncoder_FP16.mlpackage") }
    static var textPackage: URL { url(for: "SAM3.1_TextEncoder_FP16.mlpackage") }
    static var detectorPackage: URL { url(for: "SAM3.1_Detector_FP16.mlpackage") }

    /// Beides laden: erst die kleinen Tabellen, dann die Gewichte.
    static func download(onProgress: @escaping @Sendable (RemoteModel.Progress) -> Void) async {
        await tokenizer.download { _ in }   // klein genug, um ohne Fortschritt zu laufen
        guard tokenizer.looksInstalled || looksInstalled else {
            onProgress(.failed("Die Wortliste fuer die Textsuche kam nicht an."))
            return
        }
        // Unter den Namen ablegen, unter denen der Tokenizer sie sucht.
        let mapping = [("vocab.json", vocabularyFile), ("merges.txt", mergesFile)]
        for (from, to) in mapping where from != to {
            let source = url(for: from), target = url(for: to)
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.moveItem(at: source, to: target)
            }
        }
        await model.download(onProgress: onProgress)
    }
}
