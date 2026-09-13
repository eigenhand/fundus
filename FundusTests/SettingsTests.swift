import XCTest
@testable import Fundus

/// Die Einstellungen, vor allem das Token-Limit.
///
/// Das ist die Stelle, die den ersten Testflug gekostet hat: 4 000 Ausgabetoken
/// reichten einem Reasoning-Modell nicht, um über ein Foto nachzudenken *und*
/// danach noch JSON zu schreiben. Herausgekommen ist eine leere Antwort.
final class SettingsTests: XCTestCase {

    private func decode(_ json: String) throws -> ModelConfig {
        try JSONDecoder().decode(ModelConfig.self, from: Data(json.utf8))
    }

    /// Wer die App vor der Korrektur benutzt hat, hat 4 000 gespeichert liegen. Ohne
    /// Wanderung bekäme er nach dem Update denselben Fehlschlag wieder — die neue
    /// Voreinstellung greift ja nur, wo gar nichts steht.
    func testStoredOldDefaultIsRaised() throws {
        let config = try decode(#"{"maxOutputTokens":4000}"#)
        XCTAssertEqual(config.maxOutputTokens, 32_000)
    }

    func testMissingValueGetsDefault() throws {
        XCTAssertEqual(try decode("{}").maxOutputTokens, 32_000)
    }

    /// Eine selbst gesetzte Zahl bleibt, auch eine kleine — nur die eine alte
    /// Voreinstellung wird angefasst.
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

    /// Der Unterschied, um den es geht: „leer" schickt den Nutzer auf Fehlersuche,
    /// „abgeschnitten" sagt ihm, welche Zahl er ändern muss.
    func testTruncatedErrorNamesTheLimit() {
        let text = ModelError.truncated(limit: 4000, reasoningChars: 5200).errorDescription ?? ""
        XCTAssertTrue(text.contains("4000"))
        XCTAssertTrue(text.contains("5200"))
        XCTAssertTrue(text.contains("Ausgabetoken"))
    }

    func testReasoningOnlyErrorIsDistinct() {
        let text = ModelError.reasoningOnly(chars: 900).errorDescription ?? ""
        XCTAssertTrue(text.contains("900"))
        XCTAssertNotEqual(text, ModelError.emptyAnswer.errorDescription)
    }
}
