import Foundation

/// A thing in the inventory.
///
/// The fields that are not obvious stand here not for completeness but because without
/// them an inventory is an assertion: `provenance` says who wrote the entry,
/// `lastSeenAt` when somebody last saw it with their own eyes. A stock of things goes
/// stale while the database looks the same as on the first day — and that is the one
/// untruth an inventory app produces all by itself. Both fields are aimed against it.
struct Item: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()

    /// Short and searchable: "USB-C cable", not "a black USB-C cable on the left".
    /// Everything that distinguishes belongs in `note`.
    var name: String
    /// `nil` does not mean zero but uncountable or uncounted — a box of screws, a reel
    /// of wire. An invented 1 would be a number that looks like a count.
    var quantity: Int?
    var unit: String = ""
    var note: String = ""

    var placeID: UUID?
    /// File names in the photo store. The first is the overview photo the entry came
    /// from, if it came from one.
    var photoIDs: [String] = []
    var tags: [String] = []

    var provenance: Provenance = Provenance(origin: .manual)

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// When this thing was last confirmed. On creation that is now, because somebody
    /// then had it in their hand or photographed it.
    var lastSeenAt: Date = Date()

    /// What stands on the thing. Stays on the entry even once the user has rewritten
    /// the name — the number is the only thing here that can be checked.
    var code: ItemCode?

    var embedding: [Float]?
    /// Which model this vector came from. `nil` means: unknown origin and therefore
    /// unusable — the same reason as in Faden's memory.
    var embeddingStamp: EmbeddingStamp?

    init(name: String, quantity: Int? = nil, unit: String = "", note: String = "",
         placeID: UUID? = nil, provenance: Provenance = Provenance(origin: .manual)) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.note = note
        self.placeID = placeID
        self.provenance = provenance
    }

    /// Decoded leniently, as everywhere in these apps: a new field must not invalidate
    /// an existing file. The synthesised decoder throws on a missing key, and here that
    /// would mean: inventory gone.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name           = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        quantity       = try c.decodeIfPresent(Int.self, forKey: .quantity)
        unit           = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        note           = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        placeID        = try c.decodeIfPresent(UUID.self, forKey: .placeID)
        photoIDs       = try c.decodeIfPresent([String].self, forKey: .photoIDs) ?? []
        tags           = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        provenance     = try c.decodeIfPresent(Provenance.self, forKey: .provenance)
                         ?? Provenance(origin: .manual)
        createdAt      = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt      = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        lastSeenAt     = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt) ?? createdAt
        code           = try c.decodeIfPresent(ItemCode.self, forKey: .code)
        embedding      = try c.decodeIfPresent([Float].self, forKey: .embedding)
        embeddingStamp = try c.decodeIfPresent(EmbeddingStamp.self, forKey: .embeddingStamp)
    }

    /// The text that gets embedded. Name, note and tags — not the place: otherwise
    /// every thing in the cellar moves closer to every question about the cellar, and
    /// the search answers with the shelf instead of the thing.
    var embeddableText: String {
        var parts = [name]
        if !note.isEmpty { parts.append(note) }
        if !tags.isEmpty { parts.append(tags.joined(separator: ", ")) }
        // The number goes in too: whoever types "MP1584EN" into the search field is
        // looking for exactly that thing and not something similar.
        if let code, !code.value.isEmpty { parts.append(code.value) }
        return parts.joined(separator: " — ")
    }

    /// Quantity and unit, as they stand on one line.
    var amountLabel: String? {
        guard let quantity else { return unit.isEmpty ? nil : unit }
        return unit.isEmpty ? "\(quantity)" : "\(quantity) \(unit)"
    }

    /// For comparing typed names against recognised ones: capitalisation, accents and
    /// repeated spaces must not produce a second entry.
    static func normalise(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var normalisedName: String { Self.normalise(name) }
}

// MARK: - Herkunft

/// Who wrote this entry.
///
/// For the embeddings the question was "which model does this vector come from", and
/// without an answer the search quietly computed between two spaces. Here it is the
/// same question asked of an inventory entry: did a person type it or did a model read
/// it out of a photo? That is not a detail. A model miscounts, invents objects and
/// reads labels wrong — whoever stands in front of the shelf later and cannot find the
/// number again has to know whose number it was.
struct Provenance: Codable, Equatable, Hashable {
    enum Origin: String, Codable {
        /// Von Hand angelegt.
        case manual
        /// Read from a photo and confirmed by the user. Nothing unconfirmed is ever
        /// stored — which is why there is no case for that.
        case photo
        /// Aus einer Datei eingelesen.
        case imported
    }
    var origin: Origin
    /// The photo the entry came from. The evidence for the entry.
    var photoID: String?
    /// The model name, if a model was involved.
    var model: String?
    var at: Date = Date()

    init(origin: Origin, photoID: String? = nil, model: String? = nil, at: Date = Date()) {
        self.origin = origin
        self.photoID = photoID
        self.model = model
        self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin  = c.decodeLenient(Origin.self, forKey: .origin) ?? .manual
        photoID = try c.decodeIfPresent(String.self, forKey: .photoID)
        model   = try c.decodeIfPresent(String.self, forKey: .model)
        at      = try c.decodeIfPresent(Date.self, forKey: .at) ?? Date()
    }

    var label: String {
        switch origin {
        case .manual:   return String(localized: "von Hand")
        case .photo:    return model.map { String(localized: "aus einem Foto, gelesen von \($0)") }
                            ?? String(localized: "aus einem Foto")
        case .imported: return String(localized: "eingelesen")
        }
    }
}

// MARK: - Alter einer Sichtung

/// How much the entry can still be relied on today.
///
/// The two limits are set, not measured, and that should stand here as such: 30 days,
/// because a month is the rhythm at which a household's supplies turn over, and 180
/// days, because after half a year there is nothing left to say about the contents of
/// a drawer that you would not do better to check. They are deliberately not
/// adjustable — a slider would only have moved the question elsewhere, and three grades
/// are more honest than a percentage that feigns a measurement.
enum Freshness: String {
    case seen, assumed, stale

    static let assumedAfter: TimeInterval = 30 * 24 * 3600
    static let staleAfter: TimeInterval = 180 * 24 * 3600

    static func of(_ item: Item, now: Date = Date()) -> Freshness {
        let age = now.timeIntervalSince(item.lastSeenAt)
        if age < assumedAfter { return .seen }
        if age < staleAfter { return .assumed }
        return .stale
    }

    var label: String {
        switch self {
        case .seen:    return String(localized: "gesehen")
        case .assumed: return String(localized: "vermutet")
        case .stale:   return String(localized: "unbestätigt")
        }
    }
}

// MARK: - Herkunftsstempel eines Vektors

/// Where a vector comes from — the same structure as in Faden's memory, for the same
/// reason.
///
/// Two embeddings are only comparable when they come from the same model. Without the
/// stamp, all that would stand on the entry is the row of numbers: whoever changes the
/// model in the settings keeps the old vectors, and the search then computes between
/// two spaces that have nothing to do with each other. That does not fail, it quietly
/// delivers nonsense.
///
/// The dimension stands beside it because the name alone is not enough: the same model
/// name delivers vectors of different lengths depending on the provider, and a cosine
/// between vectors of different lengths is not miscalculated but simply undefined.
struct EmbeddingStamp: Codable, Equatable, Hashable {
    var model: String
    var dimension: Int

    static func normalise(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func matches(model: String, dimension: Int?) -> Bool {
        guard Self.normalise(self.model) == Self.normalise(model) else { return false }
        guard let dimension else { return true }
        return self.dimension == dimension
    }
}
