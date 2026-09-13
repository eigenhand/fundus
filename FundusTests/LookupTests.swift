import XCTest
@testable import Fundus

/// Kennungen und ihre Auflösung.
///
/// Die Prüfungen hier sind fast alle Verweigerungen. Das ist kein Zufall: eine
/// Websuche auf eine Nummer erzeugt einen präzisen, technisch klingenden
/// Produktnamen, der verlässlicher aussieht als alles andere im Bestand — und am
/// Ende einer Kette aus unscharfem Aufkleber, verwechselbaren Zeichen und einer
/// Suchmaschine steht, die auf jede Zeichenfolge irgendetwas antwortet. Was diese
/// Funktion nützlich macht, ist nicht, was sie findet, sondern wann sie schweigt.
final class LookupTests: XCTestCase {

    // MARK: Was überhaupt gesucht wird

    /// „M8“, „A4“, „12“ stehen auf tausend Dingen. Eine Suche darauf kostet einen
    /// Aufruf und liefert Rauschen, das danach wie ein Befund aussieht.
    func testShortOrDigitlessCodesAreNotSearched() {
        XCTAssertFalse(ItemCode(value: "M8").isSearchable)
        XCTAssertFalse(ItemCode(value: "A4").isSearchable)
        XCTAssertFalse(ItemCode(value: "Rot").isSearchable, "Ein Wort ohne Ziffer ist eine Beschriftung.")
        XCTAssertFalse(ItemCode(value: "Schraube").isSearchable)
        XCTAssertTrue(ItemCode(value: "MP1584EN").isSearchable)
        XCTAssertTrue(ItemCode(value: "4006381333931").isSearchable)
    }

    /// In Anführungszeichen, damit die Suchmaschine die Nummer nicht „korrigiert“.
    /// Eine falsch gelesene Nummer soll ins Leere laufen, nicht auf das
    /// nächstähnliche Bauteil zeigen.
    func testQueryQuotesTheCodeVerbatim() {
        let ean = ItemCode(value: "4006381333931", kind: .ean, origin: .scanned)
        XCTAssertEqual(IdentityLookup.query(for: ean, itemName: "Stift"), "\"4006381333931\"")

        let mpn = ItemCode(value: "MP1584EN", kind: .manufacturer)
        XCTAssertEqual(IdentityLookup.query(for: mpn, itemName: "Platine"),
                       "\"MP1584EN\" Platine",
                       "Bei einer Herstellernummer hilft der gesehene Gegenstand als Kontext.")
    }

    // MARK: Das Sicherheitsnetz gegen erfundene Strichcodes

    /// Einen Strichcode kann man nicht mit den Augen lesen. Nennt das Modell eine
    /// EAN, die der Dekoder nicht gesehen hat, hat es sie erfunden oder von den
    /// Ziffern darunter abgeschrieben — und dort ist eine verwechselte Ziffer nicht
    /// zu bemerken.
    func testUnscannedEANIsRejected() {
        let code = PhotoIntake.code(
            from: ["code": "4006381333931", "code_type": "ean"],
            scannedValues: [], scannedCodes: [])
        XCTAssertNil(code)
    }

    func testScannedEANIsKeptAndMarkedExact() {
        let scanned = [ItemCode(value: "4006381333931", kind: .ean, origin: .scanned)]
        let code = PhotoIntake.code(
            from: ["code": "4006381333931", "code_type": "ean"],
            scannedValues: Set(scanned.map(\.value)), scannedCodes: scanned)

        XCTAssertEqual(code?.value, "4006381333931")
        XCTAssertEqual(code?.origin, .scanned, "Was der Dekoder gesehen hat, ist belegt.")
    }

    /// Herstellernummern stehen als Klartext auf dem Bauteil. Die darf das Modell
    /// ablesen — sie bleiben aber als `read` markiert und damit als fehlbar.
    func testManufacturerNumberMayBeRead() {
        let code = PhotoIntake.code(
            from: ["code": "MP1584EN", "code_type": "mpn"],
            scannedValues: [], scannedCodes: [])
        XCTAssertEqual(code?.value, "MP1584EN")
        XCTAssertEqual(code?.kind, .manufacturer)
        XCTAssertEqual(code?.origin, .read)
    }

    func testMissingOrNullCodeIsNil() {
        XCTAssertNil(PhotoIntake.code(from: [:], scannedValues: [], scannedCodes: []))
        XCTAssertNil(PhotoIntake.code(from: ["code": "null"], scannedValues: [], scannedCodes: []))
        XCTAssertNil(PhotoIntake.code(from: ["code": "  "], scannedValues: [], scannedCodes: []))
    }

    // MARK: Wann das Nachschlagen schweigt

    /// `null` ist die richtige Antwort, wenn die Treffer nicht zur Nummer passen —
    /// und darf nicht zu einem Vorschlag aufgefüllt werden.
    func testNullTitleProducesNoLookup() {
        let hits = [SearchClient.Hit(title: "Irgendwas", url: "https://x", snippet: "", source: "x")]
        XCTAssertNil(IdentityLookup.parse(["title": NSNull()], query: "q", hits: hits))
        XCTAssertNil(IdentityLookup.parse(["title": "null"], query: "q", hits: hits))
        XCTAssertNil(IdentityLookup.parse(["title": ""], query: "q", hits: hits))
        XCTAssertNil(IdentityLookup.parse([:], query: "q", hits: hits))
    }

    func testLookupKeepsQueryAndSource() {
        let hits = [SearchClient.Hit(title: "MP1584EN Datenblatt",
                                     url: "https://example.org/mp1584",
                                     snippet: "3A Abwärtswandler", source: "example.org")]
        let lookup = IdentityLookup.parse(
            ["title": "MP1584EN DC-DC-Abwärtswandler 3 A",
             "summary": "Schaltregler-Modul.",
             "source": "https://example.org/mp1584",
             "confident": true],
            query: "\"MP1584EN\" Platine", hits: hits)

        XCTAssertEqual(lookup?.title, "MP1584EN DC-DC-Abwärtswandler 3 A")
        XCTAssertEqual(lookup?.query, "\"MP1584EN\" Platine",
                       "Wonach gesucht wurde, muss am Eintrag stehen — sonst ist die Kette nicht zurückverfolgbar.")
        XCTAssertEqual(lookup?.sourceName, "example.org")
        XCTAssertEqual(lookup?.confident, true)
    }

    /// Ohne ausdrückliches `confident` gilt: nicht eindeutig. Die Oberfläche
    /// beschriftet den Vorschlag dann als solchen.
    func testConfidenceDefaultsToFalse() {
        let hits = [SearchClient.Hit(title: "t", url: "u", snippet: "", source: "s")]
        let lookup = IdentityLookup.parse(["title": "Etwas"], query: "q", hits: hits)
        XCTAssertEqual(lookup?.confident, false)
    }

    // MARK: Der Suchtreffer ersetzt nichts

    /// Das Kernversprechen: ein aufgelöster Name wird nur übernommen, wenn der
    /// Nutzer ihn angehakt hat. Ohne Häkchen bleibt der Name stehen, den das Modell
    /// im Bild gelesen hat.
    func testLookupNameNeedsTheCheckmark() {
        var proposal = Proposal(name: "Platine")
        proposal.code = ItemCode(value: "MP1584EN", kind: .manufacturer)
        proposal.code?.lookup = CodeLookup(query: "q", title: "MP1584EN Abwärtswandler 3 A")

        XCTAssertEqual(proposal.effectiveName, "Platine", "Ohne Häkchen gilt der eigene Befund.")
        proposal.useLookupName = true
        XCTAssertEqual(proposal.effectiveName, "MP1584EN Abwärtswandler 3 A")
    }

    func testLookupCheckmarkStartsOff() {
        XCTAssertFalse(Proposal(name: "x").useLookupName,
                       "Eine Kette aus drei fehlbaren Gliedern bekommt keine Vorleistung.")
    }

    func testAbsorbUsesEffectiveNameAndKeepsCode() {
        var inv = Inventory()
        var proposal = Proposal(name: "Platine", quantity: 1)
        proposal.code = ItemCode(value: "MP1584EN", kind: .manufacturer)
        proposal.code?.lookup = CodeLookup(query: "q", title: "MP1584EN Abwärtswandler 3 A")
        proposal.useLookupName = true

        _ = inv.absorb(proposal, at: nil, photoID: nil, model: "m")
        XCTAssertEqual(inv.items[0].name, "MP1584EN Abwärtswandler 3 A")
        XCTAssertEqual(inv.items[0].code?.value, "MP1584EN",
                       "Die Nummer bleibt am Eintrag — sie ist das Einzige, was nachprüfbar ist.")
    }

    /// Eine bestätigte Kennung wird nicht von einem späteren Foto überschrieben,
    /// eine fehlende aber ergänzt.
    func testExistingCodeIsNotOverwritten() {
        var inv = Inventory()
        var first = Proposal(name: "Wandler")
        first.code = ItemCode(value: "MP1584EN", kind: .manufacturer)
        _ = inv.absorb(first, at: nil, photoID: nil, model: "m")

        var second = Proposal(name: "Wandler")
        second.code = ItemCode(value: "XL4015", kind: .manufacturer)
        _ = inv.absorb(second, at: nil, photoID: nil, model: "m")
        XCTAssertEqual(inv.items[0].code?.value, "MP1584EN")

        var third = Proposal(name: "Motor")
        third.code = ItemCode(value: "17HS4401", kind: .manufacturer)
        _ = inv.absorb(Proposal(name: "Motor"), at: nil, photoID: nil, model: "m")
        _ = inv.absorb(third, at: nil, photoID: nil, model: "m")
        XCTAssertEqual(inv.items.first { $0.name == "Motor" }?.code?.value, "17HS4401",
                       "Eine fehlende Kennung wird nachgetragen.")
    }

    func testCodeIsSearchableByName() {
        var item = Item(name: "Wandler")
        item.code = ItemCode(value: "MP1584EN", kind: .manufacturer)
        XCTAssertTrue(item.embeddableText.contains("MP1584EN"))
        let hits = ItemSearch.text("MP1584", in: [item])
        XCTAssertEqual(hits.count, 1, "Wer die Nummer tippt, sucht genau dieses Ding.")
        XCTAssertEqual(hits.first?.kind, .code)
    }

    /// Ein Namensanfang bleibt vorn: „Wa“ meint „Wandler“, nicht das Teil mit der
    /// Nummer WA12345.
    func testNamePrefixStillBeatsCode() {
        var numbered = Item(name: "Platine")
        numbered.code = ItemCode(value: "WA12345", kind: .manufacturer)
        let named = Item(name: "Wandler")

        let hits = ItemSearch.merge(ItemSearch.text("wa", in: [numbered, named]))
        XCTAssertEqual(hits.map(\.item.name), ["Wandler", "Platine"])
        XCTAssertEqual(hits.first?.kind, .namePrefix)
        XCTAssertEqual(hits.last?.kind, .code)
    }

    // MARK: Antwortformen der Suchdienste

    func testBraveShape() {
        let hits = SearchClient.hits(in: ["web": ["results": [
            ["title": "MP1584EN", "url": "https://a.org/x", "description": "3A Wandler",
             "profile": ["name": "a.org"]],
        ]]])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].source, "a.org")
        XCTAssertEqual(hits[0].snippet, "3A Wandler")
    }

    func testAlternativeShapesAndHostFallback() {
        let flat = SearchClient.hits(in: ["results": [
            ["title": "T", "link": "https://b.org/y", "snippet": "S"],
        ]])
        XCTAssertEqual(flat.first?.url, "https://b.org/y")
        XCTAssertEqual(flat.first?.source, "b.org", "Ohne Quellenfeld tut es der Gastgebername.")

        XCTAssertTrue(SearchClient.hits(in: ["etwas": "anderes"]).isEmpty)
    }

    func testHitPromptStaysShort() {
        let long = String(repeating: "x", count: 900)
        let hit = SearchClient.Hit(title: "T", url: "https://u", snippet: long, source: "s")
        XCTAssertLessThan(hit.forPrompt.count, 400,
                          "Fünf Werbetexte würden die technischen Angaben verdrängen.")
    }

    // MARK: Der Prompt

    func testScannedCodesReachThePrompt() {
        let codes = [ItemCode(value: "4006381333931", kind: .ean, origin: .scanned)]
        let message = IntakePrompt.message(placePath: nil, existingNames: [], hint: "",
                                           scannedCodes: codes)
        XCTAssertTrue(message.contains("4006381333931"))
        XCTAssertTrue(message.contains("zeichengenau"))
    }

    func testPromptWithoutCodesMentionsNone() {
        let message = IntakePrompt.message(placePath: nil, existingNames: [], hint: "")
        XCTAssertFalse(message.contains("entziffert"))
    }

    /// Dem Modell wird gesagt, ob die Nummer belegt oder abgelesen ist — das
    /// verschiebt die Messlatte, ab der es antworten darf.
    func testLookupMessageDistinguishesOrigin() {
        let hits = [SearchClient.Hit(title: "t", url: "u", snippet: "s", source: "x")]
        let read = IntakePrompt.lookupMessage(
            code: ItemCode(value: "MP1584EN", kind: .manufacturer, origin: .read),
            itemName: "Platine", hits: hits)
        XCTAssertTrue(read.contains("Lesefehler"))

        let scanned = IntakePrompt.lookupMessage(
            code: ItemCode(value: "4006381333931", kind: .ean, origin: .scanned),
            itemName: "Stift", hits: hits)
        XCTAssertTrue(scanned.contains("zeichengenau"))
        XCTAssertFalse(scanned.contains("Lesefehler"))
    }

    // MARK: Speichern

    func testItemWithCodeRoundTrips() throws {
        var item = Item(name: "Wandler")
        item.code = ItemCode(value: "MP1584EN", kind: .manufacturer, origin: .read,
                             lookup: CodeLookup(query: "\"MP1584EN\"", title: "Abwärtswandler",
                                                sourceURL: "https://a.org", confident: true))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(Item.self, from: try encoder.encode(item))
        XCTAssertEqual(back.code?.value, "MP1584EN")
        XCTAssertEqual(back.code?.lookup?.title, "Abwärtswandler")
        XCTAssertEqual(back.code?.lookup?.confident, true)
    }

    /// Ein Bestand aus der Zeit vor dieser Funktion muss weiter lesbar sein.
    func testItemWithoutCodeStillDecodes() throws {
        let item = try JSONDecoder().decode(Item.self, from: Data(#"{"name":"Zange"}"#.utf8))
        XCTAssertNil(item.code)
    }
}
