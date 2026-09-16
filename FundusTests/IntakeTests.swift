import XCTest
@testable import Fundus

/// What becomes of a model's answer.
///
/// The answer comes from an arbitrary model, and the deviations here are not invented
/// cases: quantities as strings, decimals, `null`, the same thing named twice, JSON in
/// a code block. Each of them has cost a paid shot somewhere at some point.
final class IntakeTests: XCTestCase {

    private func parse(_ json: String) -> IntakeResult {
        guard let object = JSONSnippet.firstObject(in: json) else {
            XCTFail("Kein JSON-Objekt gefunden in: \(json)")
            return IntakeResult()
        }
        return PhotoIntake.parse(object)
    }

    func testPlainResponse() {
        let result = parse("""
        {"items": [{"name": "USB-C-Kabel", "quantity": 3, "unit": "", "note": "schwarz"},
                   {"name": "Acryllack weiß", "quantity": null, "unit": "Dose", "note": ""}],
         "unreadable": ["eine graue Schachtel, Aufschrift unscharf"]}
        """)

        XCTAssertEqual(result.proposals.count, 2)
        XCTAssertEqual(result.proposals[0].quantity, 3)
        XCTAssertEqual(result.proposals[0].note, "schwarz")
        XCTAssertNil(result.proposals[1].quantity, "`null` heißt ungezählt, nicht null Stück.")
        XCTAssertEqual(result.proposals[1].unit, "Dose")
        XCTAssertEqual(result.unreadable.count, 1)
    }

    /// Models do not reliably keep to "answer with JSON only". Losing a shot to a code
    /// block would be a paid call for nothing.
    func testJSONInsideCodeFence() {
        let result = parse("""
        Hier ist der Bestand:

        ```json
        {"items": [{"name": "Hammer", "quantity": 1}], "unreadable": []}
        ```

        Mehr war nicht zu erkennen.
        """)
        XCTAssertEqual(result.proposals.count, 1)
        XCTAssertEqual(result.proposals[0].name, "Hammer")
    }

    func testQuantityAsString() {
        let result = parse(#"{"items": [{"name": "Dose", "quantity": "8"}]}"#)
        XCTAssertEqual(result.proposals[0].quantity, 8)
    }

    /// A decimal as a piece count is a misunderstanding on the model's part. Truncated
    /// rather than rounded: 2.7 tins become 2 certain ones, not 3 asserted ones.
    func testFractionalQuantityTruncates() {
        let result = parse(#"{"items": [{"name": "Dose", "quantity": 2.7}]}"#)
        XCTAssertEqual(result.proposals[0].quantity, 2)
    }

    func testZeroAndNegativeQuantityBecomeUncounted() {
        let result = parse(#"{"items": [{"name": "A", "quantity": 0}, {"name": "B", "quantity": -3}]}"#)
        XCTAssertNil(result.proposals[0].quantity, "Null Stück ist kein Bestand, sondern keine Zählung.")
        XCTAssertNil(result.proposals[1].quantity)
    }

    /// Two compartments, one glance: the model sometimes names the same thing twice. In
    /// the checking step the user should see things, not rows.
    func testDuplicateNamesInOneResponseAreMerged() {
        let result = parse("""
        {"items": [{"name": "Schraube 4×40", "quantity": 12},
                   {"name": "schraube 4×40", "quantity": 8, "note": "verzinkt"}]}
        """)
        XCTAssertEqual(result.proposals.count, 1)
        XCTAssertEqual(result.proposals[0].quantity, 20)
        XCTAssertEqual(result.proposals[0].note, "verzinkt",
                       "Die Notiz des zweiten Fundes geht nicht verloren.")
    }

    func testItemWithoutNameIsDropped() {
        let result = parse(#"{"items": [{"quantity": 4}, {"name": "  ", "quantity": 1}, {"name": "Zange"}]}"#)
        XCTAssertEqual(result.proposals.count, 1, "Ein Eintrag ohne Namen ist kein Eintrag.")
        XCTAssertEqual(result.proposals[0].name, "Zange")
    }

    func testEmptyResponse() {
        let result = parse(#"{"items": [], "unreadable": []}"#)
        XCTAssertTrue(result.isEmpty)
    }

    func testMissingKeysAreTolerated() {
        let result = parse(#"{"foo": "bar"}"#)
        XCTAssertTrue(result.isEmpty)
    }

    func testUnreadableIsCleaned() {
        let result = parse("""
        {"items": [], "unreadable": ["  drei Fläschchen ohne Etikett  ", "", 42]}
        """)
        XCTAssertEqual(result.unreadable, ["drei Fläschchen ohne Etikett"])
    }

    /// Every suggestion arrives ticked: nodding through is the normal case, striking
    /// out the exception. A list with forty empty boxes gets used once.
    func testProposalsArriveAccepted() {
        let result = parse(#"{"items": [{"name": "A"}, {"name": "B"}]}"#)
        XCTAssertTrue(result.proposals.allSatisfy(\.accepted))
    }

    // MARK: Der Prompt

    /// The existing names are capped, because a list of two hundred dominates the
    /// prompt and the model starts copying out of it.
    func testPromptCapsExistingNames() {
        let many = (1 ... 120).map { "Ding \($0)" }
        let message = IntakePrompt.message(placePath: "Keller", existingNames: many, hint: "")

        XCTAssertTrue(message.contains("Keller"))
        XCTAssertTrue(message.contains("- Ding 1"))
        XCTAssertFalse(message.contains("- Ding 41"), "Nach 40 Namen ist Schluss.")
        XCTAssertTrue(message.contains("80 weitere"))
    }

    func testPromptCarriesHint() {
        let message = IntakePrompt.message(placePath: nil, existingNames: [],
                                           hint: "Das sind alles Lackdosen.")
        XCTAssertTrue(message.contains("Das sind alles Lackdosen."))
    }

    func testPromptWithoutContextIsStillAQuestion() {
        let message = IntakePrompt.message(placePath: nil, existingNames: [], hint: "   ")
        XCTAssertFalse(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(message.contains("Hinweis vom Nutzer"))
    }
}
