import XCTest
@testable import Fundus

/// Die Zerlegung in Token-Nummern.
///
/// Alle Erwartungen unten stammen aus einer Referenzimplementierung von CLIPs
/// Byte-Paar-Kodierung und nicht aus dem Kopf. Der Grund steht in der Messung, die
/// diesen Test ausgeloest hat: 3739 statt 4055 geschickt und damit nach „halloween"
/// gesucht statt nach „flower" — Score 0,004 statt 0,908. Ein Token daneben ist nicht
/// ein bisschen daneben.
final class ClipTokenizerTests: XCTestCase {

    private func tokenizer() throws -> ClipTokenizer {
        let vocabulary = Sam3Assets.url(for: Sam3Assets.vocabularyFile)
        let merges = Sam3Assets.url(for: Sam3Assets.mergesFile)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: vocabulary.path)
                          && FileManager.default.fileExists(atPath: merges.path),
                          "Die Tabellen liegen nicht auf diesem Geraet.")
        return try ClipTokenizer(vocabulary: vocabulary, merges: merges)
    }

    private func ids(_ t: ClipTokenizer, _ text: String) -> [Int32] {
        t.encode(text).filter { $0 != 0 }
    }

    func testSingleWords() throws {
        let t = try tokenizer()
        XCTAssertEqual(ids(t, "flower"), [49406, 4055, 49407])
        XCTAssertEqual(ids(t, "motor"), [49406, 7659, 49407])
        XCTAssertEqual(ids(t, "screw"), [49406, 14225, 49407])
    }

    func testGermanAndCompoundWords() throws {
        let t = try tokenizer()
        XCTAssertEqual(ids(t, "stepper motor"), [49406, 795, 2440, 7659, 49407])
        XCTAssertEqual(ids(t, "Schrauben"), [49406, 844, 27744, 3518, 49407])
        XCTAssertEqual(ids(t, "wago klemme"), [49406, 86, 1468, 7612, 13105, 49407])
    }

    /// Umlaute gehen als zwei Bytes durch die Ersatztabelle. Wer sie als ein Zeichen
    /// behandelt, bekommt eine andere Zerlegung und sucht nach etwas anderem.
    func testUmlautsGoThroughTheByteTable() throws {
        let t = try tokenizer()
        XCTAssertEqual(ids(t, "Öse"), [49406, 7255, 611, 49407])
        XCTAssertEqual(ids(t, "grüne kiste"), [49406, 709, 6522, 1422, 848, 2686, 49407])
        XCTAssertEqual(ids(t, "Schrauben für Möbel"),
                       [49406, 844, 27744, 3518, 69, 6522, 337, 76, 7255, 3543, 49407])
    }

    /// Ziffern stehen einzeln. „M4" ist deshalb „m" und „4" — so hat CLIP es gelernt.
    func testDigitsStandAlone() throws {
        let t = try tokenizer()
        XCTAssertEqual(ids(t, "M4 Schraube"), [49406, 332, 275, 844, 27744, 655, 49407])
    }

    /// Satzzeichen sind eigene Token und fallen nicht weg.
    ///
    /// Diese Erwartung ist die einzige, die nicht aus der Referenz stammt — sie war
    /// dort falsch. Das Muster, mit dem ich sie nachgebaut hatte, ergab in Python eine
    /// kaputte Zeichenklasse (`[^\s^\W\d_0-9]+`), die Satzzeichen gar nicht treffen
    /// konnte, und liess das Komma stillschweigend verschwinden. Im Wortschatz steht
    /// es aber: `,</w>` ist 267.
    func testPunctuationIsItsOwnToken() throws {
        let t = try tokenizer()
        XCTAssertEqual(ids(t, "kabel, stecker"), [49406, 1595, 3543, 267, 522, 40890, 49407])
    }

    func testAlwaysExactlyThirtyTwoNumbers() throws {
        let t = try tokenizer()
        XCTAssertEqual(t.encode("motor").count, 32)
        XCTAssertEqual(t.encode("").count, 32)
        let long = String(repeating: "schraube mutter scheibe ", count: 20)
        let encoded = t.encode(long)
        XCTAssertEqual(encoded.count, 32)
        XCTAssertEqual(encoded.last, 49407, "Abgeschnitten heisst nicht: ohne Schluss.")
    }

    func testEmptyTextIsJustTheMarkers() throws {
        let t = try tokenizer()
        XCTAssertEqual(ids(t, "   "), [49406, 49407])
    }

    // MARK: Die Bytetabelle

    func testByteTableCoversEveryByte() {
        let map = ClipTokenizer.bytesToUnicode()
        XCTAssertEqual(map.count, 256, "Jedes Byte braucht ein Zeichen.")
        XCTAssertEqual(Set(map.values).count, 256, "Und jedes ein eigenes.")
        XCTAssertEqual(map[UInt8(ascii: "a")], "a")
        XCTAssertEqual(map[0], "Ā", "Die Steuerzeichen weichen auf den Bereich ab 256 aus.")
    }
}
