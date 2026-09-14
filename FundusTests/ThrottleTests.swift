import XCTest
@testable import Fundus

/// Was passiert, wenn der Anbieter drosselt.
///
/// Neu wichtig geworden, seit die Aufnahme eine Reihe ist: mehrere Aufrufe laufen
/// nebeneinander, und wer die Gleichzeitigkeit hochstellt, laeuft schneller in eine
/// Drosselung. Vorher ging dabei die Aufnahme verloren — ein 429 war ein Fehlschlag
/// wie jeder andere.
final class ThrottleTests: XCTestCase {

    /// „Zu viele Anfragen" und „gerade ueberlastet" sind Wartezeiten. Ein falscher
    /// Schluessel oder ein unbekanntes Modell sind es nicht — dort wuerde Warten nur
    /// dreimal dasselbe Ergebnis bringen.
    func testOnlyBusyStatusesAreWaitedOut() {
        XCTAssertTrue(ModelClient.isBusy(429))
        XCTAssertTrue(ModelClient.isBusy(503))
        XCTAssertTrue(ModelClient.isBusy(529))

        XCTAssertFalse(ModelClient.isBusy(401), "Ein falscher Schluessel bleibt falsch.")
        XCTAssertFalse(ModelClient.isBusy(400))
        XCTAssertFalse(ModelClient.isBusy(404))
        XCTAssertFalse(ModelClient.isBusy(500))
    }

    /// Der Anbieter weiss es besser als jede Formel — solange die Zahl brauchbar ist.
    func testRetryAfterWins() {
        XCTAssertEqual(ModelClient.pause(retryAfter: "5", attempt: 0), 5, accuracy: 0.001)
        XCTAssertEqual(ModelClient.pause(retryAfter: " 12 ", attempt: 1), 12, accuracy: 0.001)
    }

    /// Ein Kopf mit „3600" darf die App nicht fuer eine Stunde anhalten.
    func testAnAbsurdRetryAfterIsCapped() {
        XCTAssertEqual(ModelClient.pause(retryAfter: "3600", attempt: 0), 30, accuracy: 0.001)
    }

    /// Ohne Kopf: zwei, dann vier Sekunden.
    func testWithoutAHeaderTheWaitDoubles() {
        XCTAssertEqual(ModelClient.pause(retryAfter: nil, attempt: 0), 2, accuracy: 0.001)
        XCTAssertEqual(ModelClient.pause(retryAfter: nil, attempt: 1), 4, accuracy: 0.001)
    }

    /// Manche Anbieter schicken ein Datum statt einer Zahl, manche gar nichts
    /// Sinnvolles. Beides darf nicht zu null Sekunden fuehren — das waere ein
    /// Schwarm statt einer Pause.
    func testUnusableHeadersFallBackToTheFormula() {
        for header in ["Wed, 21 Oct 2026 07:28:00 GMT", "", "sofort", "0", "-5"] {
            XCTAssertEqual(ModelClient.pause(retryAfter: header, attempt: 0), 2, accuracy: 0.001,
                           "Kopf \(header.isEmpty ? "(leer)" : header)")
        }
    }

    /// Hoechstens zwei Pausen — sechs Sekunden sind die Grenze dessen, was man
    /// stillschweigend aussitzen darf.
    func testTheWaitingIsBounded() {
        XCTAssertEqual(ModelClient.maxWaits, 2)
        let total = (0 ..< ModelClient.maxWaits)
            .map { ModelClient.pause(retryAfter: nil, attempt: $0) }
            .reduce(0, +)
        XCTAssertEqual(total, 6, accuracy: 0.001)
    }

    /// Nach den Pausen sagt die Meldung, was los ist — und was man dagegen tun kann.
    /// „HTTP 429" plus JSON waere richtig und nutzlos.
    func testTheMessageSaysWhatToDo() throws {
        let text = try XCTUnwrap(ModelError.http(status: 429, body: "{\"error\":{\"message\":\"rate limit exceeded\"}}").errorDescription)
        XCTAssertTrue(text.contains("drosselt"), text)
        XCTAssertTrue(text.contains("gleichzeitig"), "Der Hebel dagegen steht in den Einstellungen.")

        let other = try XCTUnwrap(ModelError.http(status: 404, body: "nope").errorDescription)
        XCTAssertTrue(other.contains("404"), "Alles andere bleibt beim rohen Befund.")
    }
}
