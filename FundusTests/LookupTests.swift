import XCTest
@testable import Fundus

/// Kennungen und ihre Auflösung.
///
/// Eine Websuche auf eine Nummer erzeugt einen präzisen, technisch klingenden
/// Produktnamen, der verlässlicher aussieht als alles andere im Bestand — und am Ende
/// einer Kette aus unscharfem Aufkleber, verwechselbaren Zeichen und einer
/// Suchmaschine steht, die auf jede Zeichenfolge irgendetwas antwortet.
///
/// Die Antwort darauf war einmal Schweigen: im Zweifel gar kein Ergebnis. Sie ist
/// jetzt eine Auswahl — bis zu drei Möglichkeiten, und der Nutzer tippt eine an oder
/// keine. Die Prüfungen hier hängen deshalb an zwei Stellen: dass nichts ohne diesen
/// Fingertipp in den Bestand kommt, und dass jeder Vorschlag ehrlich beschriftet ist,
/// wie weit er von der gelesenen Nummer entfernt liegt.
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

    /// Eine dekodierte EAN ist zeichengenau: in Anführungszeichen, damit die
    /// Suchmaschine nicht auf ein ähnliches Produkt ausweicht.
    func testScannedCodeIsQuotedVerbatim() {
        let ean = ItemCode(value: "4006381333931", kind: .ean, origin: .scanned)
        XCTAssertEqual(IdentityLookup.query(for: ean, itemName: "Stift"), "\"4006381333931\"")
    }

    /// Eine abgelesene Nummer **nicht**, und das war die Ursache des alten Verhaltens:
    /// `"42BYGH3701-B-89S80"` in Anführungszeichen findet nichts, wenn auf dem Motor
    /// `…-B-80S80` steht. Ohne sie findet die Suche die Baureihe, und der Nutzer sucht
    /// seine Ausführung selbst heraus.
    func testReadCodeIsNotQuoted() {
        let mpn = ItemCode(value: "42BYGH3701-B-89S80", kind: .manufacturer, origin: .read)
        XCTAssertEqual(IdentityLookup.query(for: mpn, itemName: "Schrittmotor"),
                       "42BYGH3701-B-89S80 Schrittmotor",
                       "Der gesehene Gegenstand bleibt als Kontext dabei.")
        XCTAssertFalse(IdentityLookup.query(for: mpn, itemName: "").contains("\""),
                       "Auch ohne Kontext keine Anführungszeichen.")
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

    private let mpn = ItemCode(value: "MP1584EN", kind: .manufacturer, origin: .read)

    /// Eine leere Liste ist die richtige Antwort, wenn die Treffer von etwas ganz
    /// anderem handeln — und darf nicht zu einem Vorschlag aufgefüllt werden.
    func testEmptyOrTitlelessCandidatesProduceNoLookup() {
        let hits = [SearchClient.Hit(title: "Irgendwas", url: "https://x", snippet: "", source: "x")]
        func parse(_ o: [String: Any]) -> CodeLookup? {
            IdentityLookup.parse(o, code: mpn, query: "q", hits: hits)
        }
        XCTAssertNil(parse(["candidates": []]))
        XCTAssertNil(parse(["candidates": [["title": NSNull()]]]))
        XCTAssertNil(parse(["candidates": [["title": "null"], ["title": "  "]]]))
        XCTAssertNil(parse([:]))
    }

    func testLookupKeepsQueryAndSource() {
        let hits = [SearchClient.Hit(title: "MP1584EN Datenblatt",
                                     url: "https://example.org/mp1584",
                                     snippet: "3A Abwärtswandler", source: "example.org")]
        let lookup = IdentityLookup.parse(
            ["candidates": [
                ["title": "MP1584EN DC-DC-Abwärtswandler 3 A",
                 "summary": "Schaltregler-Modul.",
                 "source": "https://example.org/mp1584",
                 "match": "exact"]]],
            code: mpn, query: "MP1584EN Platine", hits: hits)

        XCTAssertEqual(lookup?.candidates.first?.title, "MP1584EN DC-DC-Abwärtswandler 3 A")
        XCTAssertEqual(lookup?.query, "MP1584EN Platine",
                       "Wonach gesucht wurde, muss am Eintrag stehen — sonst ist die Kette nicht zurückverfolgbar.")
        XCTAssertEqual(lookup?.candidates.first?.sourceName, "example.org")
        XCTAssertEqual(lookup?.candidates.first?.match, .exact,
                       "Die Nummer steht wörtlich im Treffertitel.")
        XCTAssertNil(lookup?.chosen, "Ausgewählt hat noch niemand etwas.")
    }

    /// Die eine Prüfung, die die App selbst macht, statt sie zu glauben: `exact`
    /// heißt „steht wörtlich in einem Treffer“, und das lässt sich nachsehen. Ein
    /// Modell, das gefällig sein will, stuft sonst jeden Treffer als Volltreffer ein.
    func testExactIsDowngradedWhenTheCodeIsNowhereInTheHits() {
        let hits = [SearchClient.Hit(title: "Schrittmotor 42BYGH3701-B-80S80",
                                     url: "https://shop.example/motor",
                                     snippet: "NEMA 17, Welle 5 mm", source: "shop.example")]
        let read = ItemCode(value: "42BYGH3701-B-89S80", kind: .manufacturer, origin: .read)
        let lookup = IdentityLookup.parse(
            ["candidates": [["title": "NEMA-17-Schrittmotor 42×42",
                             "match": "exact", "code_seen": "42BYGH3701-B-80S80"]]],
            code: read, query: "q", hits: hits)

        XCTAssertEqual(lookup?.candidates.first?.match, .near,
                       "Die gelesene Nummer steht in keinem Treffer — also kein Volltreffer.")
        XCTAssertEqual(lookup?.candidates.first?.codeSeen, "42BYGH3701-B-80S80",
                       "Die abweichende Nummer ist das, woran der Nutzer sein Teil erkennt.")
    }

    /// Ohne Angabe gilt die schwächste Stufe. Die Oberfläche beschriftet den
    /// Vorschlag dann entsprechend.
    func testMatchDefaultsToFamily() {
        let hits = [SearchClient.Hit(title: "t", url: "u", snippet: "", source: "s")]
        let lookup = IdentityLookup.parse(["candidates": [["title": "Etwas"]]],
                                          code: mpn, query: "q", hits: hits)
        XCTAssertEqual(lookup?.candidates.first?.match, .family)
    }

    /// Höchstens drei. Eine längere Liste ist keine Hilfe mehr, sondern eine zweite
    /// Aufgabe.
    func testCandidatesAreCappedAtThree() {
        let hits = [SearchClient.Hit(title: "t", url: "u", snippet: "", source: "s")]
        let five = (1 ... 5).map { ["title": "Teil \($0)"] }
        let lookup = IdentityLookup.parse(["candidates": five], code: mpn, query: "q", hits: hits)
        XCTAssertEqual(lookup?.candidates.count, 3)
        XCTAssertEqual(lookup?.candidates.last?.title, "Teil 3", "Die vorderen zuerst.")
    }

    /// Dieselbe Nummer noch einmal danebenzuschreiben ist Lärm.
    func testIdenticalCodeSeenIsDropped() {
        let hits = [SearchClient.Hit(title: "MP1584EN", url: "u", snippet: "", source: "s")]
        let lookup = IdentityLookup.parse(
            ["candidates": [["title": "Wandler", "code_seen": "mp1584en"]]],
            code: mpn, query: "q", hits: hits)
        XCTAssertEqual(lookup?.candidates.first?.codeSeen, "")
    }

    /// Antwortet das Modell in der alten, einzelnen Form, wird daraus ein Vorschlag —
    /// statt gar nichts.
    func testSingleObjectAnswerStillWorks() {
        let hits = [SearchClient.Hit(title: "MP1584EN", url: "https://a", snippet: "", source: "a")]
        let lookup = IdentityLookup.parse(["title": "Abwärtswandler"],
                                          code: mpn, query: "q", hits: hits)
        XCTAssertEqual(lookup?.candidates.count, 1)
        XCTAssertEqual(lookup?.candidates.first?.title, "Abwärtswandler")
    }

    // MARK: Der Suchtreffer ersetzt nichts

    private func proposalWithThree() -> Proposal {
        var proposal = Proposal(name: "Platine", quantity: 1)
        proposal.code = ItemCode(value: "MP1584EN", kind: .manufacturer)
        proposal.code?.lookup = CodeLookup(query: "q", candidates: [
            CodeCandidate(title: "MP1584EN Abwärtswandler 3 A", match: .exact),
            CodeCandidate(title: "MP2307 Abwärtswandler 3 A", match: .family),
        ])
        return proposal
    }

    /// Das Kernversprechen: ein aufgelöster Name wird nur übernommen, wenn der Nutzer
    /// ihn angetippt hat. Ohne Fingertipp bleibt der Name stehen, den das Modell im
    /// Bild gelesen hat.
    func testLookupNameNeedsTheTap() {
        var proposal = proposalWithThree()
        XCTAssertEqual(proposal.effectiveName, "Platine", "Ohne Wahl gilt der eigene Befund.")

        proposal.chosenCandidate = 1
        XCTAssertEqual(proposal.effectiveName, "MP2307 Abwärtswandler 3 A",
                       "Es gilt der gewählte Vorschlag, nicht der erste.")

        proposal.chosenCandidate = nil
        XCTAssertEqual(proposal.effectiveName, "Platine",
                       "Zurücknehmen muss möglich sein — `nil` ist eine Antwort.")
    }

    func testNoCandidateIsChosenToBeginWith() {
        XCTAssertNil(Proposal(name: "x").chosenCandidate,
                     "Eine Kette aus drei fehlbaren Gliedern bekommt keine Vorleistung.")
        XCTAssertNil(proposalWithThree().chosenCandidate)
    }

    /// Ein Index, der ins Leere zeigt, darf keinen Absturz und keinen leeren Namen
    /// erzeugen — das kann passieren, wenn ein Vorschlag verschwindet.
    func testOutOfRangeChoiceFallsBackToTheOwnName() {
        var proposal = proposalWithThree()
        proposal.chosenCandidate = 7
        XCTAssertEqual(proposal.effectiveName, "Platine")
    }

    func testAbsorbUsesEffectiveNameAndKeepsCode() {
        var inv = Inventory()
        var proposal = proposalWithThree()
        proposal.chosenCandidate = 0

        _ = inv.absorb(proposal, at: nil, photoID: nil, model: "m")
        XCTAssertEqual(inv.items[0].name, "MP1584EN Abwärtswandler 3 A")
        XCTAssertEqual(inv.items[0].code?.value, "MP1584EN",
                       "Die Nummer bleibt am Eintrag — sie ist das Einzige, was nachprüfbar ist.")
        XCTAssertEqual(inv.items[0].code?.lookup?.chosen, 0,
                       "Welcher Vorschlag bestätigt wurde, gehört an den Bestand.")
        XCTAssertEqual(inv.items[0].code?.lookup?.candidates.count, 2,
                       "Die verworfenen bleiben stehen: sie zeigen, was zur Wahl stand.")
    }

    /// Wurde keiner angetippt, steht das am Eintrag — und nicht ein Vorschlag, der
    /// aussieht, als hätte ihn jemand geprüft.
    func testUnchosenLookupIsStoredAsUnchosen() {
        var inv = Inventory()
        _ = inv.absorb(proposalWithThree(), at: nil, photoID: nil, model: "m")
        XCTAssertEqual(inv.items[0].name, "Platine")
        XCTAssertNil(inv.items[0].code?.lookup?.chosen)
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

    // MARK: Wenn nichts dasteht, steht der Grund da

    /// „Nichts Passendes gefunden“ und „die Suche kam nicht durch“ sahen vorher
    /// beide aus wie eine leere Zeile. Der Unterschied entscheidet, ob der Nutzer es
    /// gleich noch einmal versucht oder selbst nachsieht.
    func testEmptyReasonDistinguishesNothingFoundFromFailure() {
        XCTAssertEqual(CodeLookup(query: "q").emptyReason, "nichts Passendes gefunden")
        XCTAssertEqual(CodeLookup(query: "q", failed: true).emptyReason,
                       "Nachschlagen fehlgeschlagen")
        XCTAssertNil(CodeLookup(query: "q", candidates: [CodeCandidate(title: "t")]).emptyReason,
                     "Mit Vorschlägen gibt es nichts zu begründen.")
    }

    func testFailedLookupRoundTrips() throws {
        var item = Item(name: "Motor")
        item.code = ItemCode(value: "42BYGH3701-B-89S80", kind: .manufacturer,
                             lookup: CodeLookup(query: "q", failed: true))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(Item.self, from: try encoder.encode(item))
        XCTAssertEqual(back.code?.lookup?.failed, true)
        XCTAssertEqual(back.code?.lookup?.emptyReason, "Nachschlagen fehlgeschlagen")
    }

    /// Ein alter Eintrag kennt `failed` nicht — und darf nicht als Fehlschlag
    /// dastehen, nur weil das Feld fehlt.
    func testOldLookupIsNotAFailure() throws {
        let json = #"{"name":"W","code":{"value":"X1234","lookup":{"query":"q","title":"Etwas"}}}"#
        let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(item.code?.lookup?.failed, false)
    }

    /// Der Nebenaufruf bekommt dasselbe Budget wie das Lesen des Fotos.
    ///
    /// Ein Achtel davon — 4 000 Token — reicht einem Modell, das erst nachdenkt,
    /// nicht bis zum ersten Satz Antwort: `finish_reason: length`, und das
    /// Nachschlagen schlug fehl, ohne dass man den Grund sah. Gespart wurde dabei
    /// nichts, die Token werden so oder so abgerechnet.
    func testSideCallGetsTheFullBudget() {
        XCTAssertEqual(ModelClient.sideCallBudget(32_000), 32_000)
        XCTAssertNotEqual(ModelClient.sideCallBudget(32_000), 4_000,
                          "Ein Achtel reicht für den Gedankengang nicht.")
        XCTAssertEqual(ModelClient.sideCallBudget(0), 1_000,
                       "Eine Untergrenze bleibt, damit eine kaputte Einstellung nicht null ergibt.")
    }

    // MARK: Die echte Antwort des Modells

    /// Der Fall, an dem die alte Fassung nichts anzeigte: ein Schrittmotor mit einer
    /// zehnstelligen Typbezeichnung. Die Antwort unten ist wörtlich die, die
    /// z-ai/glm-5.3-flash auf den neuen Systemprompt und die echten Suchtreffer
    /// geschrieben hat — kein nachgebauter Idealfall, sondern der Vertrag, an dem
    /// sich der Parser messen lassen muss.
    func testRealModelAnswerBecomesAShortlist() throws {
        let hits = [
            SearchClient.Hit(
                title: "Dual Shaft NEMA 17 Stepper Motor(42BYGH3701-B-89S80), 80mm&89mm Shafts",
                url: "https://www.daraz.com.np/products/dual-shaft-nema-17-stepper-motor",
                snippet: "For Anycubic Kobra Max Y Axis Motor", source: "daraz.com.np"),
            SearchClient.Hit(
                title: "Hybrid Stepper Motor Datasheet–42BYGH Series",
                url: "https://www.promoco-motors.com/products/StepperMotors/42BYGH%20Series.pdf",
                snippet: "Datasheet 42BYGH Series", source: "promoco-motors.com"),
        ]
        let reply = """
        {"candidates": [
           {"title": "NEMA-17-Schrittmotor 42BYGH3701-B, doppelseitige Welle (80/89 mm), \
        Anycubic Kobra Max Y-Achse",
            "summary": "Zweiseitig ausgeführter NEMA-17-Hybridschrittmotor.",
            "source": "https://www.daraz.com.np/products/dual-shaft-nema-17-stepper-motor",
            "match": "exact",
            "code_seen": "42BYGH3701-B-89S80"},
           {"title": "42BYGH-Serie Hybrid-Schrittmotor (NEMA 17), Datenblatt",
            "summary": "Datenblatt der 42BYGH-Standardbaureihe im NEMA-17-Format.",
            "source": "https://www.promoco-motors.com/products/StepperMotors/42BYGH%20Series.pdf",
            "match": "family",
            "code_seen": "42BYGH"}
        ]}
        """
        let object = try XCTUnwrap(JSONSnippet.firstObject(in: reply))
        let code = ItemCode(value: "42BYGH3701-B-89S80", kind: .manufacturer, origin: .read)
        let lookup = try XCTUnwrap(IdentityLookup.parse(object, code: code,
                                                        query: "42BYGH3701-B-89S80 Schrittmotor",
                                                        hits: hits))

        XCTAssertEqual(lookup.candidates.count, 2, "Zwei unterscheidbare Möglichkeiten.")
        XCTAssertEqual(lookup.candidates[0].match, .exact,
                       "Die Nummer steht wörtlich im ersten Treffertitel.")
        XCTAssertEqual(lookup.candidates[0].codeSeen, "",
                       "Dieselbe Nummer noch einmal danebenzuschreiben ist Lärm.")
        XCTAssertEqual(lookup.candidates[0].sourceName, "daraz.com.np")
        XCTAssertEqual(lookup.candidates[1].match, .family)
        XCTAssertEqual(lookup.candidates[1].sourceName, "promoco-motors.com")
        XCTAssertNil(lookup.chosen, "Vorgelegt, nicht entschieden.")
        XCTAssertNil(lookup.emptyReason)
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

    /// Dem Modell wird gesagt, ob die Nummer belegt oder abgelesen ist — das legt
    /// fest, wie eng der Vergleich sein muss.
    func testLookupMessageDistinguishesOrigin() {
        let hits = [SearchClient.Hit(title: "t", url: "u", snippet: "s", source: "x")]
        let read = IntakePrompt.lookupMessage(
            code: ItemCode(value: "MP1584EN", kind: .manufacturer, origin: .read),
            itemName: "Platine", hits: hits)
        XCTAssertTrue(read.contains("Lesefehler"))
        XCTAssertTrue(read.contains("code_seen"),
                      "Bei einer abgelesenen Nummer ist ein knapp danebenliegender Treffer erwünscht.")

        let scanned = IntakePrompt.lookupMessage(
            code: ItemCode(value: "4006381333931", kind: .ean, origin: .scanned),
            itemName: "Stift", hits: hits)
        XCTAssertTrue(scanned.contains("zeichengenau"))
        XCTAssertFalse(scanned.contains("Lesefehler"))
    }

    /// Der Systemprompt muss die Auswahl verlangen und das Auffüllen verbieten —
    /// beides steht in derselben Antwortform.
    func testLookupSystemAsksForAShortlist() {
        XCTAssertTrue(IntakePrompt.lookupSystem.contains("candidates"))
        XCTAssertTrue(IntakePrompt.lookupSystem.contains("drei"))
        XCTAssertTrue(IntakePrompt.lookupSystem.contains("füllst nicht auf"))
    }

    // MARK: Speichern

    func testItemWithCodeRoundTrips() throws {
        var item = Item(name: "Wandler")
        item.code = ItemCode(
            value: "MP1584EN", kind: .manufacturer, origin: .read,
            lookup: CodeLookup(query: "MP1584EN", candidates: [
                CodeCandidate(title: "Abwärtswandler", sourceURL: "https://a.org",
                              match: .near, codeSeen: "MP1584EN-2"),
                CodeCandidate(title: "Etwas anderes"),
            ], chosen: 0))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(Item.self, from: try encoder.encode(item))
        XCTAssertEqual(back.code?.value, "MP1584EN")
        XCTAssertEqual(back.code?.lookup?.candidates.count, 2)
        XCTAssertEqual(back.code?.lookup?.chosen, 0)
        XCTAssertEqual(back.code?.lookup?.best?.title, "Abwärtswandler")
        XCTAssertEqual(back.code?.lookup?.best?.match, .near)
        XCTAssertEqual(back.code?.lookup?.best?.codeSeen, "MP1584EN-2")
    }

    /// Ein Bestand, der vor dieser Änderung angelegt wurde, hat die alte, flache Form
    /// auf der Platte: ein `title` und ein `confident`. Er muss weiter lesbar sein und
    /// darf dabei nicht so aussehen, als hätte jemand den Vorschlag bestätigt.
    func testOldFlatLookupDecodesIntoOneCandidate() throws {
        let json = """
        {"name":"Wandler",
         "code":{"value":"MP1584EN","kind":"manufacturer","origin":"read",
                 "lookup":{"query":"\\"MP1584EN\\"","title":"Abwärtswandler",
                           "summary":"Schaltregler.","sourceURL":"https://a.org",
                           "sourceName":"a.org","confident":true}}}
        """
        let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        let lookup = try XCTUnwrap(item.code?.lookup)
        XCTAssertEqual(lookup.candidates.count, 1)
        XCTAssertEqual(lookup.candidates[0].title, "Abwärtswandler")
        XCTAssertEqual(lookup.candidates[0].sourceName, "a.org")
        XCTAssertEqual(lookup.candidates[0].match, .exact, "`confident` hieß: steht wörtlich da.")
        XCTAssertNil(lookup.chosen)
    }

    /// Dasselbe ohne `confident`: der Vorschlag war nicht eindeutig und darf nach der
    /// Migration nicht als Volltreffer dastehen.
    func testOldUnconfidentLookupBecomesNear() throws {
        let json = """
        {"name":"W","code":{"value":"X1234","lookup":{"query":"q","title":"Etwas"}}}
        """
        let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(item.code?.lookup?.candidates.first?.match, .near)
    }

    /// Dasselbe im Bestand, und dort wiegt es schwerer: ein einziges unbekanntes
    /// `kind` aus einer neueren Fassung der App hätte den ganzen Bestand unlesbar
    /// gemacht.
    func testUnknownEnumInAnItemDoesNotLoseTheItem() throws {
        let json = #"""
        {"name":"Wandler","note":"bleibt",
         "code":{"value":"MP1584EN","kind":"nfc","origin":"gefunkt",
                 "lookup":{"query":"q","candidates":[{"title":"X","match":"telepathisch"}]}},
         "provenance":{"origin":"traumdeutung"}}
        """#
        let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(item.name, "Wandler")
        XCTAssertEqual(item.note, "bleibt")
        XCTAssertEqual(item.code?.value, "MP1584EN")
        XCTAssertEqual(item.code?.kind, .unknown, "Unbekannte Art heisst unbekannte Art.")
        XCTAssertEqual(item.code?.origin, .read)
        XCTAssertEqual(item.code?.lookup?.candidates.first?.match, .family)
        XCTAssertEqual(item.provenance.origin, .manual)
    }

    /// Ein Bestand aus der Zeit vor dieser Funktion muss weiter lesbar sein.
    func testItemWithoutCodeStillDecodes() throws {
        let item = try JSONDecoder().decode(Item.self, from: Data(#"{"name":"Zange"}"#.utf8))
        XCTAssertNil(item.code)
    }
}
