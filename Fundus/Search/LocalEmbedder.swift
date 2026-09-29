import Foundation
import NaturalLanguage

enum EmbeddingError: LocalizedError {
    case unsupported
    case notLoaded
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: return String(localized: "Dieses Gerät kennt das lokale Modell nicht.")
        case .notLoaded:   return String(localized: "Das lokale Modell ist noch nicht geladen.")
        case .failed(let m): return String(localized: "Einbettung fehlgeschlagen: \(m)")
        }
    }
}

/// Embeddings on the device, with Apple's `NLContextualEmbedding`.
///
/// Taken over from Faden, where the model was measured against a network model, and
/// the numbers hold here just the same: 8 ms per sentence, 108 MB of model files,
/// 13.5 MB of memory in use. On nine questions against fourteen German sentences the
/// network model (qwen3-embedding-8b, 4096 dimensions) came first seven times, this
/// one five times.
///
/// In Faden that made it a choice and not a default. Here it is the default, and the
/// reason is the place: an inventory gets searched in the cellar, in front of the
/// shelf, with one bar of reception or none. A search that needs a connection down
/// there is broken at exactly the moment you need it. Five out of nine without the
/// network beats seven out of nine with it.
actor LocalEmbedder {
    static let shared = LocalEmbedder()

    /// The name that stands on every vector as its origin.
    ///
    /// With the revision, because Apple can swap the model out with a system update:
    /// the same identifier for two different models would be exactly the quiet nonsense
    /// the stamp was built against.
    static var modelIdentifier: String {
        let revision = NLContextualEmbedding(script: .latin)?.revision ?? 0
        return "apple-nlcontextual-v\(revision)"
    }

    /// One model for all Latin scripts, not one per language.
    ///
    /// An inventory holds German and English names side by side — "Lackdose" next to
    /// "USB-C-Kabel" next to "gaffer tape". Two language models would be two vector
    /// spaces and therefore exactly the problem the origin stamp is meant to prevent.
    /// The Latin model covers 20 languages; measured, a German sentence and its English
    /// equivalent sit at 0.95 to each other.
    private static func makeModel() -> NLContextualEmbedding? {
        NLContextualEmbedding(script: .latin)
    }

    private var model: NLContextualEmbedding?

    /// True when this device knows the model at all.
    nonisolated static var isSupported: Bool { makeModel() != nil }

    /// True when the 108 MB are already on the device.
    nonisolated static var hasAssets: Bool { makeModel()?.hasAvailableAssets ?? false }

    nonisolated static var dimension: Int? {
        makeModel().map { Int($0.dimension) }
    }

    /// Downloads the model files. Returns at once when they are already there.
    ///
    /// With a timeout, because otherwise the call does not come back: in the simulator
    /// it ran for over six minutes without a result, and `mobileassetd` reports neither
    /// progress nor failure. The timeout only breaks off the *waiting* — the download
    /// carries on inside the system, and whether it arrived is something only
    /// `hasAssets` can say. Which is why this is not an error here but a piece of
    /// information.
    static func requestAssets(timeout: Duration = .seconds(180)) async throws {
        guard let probe = makeModel() else { throw EmbeddingError.unsupported }
        guard !probe.hasAvailableAssets else { return }

        let result: NLContextualEmbedding.AssetsResult? = try await withThrowingTaskGroup(
            of: NLContextualEmbedding.AssetsResult?.self) { group in
            group.addTask {
                // Its own instance rather than the one from outside:
                // NLContextualEmbedding is not Sendable, and handing it across a task
                // boundary would be exactly the data race the compiler warns about. The
                // object is only a handle on the same system model anyway.
                guard let model = makeModel() else { return nil }
                return try await model.requestAssets()
            }
            group.addTask { try await Task.sleep(for: timeout); return nil }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let result else {
            throw EmbeddingError.failed(String(localized:
                "Das System hat noch nicht geantwortet. Der Download läuft unter Umständen weiter — beim nächsten Öffnen steht hier, ob er angekommen ist."))
        }
        guard result == .available else {
            throw EmbeddingError.failed(String(localized: "Das Modell konnte nicht geladen werden (\(result.rawValue))."))
        }
    }

    private func loaded() throws -> NLContextualEmbedding {
        if let model { return model }
        guard let made = Self.makeModel() else { throw EmbeddingError.unsupported }
        guard made.hasAvailableAssets else { throw EmbeddingError.notLoaded }
        try made.load()
        model = made
        return made
    }

    /// Gives the memory back — measured at 13.5 MB.
    func unload() {
        model?.unload()
        model = nil
    }

    func embed(_ texts: [String]) throws -> [[Float]] {
        let model = try loaded()
        return try texts.map { try vector(for: $0, model: model) }
    }

    /// The vector of the first token, not the mean over all of them.
    ///
    /// Apple's header names four methods and recommends none. Measured against nine
    /// questions over fourteen sentences: first token 5/9, mean 3/9, maximum 2/9, last
    /// token 1/9. So measured rather than guessed — the mean would have been the
    /// obvious choice and is the worse one.
    private func vector(for text: String, model: NLContextualEmbedding) throws -> [Float] {
        // An empty text has no first token; without this line a zero vector would come
        // out, whose cosine to everything is 0 — that is, a hit that looks like a
        // non-hit.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.failed(String(localized: "Leerer Text.")) }

        guard let result = try? model.embeddingResult(for: trimmed, language: nil) else {
            throw EmbeddingError.failed(String(localized: "Der Text konnte nicht eingebettet werden."))
        }
        var first: [Double] = []
        result.enumerateTokenVectors(in: trimmed.startIndex ..< trimmed.endIndex) { v, _ in
            first = v
            return false
        }
        guard !first.isEmpty else { throw EmbeddingError.failed(String(localized: "Keine Tokenvektoren.")) }

        let norm = sqrt(first.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { throw EmbeddingError.failed(String(localized: "Nullvektor.")) }
        return first.map { Float($0 / norm) }
    }
}

/// Cosine similarity. Vectors sit in the inventory unnormalised, so the lengths are
/// computed here and not assumed.
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
    // Differing lengths mean something went wrong further up. Returning 0 here has
    // hidden exactly that error once already, so it is worth being loud in debug
    // builds and harmless in release.
    assert(a.count == b.count || a.isEmpty || b.isEmpty, "Vektorlängen \(a.count) vs. \(b.count)")
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Double = 0, na: Double = 0, nb: Double = 0
    for i in 0 ..< a.count {
        let x = Double(a[i]), y = Double(b[i])
        dot += x * y; na += x * x; nb += y * y
    }
    guard na > 0, nb > 0 else { return 0 }
    return dot / (na.squareRoot() * nb.squareRoot())
}
