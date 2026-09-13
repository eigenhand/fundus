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

/// Was eine Websuche zu einer Kennung ergeben hat.
///
/// Mit Quelle und Zeitpunkt, und das ist kein Zierrat: ein aufgelöster Produktname
/// sieht verlässlicher aus als alles andere im Bestand, obwohl er auf der Kette
/// „Foto → abgelesene Ziffern → Suchmaschine → zusammengefasst“ steht. Wer später
/// vor dem Regal steht und etwas anderes in der Hand hält, muss die Kette
/// zurückverfolgen können.
struct CodeLookup: Codable, Equatable, Hashable {
    /// Wonach gesucht wurde — wörtlich, damit eine falsch gelesene Nummer als
    /// solche erkennbar bleibt.
    var query: String
    /// Was das Ding laut Suche ist. Kurz, wie ein Eintragsname.
    var title: String
    /// Ein, zwei Sätze dazu.
    var summary: String = ""
    var sourceURL: String = ""
    var sourceName: String = ""
    var searchedAt: Date = Date()
    /// Wie sicher sich das Modell beim Zuordnen war. Bleibt `false`, wenn die
    /// Treffer nicht eindeutig zur Kennung passten.
    var confident: Bool = false

    init(query: String, title: String, summary: String = "", sourceURL: String = "",
         sourceName: String = "", searchedAt: Date = Date(), confident: Bool = false) {
        self.query = query
        self.title = title
        self.summary = summary
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.searchedAt = searchedAt
        self.confident = confident
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query      = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        title      = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary    = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sourceURL  = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        searchedAt = try c.decodeIfPresent(Date.self, forKey: .searchedAt) ?? Date()
        confident  = try c.decodeIfPresent(Bool.self, forKey: .confident) ?? false
    }
}
