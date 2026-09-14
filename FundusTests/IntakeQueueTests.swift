import XCTest
@testable import Fundus

/// Die Reihe und ihre Arbeiter.
///
/// Geprüft wird hier fast nur eine Funktion, und die lohnt jede Zeile: an ihr hängt,
/// wie viele bezahlte Aufrufe gleichzeitig unterwegs sind. Zu viele kosten Geld und
/// holen eine Drosselung, zu wenige lassen den Nutzer warten — und ein Auftrag, der
/// im Prüfschritt liegen bleibt, darf keinen Arbeiter festhalten, sonst blockiert ein
/// Foto, das jemand liegen lässt, den ganzen Rest.
@MainActor
final class IntakeQueueTests: XCTestCase {

    private typealias Phase = IntakeJob.Phase

    // MARK: Wer als Nächstes darf

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

    /// Der Kern der Sache: ein fertiger Auftrag wartet auf den Menschen, nicht auf
    /// Rechenzeit. Hielte er einen Arbeiter, würde ein Foto, das jemand offen lässt,
    /// die Reihe anhalten — und genau das soll die Reihe ja verhindern.
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

    /// Eine 0 aus einer kaputten Ablage hieße „nie wieder ein Foto lesen“, eine 99
    /// wäre ein Schwarm auf den Anbieter.
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

    /// Ein Foto ohne Bestand ist kein Fehlschlag. Beides gleich zu zeigen bringt dem
    /// Nutzer bei, das rote Zeichen zu übersehen — und dann sieht er den echten
    /// Fehlschlag auch nicht mehr.
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

    /// Zwölf Handyfotos in voller Auflösung sind einige hundert Megabyte, für Pixel,
    /// die weder das Modell noch der Beleg je sieht.
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

    /// Der Knopf im Prüfschritt hiess „Nichts übernehmen" und war abgeschaltet. Wer
    /// alles abwählte, um die Aufnahme loszuwerden, sass fest.
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
        XCTAssertEqual(j.commitAction.label, "Aufnahme verwerfen",
                       "Die Beschriftung muss sagen, was der Knopf tut.")
    }

    /// Auch eine Aufnahme ganz ohne Vorschläge muss sich wegtippen lassen.
    func testAnEmptyResultCanBeDiscarded() {
        let j = job()
        j.phase = .review
        XCTAssertEqual(j.commitAction, .discard)
    }

    // MARK: Der Sucher

    /// Wer einen Keller abgeht, stellt einmal auf Doku und will das nicht bei jedem
    /// Regal wieder tun.
    func testCaptureModeIsRemembered() throws {
        var settings = AppSettings()
        XCTAssertEqual(settings.captureMode, .single, "Das gewohnte Verhalten ist die Vorgabe.")

        settings.captureMode = .doku
        let encoder = JSONEncoder()
        let back = try JSONDecoder().decode(AppSettings.self, from: try encoder.encode(settings))
        XCTAssertEqual(back.captureMode, .doku)
    }

    /// Ein Bestand aus der Zeit vor dem Sucher, und eine Ablage mit einem Modus, den
    /// es nicht gibt — beides darf nicht dazu führen, dass die App nicht startet.
    ///
    /// Der zweite Fall war es, der den Fehler in `decodeIfPresent` ans Licht gebracht
    /// hat: er warf, statt auf die Vorgabe zu fallen, und riss die ganze Datei mit.
    func testUnknownOrMissingCaptureModeFallsBack() throws {
        func decode(_ json: String) throws -> AppSettings {
            try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode("{}").captureMode, .single)
        XCTAssertEqual(try decode(#"{"captureMode":"zeitraffer"}"#).captureMode, .single)

        // Und der eigentliche Punkt: der Rest der Datei überlebt es.
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
