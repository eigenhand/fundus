import XCTest
@testable import Fundus

/// Switching the language.
///
/// What gets checked is the mechanical part: that both languages are in the bundle and
/// that a key yields something different in each. Whether every sentence *is*
/// translated is checked by `check-localizations.py` on every push — a test cannot see
/// the source catalogue at runtime.
final class LocalizationTests: XCTestCase {

    /// The app bundle, not the test's: the catalogues belong to the app.
    private var app: Bundle {
        let here = Bundle(for: type(of: self))
        return Bundle(url: here.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Fundus.app")) ?? .main
    }

    func testBothLanguagesAreInTheBundle() {
        XCTAssertEqual(Set(app.localizations), ["de", "en"])
    }

    func testTheSameKeyReadsDifferentlyInEachLanguage() throws {
        for (key, de, en) in [("Einstellungen", "Einstellungen", "Settings"),
                              ("Orte", "Orte", "Places"),
                              ("Ohne Ort", "Ohne Ort", "No place")] {
            XCTAssertEqual(try text(key, in: "de"), de)
            XCTAssertEqual(try text(key, in: "en"), en)
        }
    }

    /// A placeholder has to survive the translation — lose one and the number is
    /// missing at runtime, gain one and the formatting crashes.
    func testPlaceholdersSurviveTranslation() throws {
        XCTAssertEqual(try text("Fotos: %@", in: "en"), "Photos: %@")
        XCTAssertEqual(try text("Im Suchindex: %@, %@ Dimensionen", in: "en"),
                       "In the search index: %@, %@ dimensions")
    }

    /// An unknown key returns itself. That is the guarantee the choice of German keys
    /// rests on: forget a sentence and you see German — not an empty line.
    func testAnUnknownKeyFallsBackToItself() throws {
        XCTAssertEqual(try text("Diesen Satz gibt es nicht", in: "en"),
                       "Diesen Satz gibt es nicht")
    }

    // MARK: Die Einstellung selbst

    func testSystemMeansTheDeviceDecides() {
        XCTAssertNil(AppLanguage.system.locale)
        XCTAssertNil(AppLanguage.system.code)
        XCTAssertEqual(AppLanguage.german.locale?.identifier, "de")
        XCTAssertEqual(AppLanguage.english.locale?.identifier, "en")
    }

    /// Every language names itself in itself — whoever does not currently understand
    /// the interface still finds the way back.
    func testEachLanguageNamesItselfInItsOwnTongue() {
        XCTAssertEqual(AppLanguage.german.label, "Deutsch")
        XCTAssertEqual(AppLanguage.english.label, "English")
    }

    func testTheSettingSurvivesADecodingRound() throws {
        var settings = AppSettings()
        settings.language = .english
        let back = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.language, .english)
    }

    /// A settings file from before this feature does not know the field.
    func testAnOlderSettingsFileDefaultsToTheDevice() throws {
        let old = Data(#"{"indexAutomatically":true}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: old).language,
                       .system)
    }

    private func text(_ key: String, in language: String) throws -> String {
        let path = try XCTUnwrap(app.path(forResource: language, ofType: "lproj"),
                                 "kein \(language).lproj im App-Bundle")
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
