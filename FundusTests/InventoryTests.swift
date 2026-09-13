import XCTest
@testable import Fundus

/// Die Aussagen, die in den Kommentaren stehen, hier als Prüfungen.
///
/// Ausgewählt nach dem, was still falsch sein kann: eine Dublette, eine Menge, die
/// ersetzt statt addiert wird, ein Vektor aus dem falschen Modell. Nichts davon
/// stürzt ab; alles davon macht den Bestand unwahr.
final class InventoryTests: XCTestCase {

    private func proposal(_ name: String, _ quantity: Int? = nil,
                          note: String = "") -> Proposal {
        Proposal(name: name, quantity: quantity, unit: "", note: note)
    }

    // MARK: absorb — das zweite Foto derselben Schublade

    func testSecondPhotoDoesNotDuplicate() {
        var inv = Inventory()
        let shelf = Place(name: "Regal 2")
        inv.addPlace(shelf)

        _ = inv.absorb(proposal("USB-C-Kabel", 3), at: shelf.id, photoID: "a", model: "m")
        _ = inv.absorb(proposal("USB-C-Kabel", 2), at: shelf.id, photoID: "b", model: "m")

        XCTAssertEqual(inv.items.count, 1, "Zwei Aufnahmen desselben Dings sind ein Eintrag.")
        XCTAssertEqual(inv.items[0].quantity, 5, "Die Menge wird addiert, nicht ersetzt.")
    }

    /// Ersetzen wäre die naheliegende Wahl und die falsche: ein halb verdecktes Regal
    /// würde den Bestand nach unten korrigieren, obwohl nichts verbraucht wurde.
    func testQuantityIsAddedNotReplaced() {
        var inv = Inventory()
        _ = inv.absorb(proposal("Dose", 8), at: nil, photoID: nil, model: nil)
        _ = inv.absorb(proposal("Dose", 1), at: nil, photoID: nil, model: nil)
        XCTAssertEqual(inv.items[0].quantity, 9)
    }

    func testNormalisedNamesMerge() {
        var inv = Inventory()
        _ = inv.absorb(proposal("USB-C Kabel", 1), at: nil, photoID: nil, model: nil)
        let outcome = inv.absorb(proposal("usb-c  kabel", 1), at: nil, photoID: nil, model: nil)

        XCTAssertEqual(inv.items.count, 1, "Schreibweise und Leerzeichen trennen keine Dinge.")
        guard case .increased = outcome else {
            return XCTFail("Erwartet: erhöht, nicht angelegt.")
        }
    }

    /// Derselbe Name an einem anderen Ort ist ein anderes Ding. Sonst würden zwei
    /// Schraubenkisten in zwei Räumen zu einer zusammenfallen.
    func testSameNameAtDifferentPlaceIsSeparate() {
        var inv = Inventory()
        let a = Place(name: "Keller"), b = Place(name: "Dachboden")
        inv.addPlace(a); inv.addPlace(b)

        _ = inv.absorb(proposal("Schrauben", 1), at: a.id, photoID: nil, model: nil)
        _ = inv.absorb(proposal("Schrauben", 1), at: b.id, photoID: nil, model: nil)
        XCTAssertEqual(inv.items.count, 2)
    }

    func testAbsorbRecordsProvenance() {
        var inv = Inventory()
        _ = inv.absorb(proposal("Lack"), at: nil, photoID: "foto-1", model: "z-ai/glm-5.3-flash")

        let item = inv.items[0]
        XCTAssertEqual(item.provenance.origin, .photo)
        XCTAssertEqual(item.provenance.model, "z-ai/glm-5.3-flash",
                       "Wer den Eintrag geschrieben hat, muss am Eintrag stehen.")
        XCTAssertEqual(item.provenance.photoID, "foto-1")
        XCTAssertEqual(item.photoIDs, ["foto-1"], "Das Bild ist der Beleg.")
    }

    func testAbsorbSkipsEmptyName() {
        var inv = Inventory()
        XCTAssertEqual(inv.absorb(proposal("   "), at: nil, photoID: nil, model: nil), .skipped)
        XCTAssertTrue(inv.items.isEmpty)
    }

    /// Eine Sichtung ändert den Text nicht, also darf sie den Vektor nicht
    /// wegwerfen — sonst kostet jedes „Gesehen“ eine Neuberechnung.
    func testMarkSeenKeepsEmbedding() {
        var inv = Inventory()
        var item = Item(name: "Hammer")
        item.embedding = [1, 0, 0]
        item.embeddingStamp = EmbeddingStamp(model: "m", dimension: 3)
        item.lastSeenAt = Date(timeIntervalSinceNow: -100_000)
        inv.add(item)

        inv.markSeen(item.id)
        XCTAssertNotNil(inv.items[0].embedding)
        XCTAssertEqual(Freshness.of(inv.items[0]), .seen)
    }

    // MARK: Orte

    /// Ein Ort zu löschen darf keinen Bestand vernichten. Die Dinge liegen danach
    /// nirgends — das stimmt und ist sichtbar.
    func testRemovingPlaceKeepsItems() {
        var inv = Inventory()
        let keller = Place(name: "Keller")
        let regal = Place(name: "Regal 2", parentID: keller.id)
        inv.addPlace(keller); inv.addPlace(regal)
        _ = inv.absorb(proposal("Farbe", 2), at: regal.id, photoID: nil, model: nil)

        inv.removePlace(keller.id)
        XCTAssertTrue(inv.places.isEmpty, "Der Unterbaum geht mit.")
        XCTAssertEqual(inv.items.count, 1, "Das Ding bleibt.")
        XCTAssertNil(inv.items[0].placeID)
    }

    func testItemsIncludeSubPlaces() {
        var inv = Inventory()
        let keller = Place(name: "Keller")
        let regal = Place(name: "Regal 2", parentID: keller.id)
        inv.addPlace(keller); inv.addPlace(regal)
        _ = inv.absorb(proposal("Farbe"), at: regal.id, photoID: nil, model: nil)

        XCTAssertEqual(inv.items(at: keller.id).count, 1, "„Alles im Keller“ heißt auch darunter.")
        XCTAssertEqual(inv.items(at: keller.id, includingBelow: false).count, 0)
    }

    /// Ein Ort in seinem eigenen Unterbaum wäre ein Ring, und aus einem Ring kommt
    /// kein Pfad zurück.
    func testMoveIntoOwnSubtreeIsRejected() {
        var inv = Inventory()
        let keller = Place(name: "Keller")
        let regal = Place(name: "Regal", parentID: keller.id)
        inv.addPlace(keller); inv.addPlace(regal)

        XCTAssertFalse(inv.movePlace(keller.id, under: regal.id))
        XCTAssertFalse(inv.movePlace(keller.id, under: keller.id))
        XCTAssertTrue(inv.movePlace(regal.id, under: nil))
    }

    func testPathAndFlattening() {
        var inv = Inventory()
        let keller = Place(name: "Keller")
        let regal = Place(name: "Regal 2", parentID: keller.id)
        let kiste = Place(name: "Kiste C", parentID: regal.id)
        inv.addPlace(keller); inv.addPlace(regal); inv.addPlace(kiste)

        XCTAssertEqual(inv.tree.path(of: kiste.id), "Keller · Regal 2 · Kiste C")
        XCTAssertEqual(inv.tree.flattened().map(\.depth), [0, 1, 2])
    }

    /// Die Tiefenbegrenzung im Pfad: ein von Hand verbogener Baum darf beim Zeichnen
    /// einer Zeile nicht hängen bleiben.
    func testPathTerminatesOnCycle() {
        var a = Place(name: "A")
        var b = Place(name: "B")
        a.parentID = b.id
        b.parentID = a.id
        let tree = PlaceTree([a, b])

        let path = tree.path(of: a.id)
        XCTAssertFalse(path.isEmpty)
        XCTAssertLessThanOrEqual(path.components(separatedBy: " · ").count, 32)
    }

    // MARK: Alter einer Sichtung

    func testFreshnessSteps() {
        func item(daysAgo: Double) -> Item {
            var i = Item(name: "x")
            i.lastSeenAt = Date(timeIntervalSinceNow: -daysAgo * 24 * 3600)
            return i
        }
        XCTAssertEqual(Freshness.of(item(daysAgo: 1)), .seen)
        XCTAssertEqual(Freshness.of(item(daysAgo: 29)), .seen)
        XCTAssertEqual(Freshness.of(item(daysAgo: 31)), .assumed)
        XCTAssertEqual(Freshness.of(item(daysAgo: 179)), .assumed)
        XCTAssertEqual(Freshness.of(item(daysAgo: 181)), .stale)
    }

    // MARK: Nachsichtiges Dekodieren

    /// Ein neues Feld darf keine bestehende Datei ungültig machen. Der
    /// synthetisierte Decoder wirft bei einem fehlenden Schlüssel — und das hieße
    /// hier: Bestand weg.
    func testItemDecodesFromMinimalJSON() throws {
        let json = Data(#"{"name":"Zange"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(Item.self, from: json)

        XCTAssertEqual(item.name, "Zange")
        XCTAssertNil(item.quantity)
        XCTAssertEqual(item.provenance.origin, .manual)
        XCTAssertNil(item.embeddingStamp)
    }

    func testInventoryDecodesFromEmptyObject() throws {
        let inv = try JSONDecoder().decode(Inventory.self, from: Data("{}".utf8))
        XCTAssertTrue(inv.items.isEmpty)
        XCTAssertTrue(inv.places.isEmpty)
    }

    func testRoundTrip() throws {
        var inv = Inventory()
        let place = Place(name: "Werkstatt")
        inv.addPlace(place)
        _ = inv.absorb(proposal("Lötzinn", 2, note: "1 mm"), at: place.id,
                       photoID: "p", model: "m")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(Inventory.self, from: try encoder.encode(inv))
        XCTAssertEqual(back.items.count, 1)
        XCTAssertEqual(back.items[0].name, "Lötzinn")
        XCTAssertEqual(back.items[0].note, "1 mm")
        XCTAssertEqual(back.places[0].name, "Werkstatt")
    }
}
