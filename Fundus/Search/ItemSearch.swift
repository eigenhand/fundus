import Foundation

/// Die Suche: erst was sicher ist, dann was wahrscheinlich ist.
///
/// Zwei Wege, und die Reihenfolge ist die eigentliche Entscheidung. Ein Namenstreffer
/// ist eine Gewissheit, ein Kosinus eine Vermutung. Wer „Rudi“ tippt, will das Ding,
/// das Rudi heißt, an erster Stelle — und nicht das, was ein Modell für sinnverwandt
/// hält. Die Ähnlichkeitssuche verdient ihren Platz auf den Fragen, bei denen die
/// Wörter nicht übereinstimmen: „das schwarze Kabel mit dem eckigen Stecker“ findet
/// kein Teilstring. Sie darf nur keinen sicheren Treffer nach unten schieben.
enum ItemSearch {

    enum Kind: Int, Comparable {
        /// Der Name beginnt mit dem Suchwort.
        case namePrefix = 0
        /// Die Kennung am Ding enthält das Suchwort.
        ///
        /// Direkt hinter dem Namensanfang, nicht davor: wer „Wa“ tippt, meint
        /// „Wandler“ und nicht das Teil mit der Nummer WA12345. Wer dagegen
        /// „MP1584EN“ tippt, meint genau dieses eine Teil — und findet es hier,
        /// auch wenn der Eintrag „Platine“ heißt.
        case code = 1
        /// Das Suchwort steht irgendwo im Namen.
        case nameContains = 2
        /// Es steht in Notiz oder Schlagwort.
        case sideText = 3
        /// Nur die Bedeutung passt.
        case semantic = 4

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .namePrefix, .nameContains: return "Name"
            case .code:                      return "Nummer"
            case .sideText:                  return "Notiz"
            case .semantic:                  return "Bedeutung"
            }
        }
    }

    struct Hit: Identifiable, Equatable {
        var item: Item
        var kind: Kind
        /// Nur bei `semantic` gefüllt.
        var similarity: Double?
        var id: UUID { item.id }
    }

    /// Teilstringsuche über Name, Kennung, Notiz und Schlagworte.
    ///
    /// Unempfindlich gegen Groß-/Kleinschreibung und Akzente, weil niemand „Lötzinn“
    /// mit dem richtigen Umlaut tippt, wenn er es schnell sucht.
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

    /// Ähnlichkeitstreffer aus einem Abfragevektor.
    ///
    /// `centroid` wird von beiden Seiten abgezogen — Abfrage wie Eintrag. Nur eine
    /// Seite zu zentrieren wäre ein Vergleich zwischen zwei verschiedenen Räumen und
    /// damit genau der Fehler, gegen den der Herkunftsstempel gebaut ist.
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

    /// Legt beide Wege zusammen.
    ///
    /// Ein Ding, das auf beiden Wegen kommt, behält den *besseren* Weg — sonst stünde
    /// ein Namenstreffer unter „Bedeutung“, und der Nutzer würde lesen, die App habe
    /// geraten, wo sie gewusst hat.
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
            // Gleichrangig: alphabetisch, damit dieselbe Suche zweimal dieselbe
            // Liste ergibt. Eine Reihenfolge aus einem Dictionary ist zufällig, und
            // eine Trefferliste, die bei jedem Tastendruck springt, ist unbenutzbar.
            return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
        }
    }
}
