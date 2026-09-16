import XCTest
@testable import Fundus

/// Identifiers and how they get resolved.
///
/// A web search on a number produces a precise, technical-sounding product name that
/// looks more reliable than anything else in the inventory — and stands at the end of
/// a chain made of a blurred sticker, confusable characters and a search engine that
/// answers something to every string.
///
/// The answer to that used to be silence: no result at all when in doubt. It is now a
/// choice — up to three possibilities, and the user taps one or none. The checks here
/// therefore hang on two things: that nothing gets into the inventory without that
/// tap, and that every suggestion is honestly labelled with how far it lies from the
/// number that was read.
final class LookupTests: XCTestCase {

    // MARK: What gets searched for in the first place

    /// "M8", "A4", "12" stand on a thousand things. A search on those costs a call and
    /// returns noise that afterwards looks like a finding.
    func testShortOrDigitlessCodesAreNotSearched() {
        XCTAssertFalse(ItemCode(value: "M8").isSearchable)
        XCTAssertFalse(ItemCode(value: "A4").isSearchable)
        XCTAssertFalse(ItemCode(value: "Rot").isSearchable, "Ein Wort ohne Ziffer ist eine Beschriftung.")
        XCTAssertFalse(ItemCode(value: "Schraube").isSearchable)
        XCTAssertTrue(ItemCode(value: "MP1584EN").isSearchable)
        XCTAssertTrue(ItemCode(value: "4006381333931").isSearchable)
    }

    /// A decoded EAN is exact to the character: in quotation marks, so the search
    /// engine does not fall back on a similar product.
    func testScannedCodeIsQuotedVerbatim() {
        let ean = ItemCode(value: "4006381333931", kind: .ean, origin: .scanned)
        XCTAssertEqual(IdentityLookup.query(for: ean, itemName: "Stift"), "\"4006381333931\"")
    }

    /// A number read off by eye is **not**, and that was the cause of the old
    /// behaviour: `"42BYGH3701-B-89S80"` in quotation marks finds nothing when the
    /// motor says `…-B-80S80`. Without them the search finds the series, and the user
    /// picks out their own variant.
    func testReadCodeIsNotQuoted() {
        let mpn = ItemCode(value: "42BYGH3701-B-89S80", kind: .manufacturer, origin: .read)
        XCTAssertEqual(IdentityLookup.query(for: mpn, itemName: "Schrittmotor"),
                       "42BYGH3701-B-89S80 Schrittmotor",
                       "Der gesehene Gegenstand bleibt als Kontext dabei.")
        XCTAssertFalse(IdentityLookup.query(for: mpn, itemName: "").contains("\""),
                       "Auch ohne Kontext keine Anführungszeichen.")
    }

    // MARK: Das Sicherheitsnetz gegen erfundene Strichcodes

    /// A barcode cannot be read by eye. If the model names an EAN that the decoder did
    /// not see, it either invented it or copied it from the digits underneath — and
    /// there a confused digit goes unnoticed.
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

    /// Manufacturer part numbers stand in plain text on the component. The model may
    /// read those — but they stay marked as `read` and therefore as fallible.
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

    // MARK: When the lookup stays silent

    private let mpn = ItemCode(value: "MP1584EN", kind: .manufacturer, origin: .read)

    /// An empty list is the right answer when the hits are about something else
    /// entirely — and must not be padded out into a suggestion.
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

    /// The one check the app makes itself rather than taking on trust: `exact` means
    /// "appears verbatim in a hit", and that can be looked up. A model that wants to
    /// please otherwise grades every hit as a direct hit.
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

    /// With nothing stated, the weakest grade applies. The interface then labels the
    /// suggestion accordingly.
    func testMatchDefaultsToFamily() {
        let hits = [SearchClient.Hit(title: "t", url: "u", snippet: "", source: "s")]
        let lookup = IdentityLookup.parse(["candidates": [["title": "Etwas"]]],
                                          code: mpn, query: "q", hits: hits)
        XCTAssertEqual(lookup?.candidates.first?.match, .family)
    }

    /// Three at most. A longer list stops being help and becomes a second task.
    func testCandidatesAreCappedAtThree() {
        let hits = [SearchClient.Hit(title: "t", url: "u", snippet: "", source: "s")]
        let five = (1 ... 5).map { ["title": "Teil \($0)"] }
        let lookup = IdentityLookup.parse(["candidates": five], code: mpn, query: "q", hits: hits)
        XCTAssertEqual(lookup?.candidates.count, 3)
        XCTAssertEqual(lookup?.candidates.last?.title, "Teil 3", "Die vorderen zuerst.")
    }

    /// Writing the same number out again beside it is noise.
    func testIdenticalCodeSeenIsDropped() {
        let hits = [SearchClient.Hit(title: "MP1584EN", url: "u", snippet: "", source: "s")]
        let lookup = IdentityLookup.parse(
            ["candidates": [["title": "Wandler", "code_seen": "mp1584en"]]],
            code: mpn, query: "q", hits: hits)
        XCTAssertEqual(lookup?.candidates.first?.codeSeen, "")
    }

    /// If the model answers in the old, singular form, that becomes one suggestion —
    /// rather than nothing at all.
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

    /// The core promise: a resolved name is only taken over when the user has tapped
    /// it. Without a tap, the name the model read in the picture stays.
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

    /// An index pointing into nothing must produce neither a crash nor an empty name —
    /// which can happen when a suggestion disappears.
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

    /// If none was tapped, that stands on the entry — and not a suggestion that looks
    /// as if somebody had checked it.
    func testUnchosenLookupIsStoredAsUnchosen() {
        var inv = Inventory()
        _ = inv.absorb(proposalWithThree(), at: nil, photoID: nil, model: "m")
        XCTAssertEqual(inv.items[0].name, "Platine")
        XCTAssertNil(inv.items[0].code?.lookup?.chosen)
    }

    /// A confirmed identifier is not overwritten by a later photo, but a missing one
    /// is filled in.
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

    /// The start of a name stays at the front: "Wa" means "Wandler", not the part with
    /// the number WA12345.
    func testNamePrefixStillBeatsCode() {
        var numbered = Item(name: "Platine")
        numbered.code = ItemCode(value: "WA12345", kind: .manufacturer)
        let named = Item(name: "Wandler")

        let hits = ItemSearch.merge(ItemSearch.text("wa", in: [numbered, named]))
        XCTAssertEqual(hits.map(\.item.name), ["Wandler", "Platine"])
        XCTAssertEqual(hits.first?.kind, .namePrefix)
        XCTAssertEqual(hits.last?.kind, .code)
    }

    // MARK: When nothing stands there, the reason does

    /// "Nothing suitable found" and "the search did not get through" both used to look
    /// like an empty line. The difference decides whether the user tries again
    /// straight away or looks it up themselves.
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

    /// An old entry knows nothing of `failed` — and must not stand there as a failure
    /// merely because the field is missing.
    func testOldLookupIsNotAFailure() throws {
        let json = #"{"name":"W","code":{"value":"X1234","lookup":{"query":"q","title":"Etwas"}}}"#
        let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(item.code?.lookup?.failed, false)
    }

    /// The side call gets the same budget as reading the photo.
    ///
    /// An eighth of it — 4,000 tokens — does not carry a model that thinks first as
    /// far as the first sentence of an answer: `finish_reason: length`, and the lookup
    /// failed without the reason being visible. Nothing was saved by it; the tokens
    /// are billed either way.
    func testSideCallGetsTheFullBudget() {
        XCTAssertEqual(ModelClient.sideCallBudget(32_000), 32_000)
        XCTAssertNotEqual(ModelClient.sideCallBudget(32_000), 4_000,
                          "Ein Achtel reicht für den Gedankengang nicht.")
        XCTAssertEqual(ModelClient.sideCallBudget(0), 1_000,
                       "Eine Untergrenze bleibt, damit eine kaputte Einstellung nicht null ergibt.")
    }

    // MARK: Die echte Antwort des Modells

    /// The case in which the old version displayed nothing: a stepper motor with a
    /// ten-character type designation. The answer below is literally the one
    /// z-ai/glm-5.3-flash wrote in response to the new system prompt and the real
    /// search hits — not a reconstructed ideal case but the contract the parser has to
    /// be measured against.
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

    // MARK: Response shapes of the search services

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

    /// The model is told whether the number is decoded or read by eye — that
    /// determines how tight the comparison has to be.
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

    /// The system prompt has to demand the choice and forbid padding — both live in
    /// the same response shape.
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

    /// An inventory created before this change has the old, flat shape on disk: one
    /// `title` and one `confident`. It has to stay readable and must not look, in the
    /// process, as if somebody had confirmed the suggestion.
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

    /// The same without `confident`: the suggestion was not unambiguous and must not
    /// stand there as a direct hit after the migration.
    func testOldUnconfidentLookupBecomesNear() throws {
        let json = """
        {"name":"W","code":{"value":"X1234","lookup":{"query":"q","title":"Etwas"}}}
        """
        let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(item.code?.lookup?.candidates.first?.match, .near)
    }

    /// The same in the inventory, and there it weighs more: a single unknown `kind`
    /// from a newer version of the app would have made the whole inventory unreadable.
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

    /// An inventory from before this feature has to stay readable.
    func testItemWithoutCodeStillDecodes() throws {
        let item = try JSONDecoder().decode(Item.self, from: Data(#"{"name":"Zange"}"#.utf8))
        XCTAssertNil(item.code)
    }
}
