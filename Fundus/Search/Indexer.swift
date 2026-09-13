import Foundation

/// Der Zustand des Suchindex — und die Arbeit, ihn wieder gerade zu ziehen.
///
/// Dieselbe Klassifizierung wie in Fadens Gedächtnis, und aus demselben Grund: ein
/// Vektor ohne Herkunft ist so gut wie ein falscher. Wer in den Einstellungen die
/// Quelle von „auf dem Gerät“ auf einen Endpoint umstellt, hat damit jeden
/// bestehenden Vektor unbrauchbar gemacht — nicht kaputt, sondern unvergleichbar,
/// was schlimmer ist, weil es weiter Zahlen liefert. Der Stempel macht das sichtbar,
/// diese Datei macht es zählbar.
enum Indexer {

    struct Status: Equatable {
        /// Vektor vorhanden und vom eingestellten Modell — nutzbar.
        var usable = 0
        /// Vektor vorhanden, aber aus einem anderen Modell oder mit anderer
        /// Dimension. Rechnerisch unbrauchbar, muss neu eingebettet werden.
        var foreign = 0
        /// Noch gar kein Vektor.
        var missing = 0
        /// Welche Modelle im Index stecken, mit Anzahl — damit sichtbar ist, *was*
        /// da liegt, statt nur, dass etwas nicht passt.
        var byModel: [String: Int] = [:]
        /// Die Dimension, auf die sich das eingestellte Modell eingependelt hat.
        var dimension: Int?

        var total: Int { usable + foreign + missing }
        var needsWork: Int { foreign + missing }
        var isClean: Bool { needsWork == 0 }
    }

    /// Die Dimension, die das eingestellte Modell hier tatsächlich liefert.
    ///
    /// Nicht aus einer Tabelle, sondern aus dem Bestand: Anbieter ändern die Länge
    /// unter demselben Modellnamen. Die häufigste gewinnt; Ausreißer gelten damit
    /// als fremd und werden neu geholt.
    static func dominantDimension(_ items: [Item], model: String) -> Int? {
        let wanted = EmbeddingStamp.normalise(model)
        var counts: [Int: Int] = [:]
        for stamp in items.compactMap(\.embeddingStamp)
        where EmbeddingStamp.normalise(stamp.model) == wanted {
            counts[stamp.dimension, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    static func status(_ items: [Item], model: String) -> Status {
        var status = Status()
        status.dimension = dominantDimension(items, model: model)

        for item in items {
            guard item.embedding != nil else { status.missing += 1; continue }
            if let stamp = item.embeddingStamp {
                status.byModel[stamp.model, default: 0] += 1
                if stamp.matches(model: model, dimension: status.dimension) {
                    status.usable += 1
                } else {
                    status.foreign += 1
                }
            } else {
                // Vektor ohne Stempel: aus einer Fassung vor dieser Kennzeichnung.
                status.byModel["unbekannt", default: 0] += 1
                status.foreign += 1
            }
        }
        return status
    }

    static func isUsable(_ item: Item, model: String, dimension: Int?) -> Bool {
        guard item.embedding != nil, let stamp = item.embeddingStamp else { return false }
        return stamp.matches(model: model, dimension: dimension)
    }

    /// Alles, was für das eingestellte Modell noch einen Vektor braucht — fehlend
    /// wie fremd. Die Warteschlange des Nachholens.
    ///
    /// Die ältesten zuerst, damit ein abgebrochener Durchlauf beim nächsten Mal da
    /// weitermacht, wo er aufgehört hat, statt immer dieselben vorn zu finden.
    static func needingEmbedding(_ items: [Item], model: String, limit: Int = .max) -> [Item] {
        let dimension = dominantDimension(items, model: model)
        return items
            .filter { !isUsable($0, model: model, dimension: dimension) }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    /// Der Mittelvektor der nutzbaren Einträge.
    ///
    /// Gegen die Anisotropie des lokalen Modells: dort liegen alle Kosinuswerte über
    /// 0,95, weil die Vektoren in einem engen Kegel sitzen. Zieht man den
    /// Mittelvektor ab, verteilen sich die Werte wieder über den Bereich, in dem ein
    /// Schwellwert etwas bedeutet. Auf die Rangfolge wirkt es nicht — auch das in
    /// Faden gemessen; es stellt nur die Bedeutung der Grenze wieder her.
    ///
    /// Unter zehn Einträgen wird nicht zentriert: der Mittelvektor wäre dann
    /// hauptsächlich der eine Eintrag, den man sucht, und das Abziehen würde genau
    /// den Treffer wegrechnen.
    static let minimumForCentering = 10

    static func centroid(_ items: [Item], model: String) -> [Float]? {
        let dimension = dominantDimension(items, model: model)
        let vectors = items
            .filter { isUsable($0, model: model, dimension: dimension) }
            .compactMap(\.embedding)
        guard vectors.count >= minimumForCentering, let width = vectors.first?.count else { return nil }

        var sum = [Double](repeating: 0, count: width)
        var counted = 0
        for v in vectors where v.count == width {
            for i in 0 ..< width { sum[i] += Double(v[i]) }
            counted += 1
        }
        guard counted > 0 else { return nil }
        return sum.map { Float($0 / Double(counted)) }
    }

    /// Zieht den Mittelvektor ab. Längen, die nicht passen, bleiben unangetastet —
    /// ein halb zentrierter Vektor wäre schlimmer als ein unzentrierter.
    static func centered(_ vector: [Float], by centroid: [Float]?) -> [Float] {
        guard let centroid, centroid.count == vector.count else { return vector }
        return zip(vector, centroid).map(-)
    }
}
