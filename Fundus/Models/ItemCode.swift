import Foundation

/// An identifier that stands on a thing: the EAN under a barcode, a manufacturer part
/// number on a board, a serial number on a rating plate.
///
/// The most important part is `origin`. An EAN decoded from the image by iOS is exact
/// — check digit and all. A number a model read off a blurred sticker is a guess in
/// which a single confused character points at a completely different component.
/// Writing both into the same field and having them look alike would be the most
/// expensive simplification in this app: after it you search the web for an invented
/// number and get a precise, wrong result.
struct ItemCode: Codable, Equatable, Hashable {

    enum Origin: String, Codable {
        /// Decoded from the image by iOS. Exact.
        case scanned
        /// Vom Modell abgelesen. Kann falsch sein.
        case read
    }

    enum Kind: String, Codable {
        case ean, upc, qr, dataMatrix, code128
        /// Herstellernummer (MPN) — „MP1584EN“, „BC547B“.
        case manufacturer
        case serial
        case unknown
    }

    var value: String
    var kind: Kind = .unknown
    var origin: Origin = .read
    /// What a web search made of it, if one ran.
    var lookup: CodeLookup?

    /// Whether this identifier is worth a search at all.
    ///
    /// Strings that are too short hit everything and nothing: "A4", "12", "M8" stand
    /// on a thousand things. A search on those costs a call and returns noise that
    /// afterwards looks like a finding.
    var isSearchable: Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard v.count >= 4 else { return false }
        // At least one digit: pure words are labels, not identifiers.
        return v.rangeOfCharacter(from: .decimalDigits) != nil
    }

    var label: String {
        switch kind {
        case .ean, .upc:        return "EAN"
        case .qr:               return "QR"
        case .dataMatrix:       return "DataMatrix"
        case .code128:          return "Code 128"
        case .manufacturer:     return "Herstellernummer"
        case .serial:           return "Seriennummer"
        case .unknown:          return "Kennung"
        }
    }

    init(value: String, kind: Kind = .unknown, origin: Origin = .read,
         lookup: CodeLookup? = nil) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.origin = origin
        self.lookup = lookup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value  = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        kind   = c.decodeLenient(Kind.self, forKey: .kind) ?? .unknown
        origin = c.decodeLenient(Origin.self, forKey: .origin) ?? .read
        lookup = try c.decodeIfPresent(CodeLookup.self, forKey: .lookup)
    }
}

/// One possibility of what the thing might be.
///
/// `match` is the reason a list is better than a verdict. A number read by eye is
/// rarely exact to the character — a 0 as an O, an 8 as a 9 — and the search finds the
/// right component all the same, only not under that exact spelling. Whether it is the
/// same thing is decided in a second by whoever holds it in their hand. For them to be
/// able to do that, they have to see *how far* off the suggestion lies: literally the
/// same lettering, two characters different, or only the same series.
struct CodeCandidate: Codable, Equatable, Hashable {

    enum Match: String, Codable {
        /// The identifier appears verbatim in a hit.
        case exact
        /// Ein, zwei Zeichen anders — siehe `codeSeen`.
        case near
        /// The same series, a different variant.
        case family

        var label: String {
            switch self {
            case .exact:  return String(localized: "steht so im Treffer")
            case .near:   return String(localized: "fast dieselbe Nummer")
            case .family: return String(localized: "gleiche Baureihe")
            }
        }
    }

    /// Short and factual, like an entry in the inventory.
    var title: String
    var summary: String = ""
    var sourceURL: String = ""
    var sourceName: String = ""
    var match: Match = .family
    /// What the number in the hit actually says, when it differs from the one that was
    /// read. This is the line at which a person recognises "yes, that is mine".
    var codeSeen: String = ""

    init(title: String, summary: String = "", sourceURL: String = "",
         sourceName: String = "", match: Match = .family, codeSeen: String = "") {
        self.title = title
        self.summary = summary
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.match = match
        self.codeSeen = codeSeen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title      = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary    = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sourceURL  = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        match      = c.decodeLenient(Match.self, forKey: .match) ?? .family
        codeSeen   = try c.decodeIfPresent(String.self, forKey: .codeSeen) ?? ""
    }
}

/// What a web search produced for an identifier: a short list to choose from.
///
/// A single title with a `confident` tick used to stand here, and the rule was: if it
/// does not fit unambiguously, nothing comes back. That was the wrong kind of
/// strictness. For a number read by eye, "not unambiguous" is the normal case, and the
/// answer to it was then regularly an empty line — even though the right component
/// stood among the hits, merely spelled two characters differently.
///
/// Now the app presents rather than judges: up to three possibilities, the nearest
/// first, each with the number that actually stood in the hit. The user taps one or
/// none. The promise stays the same — nothing is silently replaced — only the decision
/// is now made by whoever has the thing in their hand.
///
/// With the search query and the timestamp, and that is not decoration: a resolved
/// product name looks more reliable than anything else in the inventory, even though
/// it stands at the end of the chain "photo → digits read by eye → search engine →
/// summarised". Whoever stands in front of the shelf later holding something else has
/// to be able to trace that chain back.
struct CodeLookup: Codable, Equatable, Hashable {
    /// What was searched for — verbatim, so that a misread number stays recognisable
    /// as one.
    var query: String
    /// The suggestions, the most likely first. Never more than `maxCandidates`.
    var candidates: [CodeCandidate] = []
    /// Which one the user took. `nil` means: none — and that is an answer, not an open
    /// question.
    var chosen: Int?
    /// The search or the model did not get through.
    ///
    /// The difference from an empty list is the whole point for the user: "nothing
    /// suitable found" is a result, "the search did not get through" is a reason to try
    /// again straight away. Before, both looked the same — like an empty line with
    /// nothing to suggest that anybody had searched at all.
    var failed: Bool = false
    var searchedAt: Date = Date()

    static let maxCandidates = 3

    /// The suggestion to show when only one can be shown: the chosen one, otherwise
    /// the first. The inventory entry says beside it which of the two it was.
    var best: CodeCandidate? {
        if let chosen, candidates.indices.contains(chosen) { return candidates[chosen] }
        return candidates.first
    }

    /// What the interface says when no suggestions stand there.
    var emptyReason: String? {
        guard candidates.isEmpty else { return nil }
        return failed ? String(localized: "Nachschlagen fehlgeschlagen")
                      : String(localized: "nichts Passendes gefunden")
    }

    init(query: String, candidates: [CodeCandidate] = [], chosen: Int? = nil,
         failed: Bool = false, searchedAt: Date = Date()) {
        self.query = query
        self.candidates = Array(candidates.prefix(Self.maxCandidates))
        self.chosen = chosen
        self.failed = failed
        self.searchedAt = searchedAt
    }

    /// Reads the old shape too: a flat `title`/`summary`/`source`/`confident`.
    ///
    /// An inventory created before this change has exactly those fields on disk. They
    /// become one single suggestion — `confident` was the statement "appears verbatim
    /// in a hit" and today goes by `match: .exact`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query      = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        chosen     = try c.decodeIfPresent(Int.self, forKey: .chosen)
        failed     = try c.decodeIfPresent(Bool.self, forKey: .failed) ?? false
        searchedAt = try c.decodeIfPresent(Date.self, forKey: .searchedAt) ?? Date()

        if let list = try c.decodeIfPresent([CodeCandidate].self, forKey: .candidates) {
            candidates = Array(list.prefix(Self.maxCandidates))
            return
        }

        let old = try decoder.container(keyedBy: LegacyKeys.self)
        let title = (try old.decodeIfPresent(String.self, forKey: .title) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { candidates = []; return }
        candidates = [CodeCandidate(
            title: title,
            summary: try old.decodeIfPresent(String.self, forKey: .summary) ?? "",
            sourceURL: try old.decodeIfPresent(String.self, forKey: .sourceURL) ?? "",
            sourceName: try old.decodeIfPresent(String.self, forKey: .sourceName) ?? "",
            match: (try old.decodeIfPresent(Bool.self, forKey: .confident) ?? false)
                ? .exact : .near)]
    }

    private enum LegacyKeys: String, CodingKey {
        case title, summary, sourceURL, sourceName, confident
    }
}
