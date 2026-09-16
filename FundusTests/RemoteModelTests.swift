import XCTest
@testable import Fundus

/// The downloader, against the real server.
///
/// Slow and dependent on the network, and here all the same: resuming is the one
/// property this downloader hangs on. 67 MB over mobile data breaks off, and a manager
/// that then starts from zero is the difference between "works" and "never works".
/// That is precisely the kind of thing that cannot be reasoned out, only measured.
///
/// What gets downloaded is the smallest of the three packages — 2.1 MB, the same
/// machinery.
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

    /// `download` returns when it is done — the report before it is the result. No
    /// detour through a continuation needed.
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

    /// The case this is about: the connection broke off halfway.
    func testResumesAHalfLoadedFile() async throws {
        model.remove()
        let first = await download()
        try XCTSkipIf(first != .finished, "Der Server war nicht erreichbar.")

        let weights = model.url(for: model.files[2])
        let whole = try XCTUnwrap(RemoteModel.fileSize(weights))
        XCTAssertGreaterThan(whole, 1_000_000)

        // Truncate to half, the way a break-off leaves it.
        let handle = try FileHandle(forWritingTo: weights)
        try handle.truncate(atOffset: UInt64(whole / 2))
        try handle.close()
        XCTAssertEqual(RemoteModel.fileSize(weights), whole / 2)

        let again = await download()
        XCTAssertEqual(again, .finished)
        XCTAssertEqual(RemoteModel.fileSize(weights), whole,
                       "Fortgesetzt heisst: wieder ganz, und nicht anderthalb Mal.")
    }

    /// A file larger than expected is broken, not finished.
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

    /// Whatever is already there in full does not get fetched again.
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
