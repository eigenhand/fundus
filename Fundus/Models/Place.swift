import Foundation

/// Ein Ort: Keller, Regal 2, Kiste C.
///
/// Als Baum und nicht als Zeichenkette, weil die Frage, die eine Inventarapp
/// beantworten muss, „wo liegt das“ ist und nicht „wie heißt der Ort“. Ein Baum
/// lässt „alles im Keller“ beantworten, ohne dass irgendwo „Keller / Regal 2“ als
/// Text steht, der beim Umbenennen des Kellers stehenbleibt.
struct Place: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID?
    var note: String = ""
    var createdAt: Date = Date()

    init(name: String, parentID: UUID? = nil, note: String = "") {
        self.name = name
        self.parentID = parentID
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name      = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        parentID  = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        note      = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// Die Orte als Baum, mit den Fragen, die die Oberfläche stellt.
///
/// Eigener Typ und nicht ein paar freie Funktionen, weil jede dieser Fragen sonst
/// die ganze Liste durchläuft: die Kinderlisten werden einmal gebaut und dann
/// mehrfach benutzt.
struct PlaceTree {
    let places: [UUID: Place]
    private let children: [UUID?: [UUID]]

    init(_ all: [Place]) {
        // Lokal und nicht über `self.places`: eine Closure, die `self` anfasst,
        // während `children` noch nicht steht, lässt der Compiler nicht zu — und zu
        // Recht.
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        places = byID

        var kids: [UUID?: [UUID]] = [:]
        for p in all { kids[p.parentID, default: []].append(p.id) }
        // Geschwister alphabetisch, damit dieselbe Liste zweimal gleich aussieht.
        children = kids.mapValues { ids in
            ids.sorted {
                (byID[$0]?.name ?? "").localizedStandardCompare(byID[$1]?.name ?? "")
                    == .orderedAscending
            }
        }
    }

    var roots: [UUID] { children[nil] ?? [] }
    func childIDs(of id: UUID) -> [UUID] { children[id] ?? [] }

    /// Der Pfad von der Wurzel bis hierher, etwa „Keller · Regal 2 · Kiste C“.
    ///
    /// Mit Tiefenbegrenzung: ein Ort, der versehentlich zu seinem eigenen Vorfahren
    /// wird, würde diese Schleife sonst nicht verlassen. Das kann durch eine
    /// verschobene Zuordnung entstehen, und ein Aufhänger beim Zeichnen einer Zeile
    /// wäre der teuerste denkbare Weg, davon zu erfahren.
    func path(of id: UUID, separator: String = " · ") -> String {
        var names: [String] = []
        var current: UUID? = id
        var guardCount = 0
        while let c = current, let place = places[c], guardCount < 32 {
            names.append(place.name)
            current = place.parentID
            guardCount += 1
        }
        return names.reversed().joined(separator: separator)
    }

    /// Dieser Ort und alles darunter — für „alles im Keller“.
    func subtree(of id: UUID) -> Set<UUID> {
        var out: Set<UUID> = []
        var stack = [id]
        while let next = stack.popLast() {
            guard out.insert(next).inserted else { continue }
            stack.append(contentsOf: childIDs(of: next))
        }
        return out
    }

    /// Ob `candidate` unter `id` liegt. Verhindert, dass ein Ort in seinen eigenen
    /// Unterbaum verschoben wird und den Baum in einen Ring verwandelt.
    func isDescendant(_ candidate: UUID, of id: UUID) -> Bool {
        candidate != id && subtree(of: id).contains(candidate)
    }

    /// Alle Orte in Baumreihenfolge, mit ihrer Tiefe — so wird eine flache Liste
    /// gezeichnet, die einen Baum zeigt.
    func flattened() -> [(place: Place, depth: Int)] {
        var out: [(Place, Int)] = []
        func walk(_ ids: [UUID], _ depth: Int) {
            for id in ids {
                guard let p = places[id] else { continue }
                out.append((p, depth))
                walk(childIDs(of: id), depth + 1)
            }
        }
        walk(roots, 0)
        return out.map { (place: $0.0, depth: $0.1) }
    }
}
