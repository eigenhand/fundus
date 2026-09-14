import Foundation

/// Eine Kennung, die an einem Ding steht: die EAN unter einem Barcode, eine
/// Herstellernummer auf einer Platine, eine Seriennummer auf einem Typenschild.
///
/// Der wichtigste Teil ist `origin`. Eine von iOS aus dem Bild dekodierte EAN ist
/// exakt — Prüfziffer und alles. Eine Nummer, die ein Modell von einem unscharfen
/// Aufkleber abgelesen hat, ist eine Vermutung, bei der ein einziges verwechseltes
/// Zeichen auf ein völlig anderes Bauteil zeigt. Beides in dasselbe Feld zu
/// schreiben und gleich auszusehen wäre die teuerste Vereinfachung dieser App:
/// danach sucht man im Netz nach einer erfundenen Nummer und bekommt ein präzises,
/// falsches Ergebnis.
struct ItemCode: Codable, Equatable, Hashable {

    enum Origin: String, Codable {
        /// Von iOS aus dem Bild dekodiert. Exakt.
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
    /// Was eine Websuche daraus gemacht hat, falls eine lief.
    var lookup: CodeLookup?

    /// Ob diese Kennung überhaupt eine Suche wert ist.
    ///
    /// Zu kurze Zeichenfolgen treffen alles und nichts: „A4“, „12“, „M8“ stehen auf
    /// tausend Dingen. Eine Suche darauf kostet einen Aufruf und liefert Rauschen,
    /// das danach wie ein Befund aussieht.
    var isSearchable: Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard v.count >= 4 else { return false }
        // Mindestens eine Ziffer: reine Wörter sind Beschriftungen, keine Kennungen.
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
        kind   = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .unknown
        origin = try c.decodeIfPresent(Origin.self, forKey: .origin) ?? .read
        lookup = try c.decodeIfPresent(CodeLookup.self, forKey: .lookup)
    }
}

/// Eine Möglichkeit, was das Ding sein könnte.
///
/// `match` ist der Grund, warum eine Liste besser ist als ein Urteil. Eine abgelesene
/// Nummer ist selten zeichengenau — eine 0 als O, eine 8 als 9 —, und die Suche findet
/// das richtige Bauteil trotzdem, nur nicht unter genau dieser Schreibweise. Ob das
/// dasselbe Ding ist, entscheidet in einer Sekunde, wer es in der Hand hält. Damit er
/// das kann, muss er sehen, *wie weit* daneben der Vorschlag liegt: wörtlich derselbe
/// Aufdruck, zwei Zeichen anders, oder nur dieselbe Baureihe.
struct CodeCandidate: Codable, Equatable, Hashable {

    enum Match: String, Codable {
        /// Die Kennung steht wörtlich so in einem Treffer.
        case exact
        /// Ein, zwei Zeichen anders — siehe `codeSeen`.
        case near
        /// Dieselbe Baureihe, andere Ausführung.
        case family

        var label: String {
            switch self {
            case .exact:  return "steht so im Treffer"
            case .near:   return "fast dieselbe Nummer"
            case .family: return "gleiche Baureihe"
            }
        }
    }

    /// Kurz und sachlich, wie ein Eintrag im Bestand.
    var title: String
    var summary: String = ""
    var sourceURL: String = ""
    var sourceName: String = ""
    var match: Match = .family
    /// Wie die Nummer im Treffer wirklich lautet, wenn sie von der gelesenen abweicht.
    /// Das ist die Zeile, an der ein Mensch „ja, das ist meins“ erkennt.
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
        match      = try c.decodeIfPresent(Match.self, forKey: .match) ?? .family
        codeSeen   = try c.decodeIfPresent(String.self, forKey: .codeSeen) ?? ""
    }
}

/// Was eine Websuche zu einer Kennung ergeben hat: eine kurze Auswahlliste.
///
/// Hier stand einmal ein einzelner Titel mit einem `confident`-Haken, und die Regel
/// war: passt es nicht eindeutig, kommt gar nichts. Das war die falsche Strenge. Bei
/// einer abgelesenen Nummer ist „nicht eindeutig“ der Normalfall, und die Antwort
/// darauf war dann regelmäßig eine leere Zeile — obwohl in den Treffern das richtige
/// Bauteil stand, nur zwei Zeichen anders geschrieben.
///
/// Jetzt trägt die App vor, statt zu urteilen: bis zu drei Möglichkeiten, die nächste
/// zuerst, jede mit der Nummer, die im Treffer wirklich stand. Der Nutzer tippt eine
/// an oder keine. Das Versprechen bleibt dasselbe — nichts wird stillschweigend
/// ersetzt —, nur trifft die Entscheidung jetzt der, der das Ding in der Hand hat.
///
/// Mit Suchanfrage und Zeitpunkt, und das ist kein Zierrat: ein aufgelöster
/// Produktname sieht verlässlicher aus als alles andere im Bestand, obwohl er auf der
/// Kette „Foto → abgelesene Ziffern → Suchmaschine → zusammengefasst“ steht. Wer
/// später vor dem Regal steht und etwas anderes in der Hand hält, muss die Kette
/// zurückverfolgen können.
struct CodeLookup: Codable, Equatable, Hashable {
    /// Wonach gesucht wurde — wörtlich, damit eine falsch gelesene Nummer als solche
    /// erkennbar bleibt.
    var query: String
    /// Die Vorschläge, der wahrscheinlichste zuerst. Nie mehr als `maxCandidates`.
    var candidates: [CodeCandidate] = []
    /// Welchen der Nutzer genommen hat. `nil` heißt: keinen — und das ist eine
    /// Antwort, keine offene Frage.
    var chosen: Int?
    /// Die Suche oder das Modell sind nicht durchgekommen.
    ///
    /// Der Unterschied zu einer leeren Liste ist für den Nutzer der ganze Punkt:
    /// „nichts Passendes gefunden“ ist ein Ergebnis, „die Suche kam nicht durch“ ist
    /// ein Grund, es gleich noch einmal zu versuchen. Vorher sahen beide gleich aus —
    /// wie eine leere Zeile, an der nichts darauf hinwies, dass überhaupt jemand
    /// gesucht hatte.
    var failed: Bool = false
    var searchedAt: Date = Date()

    static let maxCandidates = 3

    /// Der Vorschlag, den man zeigt, wenn man nur einen zeigen kann: der gewählte,
    /// sonst der erste. Am Bestandseintrag steht daneben, welcher Fall es war.
    var best: CodeCandidate? {
        if let chosen, candidates.indices.contains(chosen) { return candidates[chosen] }
        return candidates.first
    }

    /// Was in der Oberfläche steht, wenn keine Vorschläge dastehen.
    var emptyReason: String? {
        guard candidates.isEmpty else { return nil }
        return failed ? "Nachschlagen fehlgeschlagen" : "nichts Passendes gefunden"
    }

    init(query: String, candidates: [CodeCandidate] = [], chosen: Int? = nil,
         failed: Bool = false, searchedAt: Date = Date()) {
        self.query = query
        self.candidates = Array(candidates.prefix(Self.maxCandidates))
        self.chosen = chosen
        self.failed = failed
        self.searchedAt = searchedAt
    }

    /// Liest auch die alte Form: ein flaches `title`/`summary`/`source`/`confident`.
    ///
    /// Ein Bestand, der vor dieser Änderung angelegt wurde, hat genau diese Felder auf
    /// der Platte. Sie werden zu einem einzelnen Vorschlag — `confident` war die
    /// Aussage „steht wörtlich in einem Treffer“ und heißt heute `match: .exact`.
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
