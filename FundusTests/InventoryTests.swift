import XCTest
@testable import Fundus

/// The statements standing in the comments, here as checks.
///
/// Chosen by what can be quietly wrong: a duplicate, a quantity replaced instead of
/// added, a vector from the wrong model. None of it crashes; all of it makes the
/// inventory untrue.
final class InventoryTests: XCTestCase {

    private func proposal(_ name: String, _ quantity: Int? = nil,
                          note: String = "") -> Proposal {
        Proposal(name: name, quantity: quantity, unit: "", note: note)
    }

    // MARK: absorb — the second photo of the same drawer

    func testSecondPhotoDoesNotDuplicate() {
        var inv = Inventory()
        let shelf = Place(name: "Regal 2")
        inv.addPlace(shelf)

        _ = inv.absorb(proposal("USB-C-Kabel", 3), at: shelf.id, photoID: "a", model: "m")
        _ = inv.absorb(proposal("USB-C-Kabel", 2), at: shelf.id, photoID: "b", model: "m")

        XCTAssertEqual(inv.items.count, 1, "Zwei Aufnahmen desselben Dings sind ein Eintrag.")
        XCTAssertEqual(inv.items[0].quantity, 5, "Die Menge wird addiert, nicht ersetzt.")
    }

    /// Replacing would be the obvious choice and the wrong one: a half-obscured shelf
    /// would correct the stock downwards even though nothing had been used up.
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

    /// The same name in a different place is a different thing. Otherwise two boxes of
    /// screws in two rooms would collapse into one.
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

    /// A sighting does not change the text, so it must not throw the vector away —
    /// otherwise every "seen" costs a recomputation.
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

    /// Deleting a place must not destroy any inventory. The things then lie nowhere —
    /// which is true and visible.
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

    /// A place inside its own subtree would be a ring, and no path comes back out of a
    /// ring.
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

    /// The depth limit in the path: a tree bent out of shape by hand must not hang
    /// while a row is being drawn.
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

    /// A new field must not invalidate an existing file. The synthesised decoder throws
    /// on a missing key — and here that would mean: inventory gone.
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
