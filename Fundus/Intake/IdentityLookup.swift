import Foundation

/// Aus einer Kennung ein Ding machen.
///
/// Zwei Durchgänge statt Werkzeugaufrufen: das Modell liest erst das Foto und nennt
/// die Kennungen, die es entziffern kann, dann sucht die App danach und lässt das
/// Modell aus den Treffern einen Namen destillieren. Werkzeugaufrufe wären der
/// elegantere Weg und der falsche — sie verlangen eine Anbieterschicht, die Faden
/// hat und diese App absichtlich nicht, und sie geben die Zahl der bezahlten
/// Aufrufe aus der Hand. Hier ist sie gedeckelt und abzählbar.
///
/// Die zweite Entscheidung ist wichtiger: ein Fund aus der Suche **ersetzt nichts**.
/// Er kommt als eigener Vorschlag neben den Befund des Modells, mit der Nummer, die
/// ihn erzeugt hat. Der Grund ist eine Kette mit drei fehlbaren Gliedern — ein
/// unscharfer Aufkleber, ein Modell, das Zeichen verwechselt, eine Suchmaschine, die
/// auf jede Zeichenfolge irgendetwas antwortet. Am Ende steht ein präziser
/// Produktname, der verlässlicher aussieht als alles andere im Bestand und es am
/// wenigsten ist. Sichtbar machen statt glätten.
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
            if let lookup = await resolveOne(code: code, itemName: out[index].name) {
                out[index].code?.lookup = lookup
            }
        }
        onProgress?(capped.count, capped.count)
        return out
    }

    /// Eine Kennung: suchen, dann destillieren lassen.
    func resolveOne(code: ItemCode, itemName: String) async -> CodeLookup? {
        let query = Self.query(for: code, itemName: itemName)
        let hits: [SearchClient.Hit]
        do {
            hits = try await search.search(query)
        } catch {
            return nil
        }
        guard !hits.isEmpty else { return nil }

        let reply: String
        do {
            reply = try await model.ask(
                prompt: IntakePrompt.lookupMessage(code: code, itemName: itemName, hits: hits),
                system: IntakePrompt.lookupSystem)
        } catch {
            return nil
        }
        guard let object = JSONSnippet.firstObject(in: reply) else { return nil }
        return Self.parse(object, query: query, hits: hits)
    }

    /// Die Suchanfrage.
    ///
    /// Die Kennung wörtlich und in Anführungszeichen, damit die Suchmaschine sie
    /// nicht „korrigiert“ — genau das würde eine falsch gelesene Nummer in ein
    /// plausibles Ergebnis verwandeln, statt sie ins Leere laufen zu lassen. Ins
    /// Leere laufen ist hier das gewünschte Verhalten.
    static func query(for code: ItemCode, itemName: String) -> String {
        switch code.kind {
        case .ean, .upc:
            return "\"\(code.value)\""
        default:
            let hint = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
            return hint.isEmpty ? "\"\(code.value)\"" : "\"\(code.value)\" \(hint)"
        }
    }

    static func parse(_ object: [String: Any], query: String,
                      hits: [SearchClient.Hit]) -> CodeLookup? {
        let title = (object["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Kein Titel heißt: die Treffer passten nicht zur Kennung. Das ist eine
        // gültige Antwort und wird nicht zu einem Vorschlag aufgefüllt.
        guard !title.isEmpty, title.lowercased() != "null" else { return nil }

        let sourceURL = (object["source"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matching = hits.first { $0.url == sourceURL } ?? hits.first

        return CodeLookup(
            query: query,
            title: title,
            summary: (object["summary"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            sourceURL: sourceURL.isEmpty ? (matching?.url ?? "") : sourceURL,
            sourceName: matching?.source ?? "",
            confident: object["confident"] as? Bool ?? false)
    }
}
