import Foundation

/// Die Websuche für Kennungen.
///
/// Absichtlich klein und ohne Rezeptmaschine: Faden kann beliebige Suchanbieter über
/// eine Konfigurationssprache ansprechen, weil dort die Suche das Werkzeug ist. Hier
/// ist sie eine Nachschlagehilfe für Ziffernfolgen, und dafür reicht ein Aufruf mit
/// drei Feldern. Die Antwortform wird nachsichtig gelesen: Brave legt die Treffer
/// unter `web.results`, andere unter `results` oder `organic_results` — alle drei
/// werden probiert, statt den Nutzer ein Pfadfeld ausfüllen zu lassen.
struct SearchClient {
    let config: LookupConfig
    let apiKey: String

    struct Hit: Equatable {
        var title: String
        var url: String
        var snippet: String
        var source: String

        /// Was davon ins Modell geht. Kurz gehalten: fünf Treffer mit je einem
        /// Absatz sind schon ein halber Prompt, und lange Werbetexte verdrängen die
        /// technischen Angaben, auf die es ankommt.
        var forPrompt: String {
            var s = "- \(title)"
            if !snippet.isEmpty { s += "\n  \(snippet.prefix(320))" }
            if !url.isEmpty { s += "\n  \(url)" }
            return s
        }
    }

    func search(_ query: String, count: Int = 5) async throws -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard var components = URLComponents(string: config.url) else {
            throw ModelError.notConfigured
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: config.queryParam, value: trimmed))
        items.append(URLQueryItem(name: "count", value: String(count)))
        components.queryItems = items
        guard let url = components.url else { throw ModelError.notConfigured }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Kein Accept-Encoding von Hand: URLSession handelt das aus und packt selbst
        // aus. Wer es selbst setzt, bekommt rohe gzip-Bytes, die nie als JSON
        // durchgehen — derselbe Fehler steckte in Faden.
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: config.keyHeader)
        }

        let (data, response) = try await Net.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ... 299).contains(status) else {
            throw ModelError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelError.notJSON("Die Suche hat kein JSON-Objekt geliefert.")
        }
        return Self.hits(in: obj)
    }

    /// Die übliche Handvoll Antwortformen, in der Reihenfolge ihrer Verbreitung.
    static func hits(in object: [String: Any]) -> [Hit] {
        let candidates: [[[String: Any]]] = [
            (object["web"] as? [String: Any])?["results"] as? [[String: Any]],
            object["results"] as? [[String: Any]],
            object["organic_results"] as? [[String: Any]],
            object["data"] as? [[String: Any]],
        ].compactMap { $0 }

        guard let raw = candidates.first(where: { !$0.isEmpty }) else { return [] }

        return raw.compactMap { row in
            let title = str(row["title"]) ?? str(row["name"]) ?? ""
            let url = str(row["url"]) ?? str(row["link"]) ?? ""
            guard !title.isEmpty || !url.isEmpty else { return nil }
            let snippet = str(row["description"]) ?? str(row["snippet"])
                ?? str(row["content"]) ?? ""
            var source = ""
            if let profile = row["profile"] as? [String: Any] { source = str(profile["name"]) ?? "" }
            if source.isEmpty { source = str(row["source"]) ?? "" }
            if source.isEmpty, let host = URL(string: url)?.host { source = host }
            return Hit(title: title, url: url, snippet: snippet, source: source)
        }
    }

    private static func str(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
