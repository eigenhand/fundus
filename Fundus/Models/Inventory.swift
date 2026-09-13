import Foundation

/// Der Bestand: Dinge und Orte in einem Dokument.
///
/// Ein Werttyp mit reinen Funktionen darauf, nicht ein Speicher mit Zustand. Der
/// Grund ist Prüfbarkeit: „ein zweites Foto derselben Schublade darf keine Dubletten
/// anlegen“ ist eine Aussage über `absorb`, und die will man in einem Test schreiben
/// können, ohne eine Datei, einen Endpoint oder eine Oberfläche zu haben.
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

    /// Dinge an diesem Ort — mit `includingBelow` auch alles in den Unterorten.
    func items(at placeID: UUID, includingBelow: Bool = true) -> [Item] {
        let ids = includingBelow ? tree.subtree(of: placeID) : [placeID]
        return items.filter { $0.placeID.map(ids.contains) ?? false }
    }

    /// Dinge ohne Ort. Kein Sonderfall, sondern der Normalfall beim schnellen
    /// Eintragen — den Ort trägt man nach, wenn man das Ding wegräumt.
    var unplaced: [Item] { items.filter { $0.placeID == nil } }

    /// Ein Ding gleichen Namens am selben Ort. Der Vergleich ist unempfindlich gegen
    /// Groß-/Kleinschreibung und Akzente, weil das Modell „USB-C-Kabel“ und ein
    /// getippter Eintrag „USB-C Kabel“ dasselbe Ding meinen.
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

    /// „Gesehen“: das Datum, auf dem die ganze Verlässlichkeit dieser App beruht.
    ///
    /// Rührt den Vektor nicht an. Eine Sichtung ändert nichts am Text und damit
    /// nichts an der Einbettung — den Index deswegen neu zu rechnen wäre Arbeit
    /// ohne Wirkung.
    mutating func markSeen(_ id: UUID, at date: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].lastSeenAt = date
        items[i].updatedAt = date
    }

    /// Nimmt einen bestätigten Vorschlag auf — entweder als neues Ding oder als
    /// Zuwachs auf einem, das schon dasteht.
    ///
    /// Das ist die Stelle, an der sich entscheidet, ob die App das zweite Foto
    /// derselben Schublade überlebt. Ohne sie stünden nach zwei Aufnahmen zwei
    /// „USB-C-Kabel“ am selben Ort, und ab da ist der Bestand nicht mehr ein
    /// Bestand, sondern eine Liste von Beobachtungen.
    ///
    /// Bei einem Treffer wird die Menge addiert und nicht ersetzt: das Foto zeigt,
    /// was zu sehen war, nicht was vorhanden ist. Ersetzen würde ein halb verdecktes
    /// Regal zu einer Bestandskorrektur nach unten machen.
    @discardableResult
    mutating func absorb(_ proposal: Proposal, at placeID: UUID?, photoID: String?,
                         model: String?) -> Outcome {
        // `effectiveName`, nicht `name`: hat der Nutzer den Fund aus der Websuche
        // angehakt, ist dessen Titel der Name — sonst der, den das Modell im Bild
        // gelesen hat.
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
            // Eine Kennung am bestehenden Eintrag wird nicht überschrieben: die erste
            // stand da, als jemand sie bestätigt hat. Eine fehlende wird ergänzt —
            // das zweite Foto zeigt das Typenschild vielleicht schärfer.
            if found.code == nil { found.code = proposal.code }
            found.lastSeenAt = Date()
            update(found)
            return .increased(found.id)
        }

        var item = Item(name: clean, quantity: proposal.quantity, unit: proposal.unit,
                        note: proposal.note, placeID: placeID,
                        provenance: Provenance(origin: .photo, photoID: photoID, model: model))
        if let photoID { item.photoIDs = [photoID] }
        item.code = proposal.code
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

    /// Verschiebt einen Ort. Ein Zug in den eigenen Unterbaum wird abgelehnt, statt
    /// den Baum in einen Ring zu verwandeln — aus dem käme kein Pfad mehr zurück.
    @discardableResult
    mutating func movePlace(_ id: UUID, under parent: UUID?) -> Bool {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return false }
        if let parent {
            guard parent != id, !tree.isDescendant(parent, of: id) else { return false }
        }
        places[i].parentID = parent
        return true
    }

    /// Löscht einen Ort und alles darunter. Die Dinge bleiben — sie liegen dann
    /// nirgends, was stimmt und sichtbar ist. Sie mitzulöschen würde einen Bestand
    /// vernichten, weil jemand ein Regal umbenennen wollte.
    mutating func removePlace(_ id: UUID) {
        let gone = tree.subtree(of: id)
        places.removeAll { gone.contains($0.id) }
        for i in items.indices where items[i].placeID.map(gone.contains) ?? false {
            items[i].placeID = nil
            items[i].updatedAt = Date()
        }
    }
}

/// Ein Vorschlag, wie er aus einem Foto kommt — noch kein Eintrag.
///
/// Eigener Typ und nicht ein halbfertiges `Item`: ein Vorschlag hat keine ID, keine
/// Herkunft und kein Sichtungsdatum, und ein `Item`, das im Speicher liegt, ohne
/// bestätigt zu sein, ist genau die Vermischung, die diese App nicht haben soll.
struct Proposal: Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var quantity: Int?
    var unit: String = ""
    var note: String = ""
    /// Eine Nummer, die am Ding steht — dekodiert oder abgelesen, siehe `ItemCode`.
    var code: ItemCode?
    /// Vom Nutzer im Prüfschritt abgewählt.
    var accepted: Bool = true
    /// Ob der Nutzer den Namen aus der Websuche übernehmen will.
    ///
    /// Getrennt vom Häkchen für den Eintrag selbst, und das ist der Kern der
    /// Absicherung: man kann den Fund behalten und die Deutung verwerfen. Startet
    /// aus, anders als `accepted` — eine Kette aus drei fehlbaren Gliedern bekommt
    /// nicht dieselbe Vorleistung wie das, was das Modell mit eigenen Augen sah.
    var useLookupName: Bool = false

    /// Der Name, der beim Annehmen wirklich gespeichert wird.
    var effectiveName: String {
        if useLookupName, let title = code?.lookup?.title, !title.isEmpty { return title }
        return name
    }
}
