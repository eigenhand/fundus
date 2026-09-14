import Foundation

/// Ein Ding im Bestand.
///
/// Die Felder, die nicht offensichtlich sind, stehen hier nicht aus Vollständigkeit,
/// sondern weil ein Bestand ohne sie eine Behauptung ist: `provenance` sagt, wer den
/// Eintrag geschrieben hat, `lastSeenAt`, wann ihn zuletzt jemand mit eigenen Augen
/// gesehen hat. Ein Lagerbestand veraltet, während die Datenbank gleich aussieht wie
/// am ersten Tag — und das ist die eine Unwahrheit, die eine Inventarapp von sich aus
/// erzeugt. Beide Felder sind dagegen gerichtet.
struct Item: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()

    /// Kurz und suchbar: „USB-C-Kabel“, nicht „ein schwarzes USB-C-Kabel links“.
    /// Alles Unterscheidende gehört in `note`.
    var name: String
    /// `nil` heißt nicht null, sondern unzählbar oder ungezählt — ein Karton Schrauben,
    /// eine Rolle Draht. Eine erfundene 1 wäre eine Zahl, die wie eine Zählung aussieht.
    var quantity: Int?
    var unit: String = ""
    var note: String = ""

    var placeID: UUID?
    /// Dateinamen im Bildspeicher. Das erste ist das Übersichtsfoto, aus dem der
    /// Eintrag kam, sofern er aus einem kam.
    var photoIDs: [String] = []
    var tags: [String] = []

    var provenance: Provenance = Provenance(origin: .manual)

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Wann dieses Ding zuletzt bestätigt wurde. Beim Anlegen ist das jetzt, denn da
    /// hat es jemand in der Hand gehabt oder fotografiert.
    var lastSeenAt: Date = Date()

    /// Was am Ding steht. Bleibt am Eintrag, auch wenn der Name inzwischen vom
    /// Nutzer umgeschrieben wurde — die Nummer ist das Einzige hier, was sich
    /// nachprüfen lässt.
    var code: ItemCode?

    var embedding: [Float]?
    /// Aus welchem Modell dieser Vektor stammt. `nil` heißt: unbekannte Herkunft und
    /// damit unbrauchbar — derselbe Grund wie im Gedächtnis von Faden.
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

    /// Nachsichtig dekodiert, wie überall in diesen Apps: ein neues Feld darf keine
    /// bestehende Datei ungültig machen. Der synthetisierte Decoder wirft bei einem
    /// fehlenden Schlüssel, und das hieße hier: Bestand weg.
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

    /// Der Text, der eingebettet wird. Name, Notiz und Schlagworte — nicht der Ort:
    /// sonst rückt jedes Ding im Keller näher an jede Frage nach dem Keller, und die
    /// Suche antwortet mit dem Regal statt mit dem Ding.
    var embeddableText: String {
        var parts = [name]
        if !note.isEmpty { parts.append(note) }
        if !tags.isEmpty { parts.append(tags.joined(separator: ", ")) }
        // Die Nummer mit hinein: wer „MP1584EN“ ins Suchfeld tippt, sucht genau
        // dieses Ding und nicht etwas Ähnliches.
        if let code, !code.value.isEmpty { parts.append(code.value) }
        return parts.joined(separator: " — ")
    }

    /// Menge und Einheit, wie sie in einer Zeile stehen.
    var amountLabel: String? {
        guard let quantity else { return unit.isEmpty ? nil : unit }
        return unit.isEmpty ? "\(quantity)" : "\(quantity) \(unit)"
    }

    /// Für Vergleiche zwischen getippten und erkannten Namen: Groß-/Kleinschreibung,
    /// Akzente und Mehrfach-Leerzeichen sollen keinen zweiten Eintrag erzeugen.
    static func normalise(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var normalisedName: String { Self.normalise(name) }
}

// MARK: - Herkunft

/// Wer diesen Eintrag geschrieben hat.
///
/// Bei den Einbettungen war die Frage „aus welchem Modell stammt dieser Vektor“,
/// und ohne Antwort rechnete die Suche still zwischen zwei Räumen. Hier ist es
/// dieselbe Frage an einen Bestandseintrag: hat den ein Mensch getippt oder ein
/// Modell aus einem Foto gelesen? Das ist kein Detail. Ein Modell verzählt sich,
/// erfindet Gegenstände und liest Etiketten falsch — wer später vor dem Regal steht
/// und die Zahl nicht wiederfindet, muss wissen, wessen Zahl das war.
struct Provenance: Codable, Equatable, Hashable {
    enum Origin: String, Codable {
        /// Von Hand angelegt.
        case manual
        /// Aus einem Foto gelesen und vom Nutzer bestätigt. Unbestätigt wird nichts
        /// gespeichert — deshalb gibt es dafür keinen Fall.
        case photo
        /// Aus einer Datei eingelesen.
        case imported
    }
    var origin: Origin
    /// Das Foto, aus dem der Eintrag kam. Der Beleg zum Eintrag.
    var photoID: String?
    /// Der Modellname, falls ein Modell beteiligt war.
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
        case .manual:   return "von Hand"
        case .photo:    return model.map { "aus einem Foto, gelesen von \($0)" } ?? "aus einem Foto"
        case .imported: return "eingelesen"
        }
    }
}

// MARK: - Alter einer Sichtung

/// Wie belastbar der Eintrag heute noch ist.
///
/// Die beiden Grenzen sind gesetzt, nicht gemessen, und das soll hier auch so
/// stehen: 30 Tage, weil ein Monat der Takt ist, in dem sich ein Haushaltsvorrat
/// umschlägt, und 180 Tage, weil nach einem halben Jahr über den Inhalt einer
/// Schublade nichts mehr zu sagen ist, was man nicht besser nachsieht. Sie sind
/// bewusst nicht einstellbar — ein Regler hätte nur die Frage verschoben, und drei
/// Stufen sind ehrlicher als eine Prozentzahl, die eine Messung vortäuscht.
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
        case .seen:    return "gesehen"
        case .assumed: return "vermutet"
        case .stale:   return "unbestätigt"
        }
    }
}

// MARK: - Herkunftsstempel eines Vektors

/// Woher ein Vektor stammt — dieselbe Struktur wie in Fadens Gedächtnis, aus
/// demselben Grund.
///
/// Zwei Einbettungen sind nur vergleichbar, wenn sie aus demselben Modell kommen.
/// Ohne den Stempel stünde am Eintrag nur die Zahlenreihe: wer in den Einstellungen
/// das Modell wechselt, behält die alten Vektoren, und die Suche rechnet danach
/// zwischen zwei Räumen, die nichts miteinander zu tun haben. Das schlägt nicht
/// fehl, es liefert still Unsinn.
///
/// Die Dimension steht dabei, weil der Name allein nicht reicht: derselbe
/// Modellname liefert je nach Anbieter unterschiedlich lange Vektoren, und ein
/// Kosinus zwischen verschieden langen Vektoren ist nicht falsch berechnet, sondern
/// gar nicht definiert.
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
