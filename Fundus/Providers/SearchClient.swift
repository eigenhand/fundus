import Foundation

/// The web search for identifiers.
///
/// Deliberately small and without a recipe engine: Faden can address arbitrary search
/// providers through a configuration language, because there the search is the tool.
/// Here it is a lookup aid for rows of digits, and for that one call with three fields
/// is enough. The response shape is read leniently: Brave puts the hits under
/// `web.results`, others under `results` or `organic_results` — all three get tried
/// rather than making the user fill in a path field.
struct SearchClient {
    let config: LookupConfig
    let apiKey: String

    struct Hit: Equatable {
        var title: String
        var url: String
        var snippet: String
        var source: String

        /// What of it goes into the model. Kept short: five hits with a paragraph each
        /// are already half a prompt, and long marketing copy crowds out the technical
        /// details that matter.
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
        // No hand-written Accept-Encoding: URLSession negotiates that and unpacks it
        // itself. Set it yourself and you get raw gzip bytes that never pass as JSON —
        // the same bug sat in Faden.
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

    /// The usual handful of response shapes, in order of how common they are.
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
