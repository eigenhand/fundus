import XCTest
@testable import Fundus

/// Der Lader, gegen den echten Server.
///
/// Langsam und vom Netz abhängig, und trotzdem hier: das Fortsetzen ist die eine
/// Eigenschaft, an der dieser Lader hängt. 67 MB über Mobilfunk reissen ab, und ein
/// Verwalter, der dann bei null anfängt, ist der Unterschied zwischen „geht" und
/// „geht nie". Genau das lässt sich nicht denken, sondern nur messen.
///
/// Geladen wird das kleinste der drei Pakete — 2,1 MB, dieselbe Maschinerie.
final class RemoteModelTests: XCTestCase {

    private let model = RemoteModel(
        folder: "sam2-test",
        source: "https://huggingface.co/apple/coreml-sam2.1-tiny/resolve/main/",
        files: [
            "SAM2_1TinyPromptEncoderFLOAT16.mlpackage/Manifest.json",
            "SAM2_1TinyPromptEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel",
            "SAM2_1TinyPromptEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
        ],
        approximateBytes: 2_200_000)

    override func tearDown() {
        model.remove()
        super.tearDown()
    }

    /// `download` kehrt zurueck, wenn es fertig ist — die Meldung davor ist das
    /// Ergebnis. Kein Umweg ueber eine Fortsetzung noetig.
    private func download() async -> RemoteModel.Progress? {
        let outcome = Outcome()
        await model.download { step in outcome.record(step) }
        return outcome.last
    }

    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var value: RemoteModel.Progress?
        func record(_ step: RemoteModel.Progress) {
            guard case .downloading = step else {
                lock.lock(); value = step; lock.unlock()
                return
            }
        }
        var last: RemoteModel.Progress? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    func testDownloadsEveryFile() async throws {
        model.remove()
        let result = await download()
        try XCTSkipIf(result != .finished, "Der Server war nicht erreichbar: \(String(describing: result))")

        XCTAssertTrue(model.looksInstalled)
        XCTAssertGreaterThan(model.bytesOnDisk, 2_000_000, "Die Gewichte allein sind 2,1 MB.")
        for file in model.files {
            XCTAssertGreaterThan(RemoteModel.fileSize(model.url(for: file)) ?? 0, 0, file)
        }
    }

    /// Der Fall, um den es geht: die Verbindung riss bei der Hälfte ab.
    func testResumesAHalfLoadedFile() async throws {
        model.remove()
        let first = await download()
        try XCTSkipIf(first != .finished, "Der Server war nicht erreichbar.")

        let weights = model.url(for: model.files[2])
        let whole = try XCTUnwrap(RemoteModel.fileSize(weights))
        XCTAssertGreaterThan(whole, 1_000_000)

        // Auf die Hälfte kürzen, wie ein Abbruch es hinterlässt.
        let handle = try FileHandle(forWritingTo: weights)
        try handle.truncate(atOffset: UInt64(whole / 2))
        try handle.close()
        XCTAssertEqual(RemoteModel.fileSize(weights), whole / 2)

        let again = await download()
        XCTAssertEqual(again, .finished)
        XCTAssertEqual(RemoteModel.fileSize(weights), whole,
                       "Fortgesetzt heisst: wieder ganz, und nicht anderthalb Mal.")
    }

    /// Eine Datei, die groesser ist als erwartet, ist kaputt und nicht fertig.
    func testAnOversizedFileIsFetchedAgain() async throws {
        model.remove()
        let first = await download()
        try XCTSkipIf(first != .finished, "Der Server war nicht erreichbar.")

        let weights = model.url(for: model.files[2])
        let whole = try XCTUnwrap(RemoteModel.fileSize(weights))
        let handle = try FileHandle(forWritingTo: weights)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0, count: 4_096))
        try handle.close()

        let step = await download()
        XCTAssertEqual(step, .finished)
        XCTAssertEqual(RemoteModel.fileSize(weights), whole)
    }

    /// Was schon ganz daliegt, wird nicht noch einmal geholt.
    func testASecondRunChangesNothing() async throws {
        model.remove()
        let first = await download()
        try XCTSkipIf(first != .finished, "Der Server war nicht erreichbar.")
        let before = model.bytesOnDisk

        let step = await download()
        XCTAssertEqual(step, .finished)
        XCTAssertEqual(model.bytesOnDisk, before)
    }
}
