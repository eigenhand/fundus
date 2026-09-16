import Foundation

/// A place: cellar, shelf 2, box C.
///
/// As a tree and not as a string, because the question an inventory app has to answer
/// is "where is it" and not "what is the place called". A tree lets "everything in the
/// cellar" be answered without "cellar / shelf 2" standing anywhere as text that stays
/// behind when the cellar is renamed.
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

/// The places as a tree, with the questions the interface asks.
///
/// Its own type and not a few free functions, because otherwise each of these questions
/// would walk the whole list: the child lists are built once and then used several
/// times.
struct PlaceTree {
    let places: [UUID: Place]
    private let children: [UUID?: [UUID]]

    init(_ all: [Place]) {
        // Local and not via `self.places`: the compiler does not allow a closure that
        // touches `self` while `children` is not yet in place — and rightly so.
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        places = byID

        var kids: [UUID?: [UUID]] = [:]
        for p in all { kids[p.parentID, default: []].append(p.id) }
        // Siblings alphabetically, so that the same list looks the same twice.
        children = kids.mapValues { ids in
            ids.sorted {
                (byID[$0]?.name ?? "").localizedStandardCompare(byID[$1]?.name ?? "")
                    == .orderedAscending
            }
        }
    }

    var roots: [UUID] { children[nil] ?? [] }
    func childIDs(of id: UUID) -> [UUID] { children[id] ?? [] }

    /// The path from the root down to here, for instance "Keller · Regal 2 · Kiste C".
    ///
    /// With a depth limit: a place that accidentally becomes its own ancestor would
    /// otherwise never leave this loop. That can come about through a moved assignment,
    /// and a hang while drawing a row would be the most expensive conceivable way of
    /// finding out about it.
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

    /// This place and everything under it — for "everything in the cellar".
    func subtree(of id: UUID) -> Set<UUID> {
        var out: Set<UUID> = []
        var stack = [id]
        while let next = stack.popLast() {
            guard out.insert(next).inserted else { continue }
            stack.append(contentsOf: childIDs(of: next))
        }
        return out
    }

    /// Whether `candidate` lies under `id`. Prevents a place being moved into its own
    /// subtree and turning the tree into a ring.
    func isDescendant(_ candidate: UUID, of id: UUID) -> Bool {
        candidate != id && subtree(of: id).contains(candidate)
    }

    /// Every place in tree order, with its depth — that is how a flat list gets drawn
    /// that shows a tree.
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
