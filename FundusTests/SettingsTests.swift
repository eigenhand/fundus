import XCTest
@testable import Fundus

/// The settings, above all the token limit.
///
/// This is the spot that cost the first test flight: 4,000 output tokens were not
/// enough for a reasoning model to think about a photo *and* write JSON afterwards.
/// What came out was an empty answer.
final class SettingsTests: XCTestCase {

    private func decode(_ json: String) throws -> ModelConfig {
        try JSONDecoder().decode(ModelConfig.self, from: Data(json.utf8))
    }

    /// Whoever used the app before the fix has 4,000 stored. Without a migration they
    /// would get the same failure back after the update — the new default only applies
    /// where nothing stands at all.
    func testStoredOldDefaultIsRaised() throws {
        let config = try decode(#"{"maxOutputTokens":4000}"#)
        XCTAssertEqual(config.maxOutputTokens, 32_000)
    }

    func testMissingValueGetsDefault() throws {
        XCTAssertEqual(try decode("{}").maxOutputTokens, 32_000)
    }

    /// A number set by hand stays, even a small one — only the one old default gets
    /// touched.
    func testDeliberateValueSurvives() throws {
        XCTAssertEqual(try decode(#"{"maxOutputTokens":800}"#).maxOutputTokens, 800)
        XCTAssertEqual(try decode(#"{"maxOutputTokens":64000}"#).maxOutputTokens, 64_000)
    }

    func testEndpointAssembly() throws {
        var c = ModelConfig()
        c.baseURL = "https://api.tensorx.ai/"
        XCTAssertEqual(c.endpointURL?.absoluteString,
                       "https://api.tensorx.ai/v1/chat/completions",
                       "Ein Schrägstrich zu viel darf die Adresse nicht zerlegen.")
        XCTAssertFalse(c.isComplete, "Ohne Modellnamen ist nichts eingerichtet.")
        c.model = "z-ai/glm-5.3-flash"
        XCTAssertTrue(c.isComplete)
    }

    // MARK: Fehlertexte

    /// The difference that matters: "empty" sends the user hunting for a fault,
    /// "truncated" tells them which number to change.
    ///
    /// What gets checked are the numbers and not the wording. Since the error texts go
    /// through the string catalogue, the sentence hangs on the language of the device —
    /// on an English simulator it read "output tokens" here, and the test was red even
    /// though the code was right. The numbers are what this is about anyway.
    func testTruncatedErrorNamesTheLimit() {
        let text = ModelError.truncated(limit: 4000, reasoningChars: 5200).errorDescription ?? ""
        // `4000.formatted()` and not "4000": since the message goes through the string
        // catalogue, the interpolation inserts the language's thousands separator — in
        // English "4,000", in German "4.000". That is proper prose and not a bug, but a
        // test looking for the bare row of digits no longer finds it.
        XCTAssertTrue(text.contains(4000.formatted()), text)
        XCTAssertTrue(text.contains(5200.formatted()), text)
    }

    func testReasoningOnlyErrorIsDistinct() {
        let text = ModelError.reasoningOnly(chars: 900).errorDescription ?? ""
        XCTAssertTrue(text.contains("900"))
        XCTAssertNotEqual(text, ModelError.emptyAnswer.errorDescription)
    }
}
