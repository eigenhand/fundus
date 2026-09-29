import XCTest
@testable import Fundus

/// The queue and its workers.
///
/// What gets checked here is almost one single function, and it is worth every line:
/// how many paid calls are in flight at once hangs on it. Too many cost money and earn
/// a throttle, too few keep the user waiting — and a job left lying in the checking
/// step must not hold on to a worker, or one photo somebody leaves lying blocks all the
/// rest.
@MainActor
final class IntakeQueueTests: XCTestCase {

    private typealias Phase = IntakeJob.Phase

    // MARK: Who goes next

    func testStartsUpToTheConcurrency() {
        let waiting: [Phase] = [.waiting, .waiting, .waiting, .waiting]
        XCTAssertEqual(IntakeSchedule.startable(waiting, concurrency: 2), [0, 1])
        XCTAssertEqual(IntakeSchedule.startable(waiting, concurrency: 1), [0],
                       "Eins heißt nacheinander — das alte Verhalten, auf Wunsch.")
    }

    func testRunningJobsTakeUpTheirSlots() {
        let phases: [Phase] = [.reading, .looking(done: 1, total: 3), .waiting, .waiting]
        XCTAssertTrue(IntakeSchedule.startable(phases, concurrency: 2).isEmpty,
                      "Beide Arbeiter sind belegt.")
        XCTAssertEqual(IntakeSchedule.startable(phases, concurrency: 3), [2])
    }

    /// The heart of it: a finished job waits for the person, not for processing time.
    /// If it held a worker, a photo somebody leaves open would stop the queue — which
    /// is exactly what the queue is there to prevent.
    func testFinishedJobsDoNotHoldAWorker() {
        let phases: [Phase] = [.review, .failed("kaputt"), .empty, .waiting, .waiting]
        XCTAssertEqual(IntakeSchedule.startable(phases, concurrency: 2), [3, 4])
    }

    func testOrderOfTheQueueIsKept() {
        let phases: [Phase] = [.review, .waiting, .reading, .waiting, .waiting]
        XCTAssertEqual(IntakeSchedule.startable(phases, concurrency: 3), [1, 3],
                       "Wer zuerst eingereiht wurde, läuft zuerst.")
    }

    func testNothingWaitingMeansNothingToStart() {
        XCTAssertTrue(IntakeSchedule.startable([], concurrency: 4).isEmpty)
        XCTAssertTrue(IntakeSchedule.startable([.review, .review], concurrency: 4).isEmpty)
    }

    /// A 0 out of a broken store would mean "never read a photo again", a 99 would be a
    /// swarm against the provider.
    func testConcurrencyIsClamped() {
        let waiting: [Phase] = Array(repeating: .waiting, count: 10)
        XCTAssertEqual(IntakeSchedule.startable(waiting, concurrency: 0).count, 1)
        XCTAssertEqual(IntakeSchedule.startable(waiting, concurrency: -5).count, 1)
        XCTAssertEqual(IntakeSchedule.startable(waiting, concurrency: 99).count,
                       IntakeSchedule.concurrencyRange.upperBound)
    }

    // MARK: Die Phasen

    func testOnlyReadingAndLookingAreBusy() {
        XCTAssertTrue(Phase.reading.isBusy)
        XCTAssertTrue(Phase.looking(done: 0, total: 2).isBusy)
        XCTAssertFalse(Phase.waiting.isBusy)
        XCTAssertFalse(Phase.review.isBusy)
        XCTAssertFalse(Phase.empty.isBusy)
        XCTAssertFalse(Phase.failed("x").isBusy)
    }

    /// A photo with no inventory in it is not a failure. Showing both the same way
    /// teaches the user to overlook the red mark — and then they stop seeing the real
    /// failure too.
    func testAPhotoWithoutInventoryIsNotAFailure() {
        XCTAssertNotEqual(Phase.empty, Phase.failed("Auf dem Bild war nichts Bestandsfähiges zu erkennen."))
        let j = job()
        j.phase = .empty
        XCTAssertEqual(j.badge, "\u{2013}", "Ein Strich, kein Ausrufezeichen.")
    }

    // MARK: Der Auftrag

    private func job(_ pixels: CGFloat = 3_000) -> IntakeJob {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: pixels, height: pixels * 0.75), format: format).image { ctx in
                UIColor.gray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels * 0.75))
            }
        return IntakeJob(image: image, placeID: nil, hint: "")
    }

    /// Twelve phone photos at full resolution are several hundred megabytes, for pixels
    /// that neither the model nor the evidence ever sees.
    func testImageIsScaledDownWhenQueued() {
        let j = job(3_000)
        XCTAssertLessThanOrEqual(max(j.image.size.width, j.image.size.height), 1_400)
        XCTAssertLessThanOrEqual(max(j.thumbnail.size.width, j.thumbnail.size.height), 240)
        XCTAssertGreaterThan(j.thumbnail.size.width, 0, "Das Symbol ist das Foto, nicht nichts.")
    }

    func testAJobStartsWaitingAndUnbadged() {
        let j = job()
        XCTAssertEqual(j.phase, .waiting)
        XCTAssertNil(j.badge, "Solange nichts gelesen ist, steht auch keine Zahl da.")
    }

    func testBadgeCountsProposalsWhenReady() {
        let j = job()
        j.result.proposals = [Proposal(name: "a"), Proposal(name: "b")]
        j.phase = .review
        XCTAssertEqual(j.badge, "2")

        j.phase = .failed("kaputt")
        XCTAssertEqual(j.badge, "!")
    }

    /// The button in the checking step read "take over nothing" and was disabled.
    /// Whoever unticked everything to be rid of the shot was stuck.
    func testDeselectingEverythingOffersToDiscard() {
        let j = job()
        j.result.proposals = [Proposal(name: "a"), Proposal(name: "b")]
        j.phase = .review
        XCTAssertEqual(j.commitAction, .take(2), "Angehakt ist beides — beides wird übernommen.")

        j.result.proposals[0].accepted = false
        XCTAssertEqual(j.commitAction, .take(1))

        j.result.proposals[1].accepted = false
        XCTAssertEqual(j.commitAction, .discard,
                       "Nichts anhaken heisst nicht: keine Handlung. Es heisst: weg damit.")
        XCTAssertEqual(j.commitAction.label, String(localized: "Aufnahme verwerfen"),
                       "Die Beschriftung muss sagen, was der Knopf tut.")
    }

    /// A shot with no suggestions at all has to be dismissible by tapping too.
    func testAnEmptyResultCanBeDiscarded() {
        let j = job()
        j.phase = .review
        XCTAssertEqual(j.commitAction, .discard)
    }

    // MARK: Der Sucher

    /// Whoever walks through a cellar switches to documentation once and does not want
    /// to do it again at every shelf.
    func testCaptureModeIsRemembered() throws {
        var settings = AppSettings()
        XCTAssertEqual(settings.captureMode, .single, "Das gewohnte Verhalten ist die Vorgabe.")

        settings.captureMode = .doku
        let encoder = JSONEncoder()
        let back = try JSONDecoder().decode(AppSettings.self, from: try encoder.encode(settings))
        XCTAssertEqual(back.captureMode, .doku)
    }

    /// An inventory from before the viewfinder, and a store with a mode that does not
    /// exist — neither may stop the app from starting.
    ///
    /// It was the second case that brought the bug in `decodeIfPresent` to light: it
    /// threw instead of falling back on the default, and took the whole file with it.
    func testUnknownOrMissingCaptureModeFallsBack() throws {
        func decode(_ json: String) throws -> AppSettings {
            try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode("{}").captureMode, .single)
        XCTAssertEqual(try decode(#"{"captureMode":"zeitraffer"}"#).captureMode, .single)

        // And the actual point: the rest of the file survives it.
        let mixed = try decode(#"{"captureMode":"zeitraffer","intakeConcurrency":5}"#)
        XCTAssertEqual(mixed.intakeConcurrency, 5,
                       "Ein unbekannter Modus darf nicht die übrigen Einstellungen kosten.")
    }

    func testEveryModeIsLabelledAndExplained() {
        XCTAssertEqual(CaptureMode.allCases.count, 3)
        for mode in CaptureMode.allCases {
            XCTAssertFalse(mode.label.isEmpty)
            XCTAssertFalse(mode.hint.isEmpty,
                           "Ein Wort wie Doku oder Objekte sagt niemandem, was passiert.")
        }
        XCTAssertEqual(Set(CaptureMode.allCases.map(\.label)).count, 3,
                       "Zwei gleich beschriftete Knöpfe waeren keine Auswahl.")
    }

    // MARK: Die Einstellung

    func testStoredConcurrencyIsClampedOnLoad() throws {
        func decode(_ json: String) throws -> AppSettings {
            try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode(#"{"intakeConcurrency":4}"#).intakeConcurrency, 4)
        XCTAssertEqual(try decode(#"{"intakeConcurrency":0}"#).intakeConcurrency, 1,
                       "Null hieße: nie wieder ein Foto lesen.")
        XCTAssertEqual(try decode(#"{"intakeConcurrency":50}"#).intakeConcurrency,
                       IntakeSchedule.concurrencyRange.upperBound)
        XCTAssertEqual(try decode("{}").intakeConcurrency, 2,
                       "Ein Bestand aus der Zeit vor der Reihe bekommt die Vorgabe.")
    }
}
