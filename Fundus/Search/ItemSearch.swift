import Foundation

/// The search: first what is certain, then what is likely.
///
/// Two routes, and the order is the real decision. A name hit is a certainty, a cosine
/// a guess. Whoever types "Rudi" wants the thing called Rudi first — and not what a
/// model considers related in meaning. The similarity search earns its place on the
/// questions where the words do not match: no substring finds "the black cable with
/// the square plug". It just must not push a certain hit further down.
enum ItemSearch {

    enum Kind: Int, Comparable {
        /// The name begins with the search term.
        case namePrefix = 0
        /// The identifier on the thing contains the search term.
        ///
        /// Directly behind the name prefix, not in front of it: whoever types "Wa"
        /// means "Wandler" and not the part with the number WA12345. Whoever types
        /// "MP1584EN", by contrast, means exactly that one part — and finds it here,
        /// even when the entry is called "Platine".
        case code = 1
        /// The search term stands somewhere in the name.
        case nameContains = 2
        /// It stands in the note or in a tag.
        case sideText = 3
        /// Only the meaning fits.
        case semantic = 4

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .namePrefix, .nameContains: return String(localized: "Name")
            case .code:                      return String(localized: "Nummer")
            case .sideText:                  return String(localized: "Notiz")
            case .semantic:                  return String(localized: "Bedeutung")
            }
        }
    }

    struct Hit: Identifiable, Equatable {
        var item: Item
        var kind: Kind
        /// Only filled in for `semantic`.
        var similarity: Double?
        var id: UUID { item.id }
    }

    /// Substring search over name, identifier, note and tags.
    ///
    /// Insensitive to capitalisation and accents, because nobody types "Lötzinn" with
    /// the right umlaut when they are looking for it in a hurry.
    static func text(_ query: String, in items: [Item]) -> [Hit] {
        let q = Item.normalise(query)
        guard !q.isEmpty else { return [] }

        var hits: [Hit] = []
        for item in items {
            let name = item.normalisedName
            if name.hasPrefix(q) {
                hits.append(Hit(item: item, kind: .namePrefix))
            } else if let value = item.code?.value, !value.isEmpty,
                      Item.normalise(value).contains(q) {
                hits.append(Hit(item: item, kind: .code))
            } else if name.contains(q) {
                hits.append(Hit(item: item, kind: .nameContains))
            } else {
                let side = Item.normalise(item.note + " " + item.tags.joined(separator: " "))
                if side.contains(q) { hits.append(Hit(item: item, kind: .sideText)) }
            }
        }
        return hits
    }

    /// Similarity hits from a query vector.
    ///
    /// `centroid` is subtracted from both sides — query as well as entry. Centring only
    /// one side would be a comparison between two different spaces and therefore
    /// exactly the error the origin stamp is built against.
    static func semantic(_ queryVector: [Float], in items: [Item], model: String,
                         centroid: [Float]?, minimum: Double, limit: Int) -> [Hit] {
        let dimension = Indexer.dominantDimension(items, model: model)
        let q = Indexer.centered(queryVector, by: centroid)

        var scored: [(Item, Double)] = []
        for item in items {
            guard Indexer.isUsable(item, model: model, dimension: dimension),
                  let vector = item.embedding, vector.count == queryVector.count
            else { continue }
            let similarity = cosineSimilarity(q, Indexer.centered(vector, by: centroid))
            if similarity >= minimum { scored.append((item, similarity)) }
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { Hit(item: $0.0, kind: .semantic, similarity: $0.1) }
    }

    /// Puts both routes together.
    ///
    /// A thing that arrives by both routes keeps the *better* one — otherwise a name
    /// hit would stand under "meaning", and the user would read that the app had
    /// guessed where it knew.
    static func merge(_ groups: [Hit]...) -> [Hit] {
        var best: [UUID: Hit] = [:]
        for group in groups {
            for hit in group {
                if let existing = best[hit.item.id], existing.kind <= hit.kind { continue }
                best[hit.item.id] = hit
            }
        }
        return best.values.sorted { a, b in
            if a.kind != b.kind { return a.kind < b.kind }
            if let x = a.similarity, let y = b.similarity, x != y { return x > y }
            // Equal rank: alphabetical, so that the same search twice gives the same
            // list. An order coming out of a dictionary is arbitrary, and a hit list
            // that jumps on every keystroke is unusable.
            return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
        }
    }
}
