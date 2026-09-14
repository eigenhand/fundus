import Foundation

enum ModelError: LocalizedError {
    case notConfigured
    case missingKey
    case http(status: Int, body: String)
    case transport(String)
    case emptyAnswer
    /// Das Modell lief in die Token-Grenze, bevor Text kam.
    case truncated(limit: Int, reasoningChars: Int)
    /// Das Modell hat nur nachgedacht und nichts geschrieben.
    case reasoningOnly(chars: Int)
    case notJSON(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Kein Modell eingerichtet. Endpoint, Schlüssel und Modellname fehlen."
        case .missingKey:    return "Kein Schlüssel im Schlüsselbund hinterlegt."
        case .http(let s, let b):
            return "HTTP \(s)\n\(Self.readable(b))"
        case .transport(let m): return "Verbindungsfehler: \(m)"
        case .emptyAnswer:   return "Das Modell hat keinen Text geliefert."
        case .truncated(let limit, let thinking):
            var m = "Die Antwort wurde bei \(limit) Token abgeschnitten, bevor Text kam."
            if thinking > 0 {
                m += " Das Modell hat vorher \(thinking) Zeichen nachgedacht — "
                m += "Reasoning-Modelle brauchen die Token doppelt."
            }
            return m + " In den Einstellungen mehr Ausgabetoken erlauben."
        case .reasoningOnly(let chars):
            return "Das Modell hat nur nachgedacht (\(chars) Zeichen) und keine Antwort "
                + "geschrieben. Meist hilft ein höheres Token-Limit."
        case .notJSON(let m): return "Die Antwort war nicht das erwartete JSON: \(m)"
        }
    }

    /// Fehlertexte sind oft JSON in JSON. Den innersten menschlichen Satz
    /// herausholen, statt dem Leser eine Wand aus Klammern zu zeigen.
    static func readable(_ body: String) -> String {
        var current = body
        for _ in 0 ..< 3 {
            guard let data = current.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { break }
            let nested = (obj["error"] as? [String: Any])?["message"] as? String
                ?? obj["message"] as? String
                ?? obj["detail"] as? String
            guard let nested else { break }
            current = nested
        }
        let cleaned = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > 300 ? String(cleaned.prefix(300)) + "…" : cleaned
    }
}

/// Der ganze Netzverkehr dieser App: ein Bild hin, JSON zurück — und Vektoren, wenn
/// die Suche über den Endpoint statt über das Gerät laufen soll.
///
/// Bewusst nicht Fadens Anbieterschicht: die kann zwei Wire-Formate, Werkzeugaufrufe,
/// Gedankengang und Token-Zählung, und davon braucht Fundus nichts. Neunhundert
/// Zeilen Maschinerie für zwei Aufrufe mitzuschleppen hieße, sie in zwei Apps
/// pflegen zu müssen, damit eine davon einen Bruchteil benutzt.
///
/// Gestreamt, obwohl die Antwort klein ist. Der Grund steht in Fadens Erfahrung: ein
/// getesteter Anbieter beantwortete gestreamte Aufrufe in Sekunden, während
/// nicht-gestreamte derselben Größe überhaupt nicht zurückkamen. Für eine Aufnahme,
/// die hinter einer Kamera hängt, ist das der Unterschied zwischen langsam und
/// kaputt — und der Fortschritt lässt sich nebenbei anzeigen.
struct ModelClient {
    let config: ModelConfig
    let apiKey: String

    // MARK: Ein Bild lesen

    /// Schickt Bild und Frage und gibt den vollständigen Antworttext zurück.
    ///
    /// `onDelta` bekommt jedes Stück, sobald es ankommt — die Oberfläche kann damit
    /// zeigen, dass etwas passiert, statt einen Kreis zu drehen.
    func read(imageJPEG: Data, prompt: String, system: String,
              onDelta: (@Sendable (String) -> Void)? = nil) async throws -> String {
        guard let url = config.endpointURL, !config.model.isEmpty else {
            throw ModelError.notConfigured
        }
        let content: [[String: Any]] = [
            ["type": "image_url",
             "image_url": ["url": "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"]],
            ["type": "text", "text": prompt],
        ]
        var body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": content],
            ],
            "max_tokens": config.maxOutputTokens,
            "stream": true,
        ]
        // Niedrig, nicht null: bei Temperatur 0 verweigern einige Anbieter, und für
        // eine Bestandsaufnahme ist Erfindungsreichtum das Letzte, was man will.
        body["temperature"] = 0.2

        return try await stream(url: url, body: body, onDelta: onDelta)
    }

    // MARK: Eine Frage ohne Bild

    /// Für den zweiten Durchgang: aus Suchtreffern einen Namen destillieren.
    ///
    /// Knapper begrenzt als das Lesen eines Fotos, weil die Antwort drei Felder hat.
    /// Ein Reasoning-Modell darf trotzdem nachdenken — daher nicht auf ein paar
    /// hundert Token gedeckelt, sondern auf ein Achtel des Vorrats.
    /// Das Ausgabebudget für einen Nebenaufruf wie das Nachschlagen einer Kennung.
    ///
    /// Hier stand `maxOutputTokens / 8` — eine Sparmaßnahme für einen Aufruf, dessen
    /// Antwort kurz ist. Sie hat das Nachschlagen zuverlässig zerstört, und zwar so,
    /// dass man es nicht sah: ein Modell, das erst nachdenkt, verbraucht die 4 000
    /// Token im Gedankengang und kommt nie zum Text. Gemessen an einer echten
    /// Aufnahme: 70 Sekunden, 277 kB Denkspur, `finish_reason: length`, null Inhalt.
    ///
    /// Gespart hat das nichts. Die Token werden abgerechnet, ob am Ende ein Satz
    /// steht oder nicht — ein gedeckelter Aufruf kostet dasselbe und liefert nur
    /// kein Ergebnis. Das Budget ist deshalb dasselbe wie beim Lesen des Fotos.
    static func sideCallBudget(_ configured: Int) -> Int { max(1_000, configured) }

    func ask(prompt: String, system: String) async throws -> String {
        guard let url = config.endpointURL, !config.model.isEmpty else {
            throw ModelError.notConfigured
        }
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt],
            ],
            "max_tokens": Self.sideCallBudget(config.maxOutputTokens),
            "stream": true,
            "temperature": 0.1,
        ]
        return try await stream(url: url, body: body, onDelta: nil)
    }

    private func stream(url: URL, body: [String: Any],
                        onDelta: (@Sendable (String) -> Void)?) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        for (k, v) in config.extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await Net.session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelError.transport("Keine HTTP-Antwort.")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 2_000 { break }
            }
            throw ModelError.http(status: http.statusCode, body: errorBody)
        }

        var text = ""
        // Mitgezaehlt, nicht gesammelt: der Gedankengang gehoert nicht in den Bestand,
        // aber ohne ihn ist "keine Antwort" nicht von "nur nachgedacht" zu trennen —
        // und genau diese beiden Faelle brauchen entgegengesetzte Abhilfe.
        var thinkingChars = 0
        var finishReason: String?

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let error = obj["error"] as? [String: Any] {
                throw ModelError.transport(error["message"] as? String ?? "Unbekannter Fehler.")
            }
            guard let choice = (obj["choices"] as? [[String: Any]])?.first else { continue }
            if let reason = choice["finish_reason"] as? String { finishReason = reason }
            guard let delta = choice["delta"] as? [String: Any] else { continue }

            // Anbieter benennen den Gedankengang unterschiedlich; beide Schreibweisen
            // sind im Umlauf.
            for key in ["reasoning_content", "reasoning"] {
                if let t = delta[key] as? String { thinkingChars += t.count }
            }
            guard let piece = delta["content"] as? String, !piece.isEmpty else { continue }
            text += piece
            onDelta?(piece)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }

        // Ohne Text: sagen, warum. "Das Modell hat nichts geliefert" schickt den
        // Nutzer sonst auf die Suche nach einem Fehler, den es nicht gibt.
        if finishReason == "length" {
            throw ModelError.truncated(limit: config.maxOutputTokens,
                                       reasoningChars: thinkingChars)
        }
        if thinkingChars > 0 { throw ModelError.reasoningOnly(chars: thinkingChars) }
        throw ModelError.emptyAnswer
    }

    // MARK: Vektoren über den Endpoint

    func embed(_ texts: [String], search: SearchConfig) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let model = search.embeddingModel.trimmingCharacters(in: .whitespaces)
        guard let url = search.embeddingURL(fallbackBase: config.baseURL), !model.isEmpty
        else { throw ModelError.notConfigured }

        var out: [[Float]] = []
        // In Häppchen, die jeder Endpoint annimmt.
        for chunk in texts.chunked(into: 32) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["model": model, "input": chunk])

            let (data, response) = try await Net.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ... 299).contains(status) else {
                throw ModelError.http(status: status,
                                      body: String(data: data, encoding: .utf8) ?? "")
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = obj["data"] as? [[String: Any]]
            else { throw ModelError.notJSON("Feld `data` fehlt.") }

            for item in items {
                guard let raw = item["embedding"] as? [Double] else {
                    throw ModelError.notJSON("Feld `embedding` fehlt oder ist keine Zahlenreihe.")
                }
                out.append(raw.map(Float.init))
            }
        }
        guard out.count == texts.count else {
            throw ModelError.notJSON("Es kamen \(out.count) Vektoren für \(texts.count) Texte zurück.")
        }
        return out
    }
}

/// Gemeinsame URLSession mit großzügigen Zeitgrenzen — ein Modell, das ein Regalfoto
/// liest, braucht länger als eine Textantwort.
enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 180
        c.timeoutIntervalForResource = 600
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

/// Holt ein JSON-Objekt aus einer Antwort, die es in Prosa oder einen Codeblock
/// gepackt hat.
///
/// Übernommen aus Faden, wo dieselbe Aufgabe bei der Wissensgraph-Extraktion steht:
/// Modelle halten sich nicht zuverlässig an „antworte nur mit JSON“, und eine
/// Aufnahme an einem `​```json` zu verlieren wäre ein bezahlter Modellaufruf für
/// nichts.
enum JSONSnippet {
    static func firstObject(in s: String) -> [String: Any]? {
        if let data = s.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return o
        }
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        let slice = String(s[start ... i])
                        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8)))
                            as? [String: Any]
                    }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }
}
