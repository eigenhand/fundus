import XCTest
@testable import Fundus

/// Die Suche und der Index.
///
/// Der Kern ist eine Rangfolge: ein Namenstreffer ist eine Gewissheit, ein Kosinus
/// eine Vermutung. Und die Klassifizierung der Vektoren, denn ein Vektor aus dem
/// falschen Modell liefert keinen Fehler, sondern still Unsinn.
final class SearchTests: XCTestCase {

    private func item(_ name: String, note: String = "", tags: [String] = [],
                      vector: [Float]? = nil, model: String? = nil) -> Item {
        var i = Item(name: name, note: note)
        i.tags = tags
        i.embedding = vector
        if let vector, let model {
            i.embeddingStamp = EmbeddingStamp(model: model, dimension: vector.count)
        }
        return i
    }

    // MARK: Textsuche

    func testPrefixBeatsContains() {
        let items = [item("Kabelbinder"), item("USB-C-Kabel")]
        let hits = ItemSearch.merge(ItemSearch.text("kabel", in: items))

        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].item.name, "Kabelbinder")
        XCTAssertEqual(hits[0].kind, .namePrefix)
        XCTAssertEqual(hits[1].kind, .nameContains)
    }

    /// Niemand tippt „Lötzinn“ mit dem richtigen Umlaut, wenn er es schnell sucht.
    func testDiacriticAndCaseInsensitive() {
        let items = [item("Lötzinn")]
        XCTAssertEqual(ItemSearch.text("lotzinn", in: items).count, 1)
        XCTAssertEqual(ItemSearch.text("LÖTZINN", in: items).count, 1)
    }

    func testNoteAndTagsRankBelowName() {
        let items = [item("Klebeband", note: "grau, breit"),
                     item("Isolierband", tags: ["grau"])]
        let hits = ItemSearch.merge(ItemSearch.text("grau", in: items))
        XCTAssertEqual(hits.count, 2)
        XCTAssertTrue(hits.allSatisfy { $0.kind == .sideText })
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertTrue(ItemSearch.text("   ", in: [item("A")]).isEmpty)
    }

    // MARK: Zusammenlegen

    /// Ein Ding, das auf beiden Wegen kommt, behält den besseren. Sonst stünde ein
    /// Namenstreffer unter „Bedeutung“, und der Nutzer würde lesen, die App habe
    /// geraten, wo sie gewusst hat.
    func testNameHitWinsOverSemanticForSameItem() {
        let kabel = item("Kabel")
        let byName = [ItemSearch.Hit(item: kabel, kind: .nameContains)]
        let byMeaning = [ItemSearch.Hit(item: kabel, kind: .semantic, similarity: 0.9)]

        let merged = ItemSearch.merge(byName, byMeaning)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].kind, .nameContains)
    }

    func testSemanticHitsSortBySimilarity() {
        let a = item("A"), b = item("B")
        let merged = ItemSearch.merge([
            ItemSearch.Hit(item: a, kind: .semantic, similarity: 0.3),
            ItemSearch.Hit(item: b, kind: .semantic, similarity: 0.8),
        ])
        XCTAssertEqual(merged.map(\.item.name), ["B", "A"])
    }

    /// Eine Reihenfolge aus einem Dictionary ist zufällig, und eine Trefferliste, die
    /// bei jedem Tastendruck springt, ist unbenutzbar.
    func testEqualRankIsOrderedStably() {
        let items = [item("Zange"), item("Ahle"), item("Meißel")]
        let hits = items.map { ItemSearch.Hit(item: $0, kind: .namePrefix) }

        let first = ItemSearch.merge(hits).map(\.item.name)
        for _ in 0 ..< 20 {
            XCTAssertEqual(ItemSearch.merge(hits).map(\.item.name), first)
        }
        XCTAssertEqual(first, ["Ahle", "Meißel", "Zange"])
    }

    // MARK: Ähnlichkeitssuche

    func testSemanticIgnoresForeignVectors() {
        let items = [
            item("richtig", vector: [1, 0, 0], model: "m"),
            item("fremdes Modell", vector: [1, 0, 0], model: "anderes"),
            item("ohne Stempel", vector: [1, 0, 0]),
            item("ohne Vektor"),
        ]
        let hits = ItemSearch.semantic([1, 0, 0], in: items, model: "m", centroid: nil,
                                       minimum: 0.5, limit: 10)
        XCTAssertEqual(hits.map(\.item.name), ["richtig"],
                       "Nur Vektoren aus dem eingestellten Modell dürfen mitrechnen.")
    }

    func testSemanticRespectsMinimum() {
        let items = [item("nah", vector: [1, 0], model: "m"),
                     item("fern", vector: [0, 1], model: "m")]
        let hits = ItemSearch.semantic([1, 0], in: items, model: "m", centroid: nil,
                                       minimum: 0.5, limit: 10)
        XCTAssertEqual(hits.map(\.item.name), ["nah"])
    }

    /// Ein Vektor anderer Länge ist nicht falsch berechnet, sondern gar nicht
    /// vergleichbar. Er darf nicht als Nichttreffer durchgehen, sondern muss
    /// draußen bleiben.
    func testMismatchedDimensionIsExcluded() {
        let items = [item("kurz", vector: [1, 0], model: "m")]
        let hits = ItemSearch.semantic([1, 0, 0], in: items, model: "m", centroid: nil,
                                       minimum: 0, limit: 10)
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: Index

    func testStatusClassifies() {
        let items = [
            item("a", vector: [1, 0], model: "m"),
            item("b", vector: [0, 1], model: "m"),
            item("c", vector: [1, 1], model: "altes-modell"),
            item("d", vector: [1, 1]),
            item("e"),
        ]
        let status = Indexer.status(items, model: "m")

        XCTAssertEqual(status.usable, 2)
        XCTAssertEqual(status.foreign, 2, "Fremdes Modell und fehlender Stempel zählen beide als fremd.")
        XCTAssertEqual(status.missing, 1)
        XCTAssertEqual(status.total, 5)
        XCTAssertEqual(status.byModel["unbekannt"], 1)
        XCTAssertFalse(status.isClean)
    }

    func testStatusIsCleanWhenEverythingMatches() {
        let items = [item("a", vector: [1, 0], model: "m")]
        XCTAssertTrue(Indexer.status(items, model: "m").isClean)
    }

    /// Anbieter ändern die Vektorlänge unter demselben Modellnamen. Die häufigste
    /// gewinnt; Ausreißer gelten als fremd und werden neu geholt.
    func testDominantDimensionWins() {
        let items = [
            item("a", vector: [1, 0], model: "m"),
            item("b", vector: [0, 1], model: "m"),
            item("c", vector: [1, 1, 1], model: "m"),
        ]
        XCTAssertEqual(Indexer.dominantDimension(items, model: "m"), 2)
        XCTAssertEqual(Indexer.status(items, model: "m").foreign, 1)
    }

    func testModelNameIsNormalised() {
        let items = [item("a", vector: [1, 0], model: "  Qwen/Embedding  ")]
        XCTAssertEqual(Indexer.status(items, model: "qwen/embedding").usable, 1)
    }

    func testNeedingEmbeddingReturnsForeignAndMissing() {
        let items = [
            item("gut", vector: [1, 0], model: "m"),
            item("fremd", vector: [1, 0], model: "x"),
            item("leer"),
        ]
        let pending = Indexer.needingEmbedding(items, model: "m")
        XCTAssertEqual(Set(pending.map(\.name)), ["fremd", "leer"])
    }

    // MARK: Zentrieren

    /// Unter zehn Einträgen wäre der Mittelvektor hauptsächlich der eine Eintrag, den
    /// man sucht — das Abziehen würde genau den Treffer wegrechnen.
    func testCentroidNeedsEnoughItems() {
        let few = (0 ..< 9).map { item("i\($0)", vector: [Float($0), 1], model: "m") }
        XCTAssertNil(Indexer.centroid(few, model: "m"))

        let enough = (0 ..< 10).map { item("i\($0)", vector: [Float($0), 1], model: "m") }
        XCTAssertNotNil(Indexer.centroid(enough, model: "m"))
    }

    func testCentroidIsTheMean() {
        let items = (0 ..< 10).map { _ in item("x", vector: [2, 4], model: "m") }
        let centroid = Indexer.centroid(items, model: "m")
        XCTAssertEqual(centroid?[0], 2)
        XCTAssertEqual(centroid?[1], 4)
    }

    /// Ein halb zentrierter Vektor wäre schlimmer als ein unzentrierter.
    func testCenteringLeavesMismatchedLengthsAlone() {
        let vector: [Float] = [1, 2, 3]
        XCTAssertEqual(Indexer.centered(vector, by: [1, 1]), vector)
        XCTAssertEqual(Indexer.centered(vector, by: nil), vector)
        XCTAssertEqual(Indexer.centered(vector, by: [1, 1, 1]), [0, 1, 2])
    }

    // MARK: Kosinus

    func testCosine() {
        XCTAssertEqual(cosineSimilarity([1, 0], [1, 0]), 1, accuracy: 1e-6)
        XCTAssertEqual(cosineSimilarity([1, 0], [0, 1]), 0, accuracy: 1e-6)
        XCTAssertEqual(cosineSimilarity([1, 0], [-1, 0]), -1, accuracy: 1e-6)
        XCTAssertEqual(cosineSimilarity([0, 0], [1, 0]), 0, "Ein Nullvektor hat keine Richtung.")
    }
}
