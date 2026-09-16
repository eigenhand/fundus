import XCTest
@testable import Fundus

/// What happens when the provider throttles.
///
/// Newly important since shots became a queue: several calls run side by side, and
/// whoever turns the concurrency up runs into a throttle sooner. Before, the shot was
/// lost when that happened — a 429 was a failure like any other.
final class ThrottleTests: XCTestCase {

    /// "Too many requests" and "overloaded right now" are waits. A wrong key or an
    /// unknown model are not — there, waiting would only bring the same result three
    /// times over.
    func testOnlyBusyStatusesAreWaitedOut() {
        XCTAssertTrue(ModelClient.isBusy(429))
        XCTAssertTrue(ModelClient.isBusy(503))
        XCTAssertTrue(ModelClient.isBusy(529))

        XCTAssertFalse(ModelClient.isBusy(401), "Ein falscher Schluessel bleibt falsch.")
        XCTAssertFalse(ModelClient.isBusy(400))
        XCTAssertFalse(ModelClient.isBusy(404))
        XCTAssertFalse(ModelClient.isBusy(500))
    }

    /// The provider knows better than any formula — as long as the number is usable.
    func testRetryAfterWins() {
        XCTAssertEqual(ModelClient.pause(retryAfter: "5", attempt: 0), 5, accuracy: 0.001)
        XCTAssertEqual(ModelClient.pause(retryAfter: " 12 ", attempt: 1), 12, accuracy: 0.001)
    }

    /// A header saying "3600" must not stop the app for an hour.
    func testAnAbsurdRetryAfterIsCapped() {
        XCTAssertEqual(ModelClient.pause(retryAfter: "3600", attempt: 0), 30, accuracy: 0.001)
    }

    /// Without a header: two, then four seconds.
    func testWithoutAHeaderTheWaitDoubles() {
        XCTAssertEqual(ModelClient.pause(retryAfter: nil, attempt: 0), 2, accuracy: 0.001)
        XCTAssertEqual(ModelClient.pause(retryAfter: nil, attempt: 1), 4, accuracy: 0.001)
    }

    /// Some providers send a date instead of a number, some nothing sensible at all.
    /// Neither may lead to zero seconds — that would be a swarm instead of a pause.
    func testUnusableHeadersFallBackToTheFormula() {
        for header in ["Wed, 21 Oct 2026 07:28:00 GMT", "", "sofort", "0", "-5"] {
            XCTAssertEqual(ModelClient.pause(retryAfter: header, attempt: 0), 2, accuracy: 0.001,
                           "Kopf \(header.isEmpty ? "(leer)" : header)")
        }
    }

    /// Two pauses at most — six seconds are the limit of what may be sat out in
    /// silence.
    func testTheWaitingIsBounded() {
        XCTAssertEqual(ModelClient.maxWaits, 2)
        let total = (0 ..< ModelClient.maxWaits)
            .map { ModelClient.pause(retryAfter: nil, attempt: $0) }
            .reduce(0, +)
        XCTAssertEqual(total, 6, accuracy: 0.001)
    }

    /// After the pauses the message says what is going on — and what can be done about
    /// it. "HTTP 429" plus JSON would be correct and useless.
    ///
    /// What gets checked is the form and not the wording: since the move to the string
    /// catalogue the sentence follows the language of the device. What this test really
    /// asserts is that a 429 turns into a line for people and not the provider's JSON —
    /// and that it is noticeably longer than the raw status message, because it carries
    /// advice.
    func testTheMessageSaysWhatToDo() throws {
        let text = try XCTUnwrap(ModelError.http(status: 429, body: "{\"error\":{\"message\":\"rate limit exceeded\"}}").errorDescription)
        XCTAssertFalse(text.contains("{"), "Kein rohes JSON in der Zeile: \(text)")
        XCTAssertFalse(text.contains("rate limit exceeded"), text)
        XCTAssertGreaterThan(text.count, 80, "Ohne Rat wäre die Zeile kurz: \(text)")

        let other = try XCTUnwrap(ModelError.http(status: 404, body: "nope").errorDescription)
        XCTAssertTrue(other.contains("404"), "Alles andere bleibt beim rohen Befund.")
    }
}
