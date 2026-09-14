import Foundation

/// Aus einer Kennung eine Auswahl machen — nicht ein Urteil.
///
/// Zwei Durchgänge statt Werkzeugaufrufen: das Modell liest erst das Foto und nennt
/// die Kennungen, die es entziffern kann, dann sucht die App danach und lässt das
/// Modell aus den Treffern die nächstliegenden Möglichkeiten destillieren.
/// Werkzeugaufrufe wären der elegantere Weg und der falsche — sie verlangen eine
/// Anbieterschicht, die Faden hat und diese App absichtlich nicht, und sie geben die
/// Zahl der bezahlten Aufrufe aus der Hand. Hier ist sie gedeckelt und abzählbar.
///
/// Die zweite Entscheidung ist wichtiger: ein Fund aus der Suche **ersetzt nichts**.
/// Er kommt als Vorschlag neben den Befund des Modells, mit der Nummer, die ihn
/// erzeugt hat. Der Grund ist eine Kette mit drei fehlbaren Gliedern — ein unscharfer
/// Aufkleber, ein Modell, das Zeichen verwechselt, eine Suchmaschine, die auf jede
/// Zeichenfolge irgendetwas antwortet. Am Ende steht ein präziser Produktname, der
/// verlässlicher aussieht als alles andere im Bestand und es am wenigsten ist.
/// Sichtbar machen statt glätten.
///
/// Was sich geändert hat, ist, *wer* die Kette bewertet. Vorher sollte das Modell
/// entscheiden, ob die Treffer zur Nummer passen, und im Zweifel schweigen — bei einer
/// abgelesenen Nummer ist der Zweifel der Normalfall, und heraus kam meistens nichts,
/// obwohl das richtige Teil in den Treffern stand. Jetzt legt die App bis zu drei
/// Möglichkeiten vor, und es entscheidet der, der das Ding in der Hand hält.
struct IdentityLookup {
    let model: ModelClient
    let search: SearchClient

    /// Wie viele Kennungen je Aufnahme nachgeschlagen werden.
    ///
    /// Gedeckelt, weil ein Koffer mit vierzig Bauteilen sonst vierzig Suchen und
    /// vierzig Modellaufrufe auslöst — für eine Aufnahme, die der Nutzer vielleicht
    /// verwirft. Wer mehr will, schlägt einzeln im Eintrag nach.
    static let maxPerIntake = 8

    /// Schlägt die Kennungen der Vorschläge nach und hängt das Ergebnis an.
    ///
    /// Schlägt einzeln fehl, nicht im Ganzen: eine Suche ohne Treffer oder ein
    /// Zeitablauf darf die Aufnahme nicht kosten, die schon bezahlt ist.
    func resolve(_ proposals: [Proposal],
                 onProgress: (@Sendable (Int, Int) -> Void)? = nil) async -> [Proposal] {
        var out = proposals
        let targets = proposals.indices.filter {
            proposals[$0].code?.isSearchable == true && proposals[$0].code?.lookup == nil
        }
        let capped = Array(targets.prefix(Self.maxPerIntake))
        guard !capped.isEmpty else { return out }

        for (done, index) in capped.enumerated() {
            onProgress?(done, capped.count)
            guard let code = out[index].code else { continue }
            // Der Name vorher heraus: `out[index]` zu lesen, während in dasselbe
            // Element geschrieben wird, ist ein überlappender Zugriff.
            let name = out[index].name
            out[index].code?.lookup = await resolveOne(code: code, itemName: name)
        }
        onProgress?(capped.count, capped.count)
        return out
    }

    /// Eine Kennung: suchen, dann die Auswahl destillieren lassen.
    ///
    /// Gibt immer etwas zurück, und das ist Absicht. Vorher kam bei jedem Fehlschlag
    /// `nil` heraus — bei einer abgerissenen Verbindung, bei einem Modell, das kein
    /// JSON schrieb, und bei „passt nichts“ dasselbe. In der Oberfläche war das eine
    /// leere Stelle unter der Nummer, an der nichts darauf hinwies, dass überhaupt
    /// jemand gesucht hatte. Jetzt steht dort der Grund.
    func resolveOne(code: ItemCode, itemName: String) async -> CodeLookup {
        let query = Self.query(for: code, itemName: itemName)
        let failure = CodeLookup(query: query, failed: true)

        let hits: [SearchClient.Hit]
        do {
            hits = try await search.search(query)
        } catch {
            return failure
        }
        // Kein Treffer ist ein Ergebnis, kein Fehler: die Nummer steht so nirgends.
        guard !hits.isEmpty else { return CodeLookup(query: query) }

        let reply: String
        do {
            reply = try await model.ask(
                prompt: IntakePrompt.lookupMessage(code: code, itemName: itemName, hits: hits),
                system: IntakePrompt.lookupSystem)
        } catch {
            return failure
        }
        guard let object = JSONSnippet.firstObject(in: reply) else { return failure }
        return Self.parse(object, code: code, query: query, hits: hits)
            ?? CodeLookup(query: query)
    }

    /// Die Suchanfrage.
    ///
    /// Hier stand die Kennung immer in Anführungszeichen, damit die Suchmaschine sie
    /// nicht „korrigiert“. Für eine dekodierte EAN ist das richtig: die ist
    /// zeichengenau, und ein Ausweichen auf ein ähnliches Produkt wäre ein Fehler.
    ///
    /// Für eine abgelesene Nummer war es die Ursache des Problems. `42BYGH3701-B-89S80`
    /// in Anführungszeichen findet nichts, wenn auf dem Motor `…-B-80S80` steht — und
    /// „nichts“ war dann das Ergebnis, obwohl ein Mensch den Motor in zwei Sekunden
    /// wiedererkannt hätte. Ohne Anführungszeichen findet die Suche die Baureihe, und
    /// der Nutzer sucht sich seine Ausführung selbst heraus. Ins Leere laufen war als
    /// Schutz gedacht; in Wahrheit hat es nur die Arbeit zurückgegeben.
    static func query(for code: ItemCode, itemName: String) -> String {
        let hint = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch code.origin {
        case .scanned:
            return "\"\(code.value)\""
        case .read:
            return hint.isEmpty ? code.value : "\(code.value) \(hint)"
        }
    }

    /// Die Antwort des Modells zu einer Auswahlliste machen.
    ///
    /// Eine Prüfung macht die App selbst, statt sie zu glauben: `exact` heißt, die
    /// Kennung steht **wörtlich** in einem Treffer, und das lässt sich nachsehen.
    /// Tut sie es nicht, wird der Vorschlag auf `near` zurückgestuft. Ein Modell, das
    /// gefällig sein will, stuft sonst jeden Treffer als Volltreffer ein — und genau
    /// diese Etikette entscheidet, wie viel Vertrauen die Zeile in der Oberfläche
    /// bekommt.
    static func parse(_ object: [String: Any], code: ItemCode, query: String,
                      hits: [SearchClient.Hit]) -> CodeLookup? {
        let rows = object["candidates"] as? [[String: Any]]
            // Auch die alte, einzelne Form, falls das Modell in sie zurückfällt.
            ?? (object["title"] is String ? [object] : [])

        let literal = hits.contains {
            ($0.title + " " + $0.snippet + " " + $0.url)
                .range(of: code.value, options: .caseInsensitive) != nil
        }

        var out: [CodeCandidate] = []
        for row in rows {
            let title = (row["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Kein Titel heißt: dieser Vorschlag ist keiner. Er wird nicht aufgefüllt.
            guard !title.isEmpty, title.lowercased() != "null" else { continue }

            let sourceURL = (row["source"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let matching = hits.first { $0.url == sourceURL } ?? hits.first

            var match = CodeCandidate.Match(
                rawValue: (row["match"] as? String)?.lowercased() ?? "") ?? .family
            if match == .exact, !literal { match = .near }

            out.append(CodeCandidate(
                title: title,
                summary: (row["summary"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                sourceURL: sourceURL.isEmpty ? (matching?.url ?? "") : sourceURL,
                sourceName: matching?.source ?? "",
                match: match,
                codeSeen: seen(row["code_seen"], unlike: code.value)))
            if out.count == CodeLookup.maxCandidates { break }
        }

        guard !out.isEmpty else { return nil }
        return CodeLookup(query: query, candidates: out)
    }

    /// Die Nummer aus dem Treffer — aber nur, wenn sie sich von der gelesenen
    /// unterscheidet. Dieselbe Nummer noch einmal danebenzuschreiben ist Lärm.
    private static func seen(_ raw: Any?, unlike value: String) -> String {
        let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !s.isEmpty, s.lowercased() != "null",
              s.compare(value, options: .caseInsensitive) != .orderedSame else { return "" }
        return s
    }
}
