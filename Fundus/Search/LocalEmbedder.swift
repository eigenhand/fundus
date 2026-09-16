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

/// Einbettungen auf dem Gerät, mit Apples `NLContextualEmbedding`.
///
/// Übernommen aus Faden, wo das Modell gegen ein Netzmodell gemessen wurde, und
/// die Zahlen gelten hier genauso: 8 ms je Satz, 108 MB Modelldateien, 13,5 MB
/// Arbeitsspeicher im Betrieb. Auf neun Fragen gegen vierzehn deutsche Sätze traf
/// das Netzmodell (qwen3-embedding-8b, 4096 Dimensionen) siebenmal auf Platz eins,
/// dieses hier fünfmal.
///
/// In Faden war das deshalb eine Wahl und keine Voreinstellung. Hier ist es die
/// Voreinstellung, und der Grund ist der Ort: ein Bestand wird im Keller
/// durchsucht, vor dem Regal, mit einem Balken Empfang oder keinem. Eine Suche, die
/// dort eine Leitung braucht, ist genau in dem Moment kaputt, in dem man sie
/// braucht. Fünf von neun ohne Netz schlagen sieben von neun mit.
actor LocalEmbedder {
    static let shared = LocalEmbedder()

    /// Der Name, der als Herkunft an jedem Vektor steht.
    ///
    /// Mit Revision, weil Apple das Modell mit einem Systemupdate austauschen kann:
    /// dieselbe Kennung für zwei verschiedene Modelle wäre genau der stille Unsinn,
    /// gegen den der Stempel gebaut wurde.
    static var modelIdentifier: String {
        let revision = NLContextualEmbedding(script: .latin)?.revision ?? 0
        return "apple-nlcontextual-v\(revision)"
    }

    /// Ein Modell für alle lateinischen Schriften, nicht eines je Sprache.
    ///
    /// Ein Bestand enthält deutsche und englische Bezeichnungen nebeneinander —
    /// „Lackdose“ neben „USB-C-Kabel“ neben „Gaffer Tape“. Zwei Sprachmodelle wären
    /// zwei Vektorräume und damit genau das Problem, das der Herkunftsstempel
    /// verhindern soll. Das lateinische Modell deckt 20 Sprachen ab; gemessen liegt
    /// ein deutscher Satz und seine englische Entsprechung bei 0,95 zueinander.
    private static func makeModel() -> NLContextualEmbedding? {
        NLContextualEmbedding(script: .latin)
    }

    private var model: NLContextualEmbedding?

    /// True, wenn dieses Gerät das Modell überhaupt kennt.
    nonisolated static var isSupported: Bool { makeModel() != nil }

    /// True, wenn die 108 MB schon auf dem Gerät liegen.
    nonisolated static var hasAssets: Bool { makeModel()?.hasAvailableAssets ?? false }

    nonisolated static var dimension: Int? {
        makeModel().map { Int($0.dimension) }
    }

    /// Lädt die Modelldateien. Kommt sofort zurück, wenn sie schon da sind.
    ///
    /// Mit Zeitgrenze, weil der Aufruf sonst nicht zurückkommt: im Simulator lief er
    /// über sechs Minuten ohne Ergebnis, und `mobileassetd` meldet keinen Fortschritt
    /// und keinen Fehlschlag. Die Zeitgrenze bricht nur das *Warten* ab — der
    /// Download läuft im System weiter, und ob er ankam, sagt allein `hasAssets`.
    /// Deshalb ist das hier auch kein Fehler, sondern eine Auskunft.
    static func requestAssets(timeout: Duration = .seconds(180)) async throws {
        guard let probe = makeModel() else { throw EmbeddingError.unsupported }
        guard !probe.hasAvailableAssets else { return }

        let result: NLContextualEmbedding.AssetsResult? = try await withThrowingTaskGroup(
            of: NLContextualEmbedding.AssetsResult?.self) { group in
            group.addTask {
                // Eigene Instanz statt der von draußen: NLContextualEmbedding ist
                // nicht Sendable, und sie über eine Aufgabengrenze zu reichen wäre
                // genau das Datenrennen, vor dem der Compiler warnt. Das Objekt ist
                // ohnehin nur ein Griff auf dasselbe Systemmodell.
                guard let model = makeModel() else { return nil }
                return try await model.requestAssets()
            }
            group.addTask { try await Task.sleep(for: timeout); return nil }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let result else {
            throw EmbeddingError.failed(
                "Das System hat noch nicht geantwortet. Der Download läuft unter Umständen "
                + "weiter — beim nächsten Öffnen steht hier, ob er angekommen ist.")
        }
        guard result == .available else {
            throw EmbeddingError.failed("Das Modell konnte nicht geladen werden (\(result.rawValue)).")
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

    /// Gibt den Arbeitsspeicher wieder frei — gemessen 13,5 MB.
    func unload() {
        model?.unload()
        model = nil
    }

    func embed(_ texts: [String]) throws -> [[Float]] {
        let model = try loaded()
        return try texts.map { try vector(for: $0, model: model) }
    }

    /// Der Vektor des ersten Tokens, nicht der Mittelwert über alle.
    ///
    /// Apple nennt in der Kopfzeile vier Verfahren und empfiehlt keines. Gemessen an
    /// neun Fragen gegen vierzehn Sätze: erster Token 5/9, Mittelwert 3/9, Maximum
    /// 2/9, letzter Token 1/9. Also gemessen statt geraten — der Mittelwert wäre die
    /// naheliegende Wahl gewesen und ist die schlechtere.
    private func vector(for text: String, model: NLContextualEmbedding) throws -> [Float] {
        // Ein leerer Text hat keinen ersten Token; ohne diese Zeile käme ein
        // Nullvektor heraus, dessen Kosinus zu allem 0 ist — also ein Treffer, der
        // wie ein Nichttreffer aussieht.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.failed("Leerer Text.") }

        guard let result = try? model.embeddingResult(for: trimmed, language: nil) else {
            throw EmbeddingError.failed("Der Text konnte nicht eingebettet werden.")
        }
        var first: [Double] = []
        result.enumerateTokenVectors(in: trimmed.startIndex ..< trimmed.endIndex) { v, _ in
            first = v
            return false
        }
        guard !first.isEmpty else { throw EmbeddingError.failed("Keine Tokenvektoren.") }

        let norm = sqrt(first.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { throw EmbeddingError.failed("Nullvektor.") }
        return first.map { Float($0 / norm) }
    }
}

/// Kosinusähnlichkeit. Vektoren liegen unnormiert im Bestand, also werden die
/// Längen hier gerechnet und nicht angenommen.
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
    // Verschiedene Längen heißen, dass weiter oben etwas schiefging. Hier 0
    // zurückzugeben hat genau diesen Fehler schon einmal versteckt, also ist es
    // wert, in Debug-Builds laut zu sein und im Release harmlos zu bleiben.
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
