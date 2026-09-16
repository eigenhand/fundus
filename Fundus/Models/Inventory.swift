import Foundation

/// The inventory: things and places in one document.
///
/// A value type with pure functions on it, not a store with state. The reason is
/// testability: "a second photo of the same drawer must not create duplicates" is a
/// statement about `absorb`, and you want to be able to write it in a test without
/// having a file, an endpoint or an interface.
struct Inventory: Codable, Equatable {
    var items: [Item] = []
    var places: [Place] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items  = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        places = try c.decodeIfPresent([Place].self, forKey: .places) ?? []
    }

    var tree: PlaceTree { PlaceTree(places) }

    // MARK: Lesen

    func item(_ id: UUID) -> Item? { items.first { $0.id == id } }
    func place(_ id: UUID?) -> Place? { id.flatMap { pid in places.first { $0.id == pid } } }

    /// Things in this place — with `includingBelow`, everything in the sub-places too.
    func items(at placeID: UUID, includingBelow: Bool = true) -> [Item] {
        let ids = includingBelow ? tree.subtree(of: placeID) : [placeID]
        return items.filter { $0.placeID.map(ids.contains) ?? false }
    }

    /// Things without a place. Not a special case but the normal one when entering
    /// quickly — the place gets filled in when you put the thing away.
    var unplaced: [Item] { items.filter { $0.placeID == nil } }

    /// A thing of the same name in the same place. The comparison ignores
    /// capitalisation and accents, because the model's "USB-C-Kabel" and a typed
    /// "USB-C Kabel" mean the same thing.
    func existing(named name: String, at placeID: UUID?) -> Item? {
        let wanted = Item.normalise(name)
        guard !wanted.isEmpty else { return nil }
        return items.first { $0.placeID == placeID && $0.normalisedName == wanted }
    }

    // MARK: Schreiben

    mutating func add(_ item: Item) {
        var copy = item
        copy.updatedAt = Date()
        items.append(copy)
    }

    mutating func update(_ item: Item) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        var copy = item
        copy.updatedAt = Date()
        items[i] = copy
    }

    mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// "Seen": the date on which the entire reliability of this app rests.
    ///
    /// Does not touch the vector. A sighting changes nothing about the text and
    /// therefore nothing about the embedding — recomputing the index over it would be
    /// work without effect.
    mutating func markSeen(_ id: UUID, at date: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].lastSeenAt = date
        items[i].updatedAt = date
    }

    /// Takes in a confirmed suggestion — either as a new thing or as an increase on one
    /// that is already there.
    ///
    /// This is the place where it is decided whether the app survives the second photo
    /// of the same drawer. Without it, two shots would leave two "USB-C cables" in the
    /// same place, and from then on the inventory is no longer an inventory but a list
    /// of observations.
    ///
    /// On a match the quantity is added and not replaced: the photo shows what was
    /// visible, not what is there. Replacing would turn a half-obscured shelf into a
    /// downward correction of the stock.
    @discardableResult
    mutating func absorb(_ proposal: Proposal, at placeID: UUID?, photoID: String?,
                         model: String?) -> Outcome {
        // `effectiveName`, not `name`: if the user tapped a suggestion from the web
        // search, its title is the name — otherwise the one the model read in the
        // picture.
        let clean = proposal.effectiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return .skipped }

        if var found = existing(named: clean, at: placeID) {
            if let extra = proposal.quantity {
                found.quantity = (found.quantity ?? 0) + extra
            }
            if !proposal.note.isEmpty, !found.note.localizedCaseInsensitiveContains(proposal.note) {
                found.note = found.note.isEmpty ? proposal.note : found.note + "; " + proposal.note
            }
            if let photoID, !found.photoIDs.contains(photoID) { found.photoIDs.append(photoID) }
            // An identifier on the existing entry is not overwritten: the first one was
            // there when somebody confirmed it. A missing one is filled in — the second
            // photo may show the rating plate more sharply.
            if found.code == nil { found.code = proposal.resolvedCode }
            found.lastSeenAt = Date()
            update(found)
            return .increased(found.id)
        }

        var item = Item(name: clean, quantity: proposal.quantity, unit: proposal.unit,
                        note: proposal.note, placeID: placeID,
                        provenance: Provenance(origin: .photo, photoID: photoID, model: model))
        if let photoID { item.photoIDs = [photoID] }
        item.code = proposal.resolvedCode
        add(item)
        return .added(item.id)
    }

    enum Outcome: Equatable {
        case added(UUID)
        case increased(UUID)
        case skipped
    }

    // MARK: Orte

    mutating func addPlace(_ place: Place) { places.append(place) }

    mutating func renamePlace(_ id: UUID, to name: String) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        places[i].name = name
    }

    /// Moves a place. A move into its own subtree is refused rather than turning the
    /// tree into a ring — no path would come back out of that.
    @discardableResult
    mutating func movePlace(_ id: UUID, under parent: UUID?) -> Bool {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return false }
        if let parent {
            guard parent != id, !tree.isDescendant(parent, of: id) else { return false }
        }
        places[i].parentID = parent
        return true
    }

    /// Deletes a place and everything under it. The things stay — they then lie
    /// nowhere, which is true and visible. Deleting them along with it would destroy an
    /// inventory because somebody wanted to rename a shelf.
    mutating func removePlace(_ id: UUID) {
        let gone = tree.subtree(of: id)
        places.removeAll { gone.contains($0.id) }
        for i in items.indices where items[i].placeID.map(gone.contains) ?? false {
            items[i].placeID = nil
            items[i].updatedAt = Date()
        }
    }
}

/// A suggestion as it comes out of a photo — not yet an entry.
///
/// Its own type and not a half-finished `Item`: a suggestion has no ID, no provenance
/// and no sighting date, and an `Item` sitting in memory without having been confirmed
/// is exactly the blurring this app is meant not to have.
struct Proposal: Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var quantity: Int?
    var unit: String = ""
    var note: String = ""
    /// A number that stands on the thing — decoded or read by eye, see `ItemCode`.
    var code: ItemCode?
    /// Unticked by the user in the checking step.
    var accepted: Bool = true
    /// Which suggestion from the web search the user tapped.
    ///
    /// Kept apart from `accepted`, and that is the core of the safeguard: you can keep
    /// the find and discard the interpretation. Starts at `nil` — none — unlike
    /// `accepted`. A chain of three fallible links does not get the same benefit of the
    /// doubt as what the model saw with its own eyes in the picture.
    ///
    /// `nil` here does not mean "not yet decided" but is a valid answer: none of the
    /// suggestions is it. Then the name the model read stays.
    var chosenCandidate: Int?

    /// The name that actually gets stored on acceptance.
    var effectiveName: String {
        if let i = chosenCandidate, let list = code?.lookup?.candidates,
           list.indices.contains(i), !list[i].title.isEmpty {
            return list[i].title
        }
        return name
    }

    /// The identifier as it goes onto the entry: with the choice that was made inside
    /// it.
    ///
    /// The choice belongs to the inventory and not only to this checking step. Whoever
    /// stands in front of the shelf in half a year's time then sees not only what the
    /// search suggested but also which of those somebody confirmed — and whether
    /// anybody did.
    var resolvedCode: ItemCode? {
        guard var c = code else { return nil }
        c.lookup?.chosen = chosenCandidate
        return c
    }
}
