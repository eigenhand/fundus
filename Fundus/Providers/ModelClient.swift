import Foundation

enum ModelError: LocalizedError {
    case notConfigured
    case missingKey
    case http(status: Int, body: String)
    case transport(String)
    case emptyAnswer
    /// The model ran into the token limit before any text arrived.
    case truncated(limit: Int, reasoningChars: Int)
    /// The model only thought and wrote nothing.
    case reasoningOnly(chars: Int)
    case notJSON(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return String(localized: "Kein Modell eingerichtet. Endpoint, Schlüssel und Modellname fehlen.")
        case .missingKey:    return String(localized: "Kein Schlüssel im Schlüsselbund hinterlegt.")
        case .http(let s, _) where ModelClient.isBusy(s):
            // After three attempts with waits in between. "HTTP 429" plus JSON would
            // be correct here and useless: the reader can do nothing with it beyond
            // what this sentence already says.
            return String(localized: "Der Anbieter drosselt gerade (HTTP \(s)) — auch nach zwei Wartepausen noch. Kurz warten hilft. Kommt es oft vor, in den Einstellungen unter „Aufnahme“ weniger Fotos gleichzeitig lesen lassen.")
        case .http(let s, let b):
            return String(localized: "HTTP \(s)\n\(Self.readable(b))")
        case .transport(let m): return String(localized: "Verbindungsfehler: \(m)")
        case .emptyAnswer:   return String(localized: "Das Modell hat keinen Text geliefert.")
        case .truncated(let limit, let thinking):
            // Two whole sentences instead of one assembled from parts: a catalogue
            // only knows whole keys, and in English the clause sits elsewhere.
            if thinking > 0 {
                return String(localized: "Die Antwort wurde bei \(limit) Token abgeschnitten, bevor Text kam. Das Modell hat vorher \(thinking) Zeichen nachgedacht — Reasoning-Modelle brauchen die Token doppelt. In den Einstellungen mehr Ausgabetoken erlauben.")
            }
            return String(localized: "Die Antwort wurde bei \(limit) Token abgeschnitten, bevor Text kam. In den Einstellungen mehr Ausgabetoken erlauben.")
        case .reasoningOnly(let chars):
            return String(localized: "Das Modell hat nur nachgedacht (\(chars) Zeichen) und keine Antwort geschrieben. Meist hilft ein höheres Token-Limit.")
        case .notJSON(let m): return String(localized: "Die Antwort war nicht das erwartete JSON: \(m)")
        }
    }

    /// Error texts are often JSON inside JSON. Pull out the innermost human sentence
    /// rather than showing the reader a wall of brackets.
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

/// The entire network traffic of this app: an image out, JSON back — and vectors, when
/// the search is to run over the endpoint rather than over the device.
///
/// Deliberately not Faden's provider layer: that one speaks two wire formats, tool
/// calls, reasoning traces and token counting, and Fundus needs none of it. Dragging
/// nine hundred lines of machinery along for two calls would mean maintaining it in
/// two apps so that one of them could use a fraction.
///
/// Streamed, even though the answer is small. The reason lies in Faden's experience:
/// one provider under test answered streamed calls in seconds while non-streamed ones
/// of the same size never came back at all. For a shot hanging behind a camera that is
/// the difference between slow and broken — and the progress can be shown along the
/// way.
struct ModelClient {
    let config: ModelConfig
    let apiKey: String

    // MARK: Ein Bild lesen

    /// Sends the image and the question and returns the complete answer text.
    ///
    /// `onDelta` gets every piece as soon as it arrives — the interface can use it to
    /// show that something is happening instead of turning a spinner.
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
        // Low, not zero: at temperature 0 some providers refuse, and for taking stock
        // inventiveness is the last thing you want.
        body["temperature"] = 0.2

        return try await stream(url: url, body: body, onDelta: onDelta)
    }

    // MARK: Eine Frage ohne Bild

    /// For the second pass: distilling a name out of search hits.
    ///
    /// Bounded more tightly than reading a photo, because the answer has three fields.
    /// A reasoning model may still think — hence no cap at a few hundred tokens but at
    /// an eighth of the budget.
    /// The output budget for a side call such as looking up an identifier.
    ///
    /// This used to read `maxOutputTokens / 8` — an economy measure for a call whose
    /// answer is short. It reliably destroyed the lookup, and in a way you could not
    /// see: a model that thinks first spends the 4,000 tokens on its reasoning and
    /// never gets to the text. Measured against a real shot: 70 seconds, 277 kB of
    /// reasoning trace, `finish_reason: length`, zero content.
    ///
    /// That saved nothing. The tokens are billed whether a sentence stands at the end
    /// or not — a capped call costs the same and simply delivers no result. The budget
    /// is therefore the same as for reading the photo.
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

    // MARK: Waiting when the provider throttles

    /// States in which a second attempt is worth something.
    ///
    /// 429 means "too many requests", 503 and 529 mean "overloaded right now". Those
    /// are waits, not defects — and the difference has newly come to matter here: since
    /// shots became a queue, several calls run side by side, and whoever turns the
    /// concurrency up runs into a throttle sooner. Before, the shot was lost when that
    /// happened.
    static func isBusy(_ status: Int) -> Bool { status == 429 || status == 503 || status == 529 }

    /// Two waits at most, then it counts as a failure. Three attempts and six seconds
    /// are the limit of what may be sat out in silence.
    static let maxWaits = 2

    /// How long the wait is.
    ///
    /// `Retry-After` first, because the provider knows better than any formula —
    /// capped, so that a header saying "3600" does not stop the app for an hour.
    /// Otherwise 2, then 4 seconds.
    static func pause(retryAfter header: String?, attempt: Int) -> Double {
        if let header, let seconds = Double(header.trimmingCharacters(in: .whitespaces)),
           seconds > 0 {
            return Swift.min(seconds, 30)
        }
        return Double(1 << (attempt + 1))
    }

    private func stream(url: URL, body: [String: Any],
                        onDelta: (@Sendable (String) -> Void)?,
                        attempt: Int = 0) async throws -> String {
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
            // Throttled: wait and try again — with the same model. Falling back on a
            // different one would be the wrong answer to a wait.
            if Self.isBusy(http.statusCode), attempt < Self.maxWaits {
                let seconds = Self.pause(
                    retryAfter: http.value(forHTTPHeaderField: "Retry-After"), attempt: attempt)
                try await Task.sleep(for: .seconds(seconds))
                return try await stream(url: url, body: body, onDelta: onDelta,
                                        attempt: attempt + 1)
            }
            throw ModelError.http(status: http.statusCode, body: errorBody)
        }

        var text = ""
        // Counted, not collected: the reasoning trace does not belong in the inventory,
        // but without it "no answer" cannot be told apart from "only thought about it"
        // — and those two cases need opposite remedies.
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

            // Providers name the reasoning trace differently; both spellings are in
            // circulation.
            for key in ["reasoning_content", "reasoning"] {
                if let t = delta[key] as? String { thinkingChars += t.count }
            }
            guard let piece = delta["content"] as? String, !piece.isEmpty else { continue }
            text += piece
            onDelta?(piece)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }

        // Without text: say why. "The model delivered nothing" would otherwise send the
        // user looking for a fault that does not exist.
        if finishReason == "length" {
            throw ModelError.truncated(limit: config.maxOutputTokens,
                                       reasoningChars: thinkingChars)
        }
        if thinkingChars > 0 { throw ModelError.reasoningOnly(chars: thinkingChars) }
        throw ModelError.emptyAnswer
    }

    // MARK: Vectors over the endpoint

    func embed(_ texts: [String], search: SearchConfig) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let model = search.embeddingModel.trimmingCharacters(in: .whitespaces)
        guard let url = search.embeddingURL(fallbackBase: config.baseURL), !model.isEmpty
        else { throw ModelError.notConfigured }

        var out: [[Float]] = []
        // In helpings that every endpoint accepts.
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

/// A shared URLSession with generous timeouts — a model reading a photo of a shelf
/// takes longer than a text answer.
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

/// Pulls a JSON object out of an answer that has wrapped it in prose or a code block.
///
/// Taken over from Faden, where the same job stands at the knowledge-graph extraction:
/// models do not reliably keep to "answer with JSON only", and losing a shot to a
/// `​```json` would be a paid model call for nothing.
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
