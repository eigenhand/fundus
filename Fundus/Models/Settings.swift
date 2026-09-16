import Foundation

/// Alles, was Fundus braucht, um mit einem Modell zu sprechen.
///
/// Dieselbe Prämisse wie bei Faden: die App bringt keine Infrastruktur mit. Endpoint,
/// Schlüssel und Modellname kommen vom Nutzer. Anders als Faden braucht Fundus davon
/// nur einen Bruchteil — ein Bild hin, JSON zurück — deshalb steht hier kein
/// Wire-Format zur Wahl. Das OpenAI-kompatible Format spricht praktisch jeder
/// Anbieter, und für den einen Aufruf, den diese App macht, wäre eine zweite
/// Übersetzung Aufwand ohne Gegenwert.
struct ModelConfig: Codable, Equatable {
    var baseURL: String = ""
    var path: String = "/v1/chat/completions"
    var model: String = ""
    /// Nur der Verweis. Der Schlüssel selbst liegt im Schlüsselbund.
    var keychainAccount: String = "fundus.model.key"
    /// Grosszuegig, und das ist eine Lehre aus dem ersten Testflug.
    ///
    /// 4 000 waren zu wenig: ein Reasoning-Modell wie `glm-5.3-flash` denkt ueber ein
    /// Foto mit vierzig Teilen laenger nach, als es danach zu schreiben hat, und lief
    /// in die Grenze, bevor das erste JSON-Zeichen kam. Herausgekommen ist eine leere
    /// Antwort — teuer bezahlt und nicht als Grenze erkennbar. Ausgabetoken werden
    /// nur berechnet, wenn sie anfallen; ein hohes Limit kostet nichts, ein zu
    /// niedriges kostet die ganze Aufnahme.
    var maxOutputTokens: Int = 32_000
    /// Zusätzliche Kopfzeilen, etwa `HTTP-Referer` für OpenRouter.
    var extraHeaders: [String: String] = [:]

    var endpointURL: URL? {
        let base = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { return nil }
        return URL(string: base + path)
    }

    var isComplete: Bool {
        endpointURL != nil && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ModelConfig()
        baseURL         = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        path            = try c.decodeIfPresent(String.self, forKey: .path) ?? d.path
        model           = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        keychainAccount = try c.decodeIfPresent(String.self, forKey: .keychainAccount) ?? d.keychainAccount
        // Gespeicherte 4 000 stammen aus der ersten Fassung und waren nie eine Wahl,
        // sondern eine zu knappe Voreinstellung. Wer sie noch liegen hat, bekaeme
        // sonst denselben Fehlschlag nach jedem Update wieder.
        let storedTokens = try c.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        maxOutputTokens = (storedTokens == nil || storedTokens == 4000)
            ? d.maxOutputTokens : storedTokens!
        extraHeaders    = try c.decodeIfPresent([String: String].self, forKey: .extraHeaders) ?? [:]
    }
}

/// Die Websuche, mit der Kennungen aufgelöst werden.
///
/// Aus, solange nichts eingetragen ist. Das ist kein Vorsichtsgestus, sondern die
/// Prämisse dieser App: sie bringt keine Infrastruktur mit, und eine Suche, die
/// stillschweigend über einen fremden Dienst liefe, wäre genau das.
struct LookupConfig: Codable, Equatable {
    var enabled: Bool = false
    /// Voreingestellt auf Brave, weil Faden ihn schon spricht und ein Schlüssel im
    /// Haushalt für beide reicht. Jeder Dienst, der JSON mit Titel, URL und
    /// Beschreibung liefert, geht auch.
    var url: String = "https://api.search.brave.com/res/v1/web/search"
    var queryParam: String = "q"
    var keyHeader: String = "X-Subscription-Token"
    var keychainAccount: String = "fundus.search.key"

    var isComplete: Bool {
        enabled && URL(string: url) != nil
            && !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LookupConfig()
        enabled         = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        url             = try c.decodeIfPresent(String.self, forKey: .url) ?? d.url
        queryParam      = try c.decodeIfPresent(String.self, forKey: .queryParam) ?? d.queryParam
        keyHeader       = try c.decodeIfPresent(String.self, forKey: .keyHeader) ?? d.keyHeader
        keychainAccount = try c.decodeIfPresent(String.self, forKey: .keychainAccount) ?? d.keychainAccount
    }
}

/// Woher die Vektoren für die Suche kommen.
struct SearchConfig: Codable, Equatable {
    enum Source: String, Codable, CaseIterable {
        /// Apples Modell auf dem Gerät. Die Voreinstellung hier — anders als bei
        /// Faden, und mit Grund: ein Bestand wird im Keller durchsucht, und ein
        /// Suchfeld, das ohne Empfang nichts findet, ist in genau dem Moment kaputt,
        /// in dem man es braucht. Die 108 MB sind der Preis dafür.
        case onDevice
        /// Über den Endpoint des Nutzers. Genauer, kostet aber eine Leitung.
        case endpoint
    }
    var source: Source = .onDevice

    var embeddingPath: String = "/v1/embeddings"
    var embeddingModel: String = ""
    /// Leer heißt: derselbe Endpoint und Schlüssel wie fürs Lesen der Fotos.
    var embeddingBaseURL: String = ""

    /// Ab welcher Ähnlichkeit ein Treffer überhaupt gezeigt wird.
    ///
    /// 0,18 nach dem Zentrieren. Vor dem Zentrieren liegen beim lokalen Modell alle
    /// Werte über 0,95 und ein Schwellwert filtert nichts; nach dem Abzug des
    /// Mittelvektors verteilen sie sich wieder über den Bereich, in dem eine Grenze
    /// etwas bedeutet.
    var minimumSimilarity: Double = 0.18
    /// Wie viele Ähnlichkeitstreffer höchstens unter die Namenstreffer kommen.
    var maxSemanticHits: Int = 12

    /// Der Name, der als Herkunft an jedem Vektor steht.
    ///
    /// Nicht `embeddingModel`: auf dem Gerät gibt es kein Feld, in das jemand einen
    /// Namen tippt, und der Stempel braucht trotzdem einen — sonst ließen sich die
    /// beiden Quellen nicht auseinanderhalten, und genau dafür ist er da.
    var effectiveModel: String {
        switch source {
        case .onDevice: return LocalEmbedder.modelIdentifier
        case .endpoint: return embeddingModel
        }
    }

    /// Ob die Ähnlichkeiten vor dem Vergleich zentriert werden müssen.
    ///
    /// Beim lokalen Modell liegen alle Kosinuswerte über 0,95 — gemessen in Faden:
    /// Hund zu „Welches Haustier habe ich?“ 0,979, Auto zur selben Frage 0,970. Die
    /// Rangfolge stimmt noch, aber ein Schwellwert filtert nichts mehr. Den
    /// Mittelvektor des Bestands abzuziehen ist das übliche Mittel dagegen und
    /// stellt die Bedeutung der Grenze wieder her.
    var needsCentering: Bool { source == .onDevice }

    func embeddingURL(fallbackBase: String) -> URL? {
        let raw = embeddingBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
            ? fallbackBase : embeddingBaseURL
        let base = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { return nil }
        return URL(string: base + embeddingPath)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SearchConfig()
        source            = c.decodeLenient(Source.self, forKey: .source) ?? d.source
        embeddingPath     = try c.decodeIfPresent(String.self, forKey: .embeddingPath) ?? d.embeddingPath
        embeddingModel    = try c.decodeIfPresent(String.self, forKey: .embeddingModel) ?? ""
        embeddingBaseURL  = try c.decodeIfPresent(String.self, forKey: .embeddingBaseURL) ?? ""
        minimumSimilarity = try c.decodeIfPresent(Double.self, forKey: .minimumSimilarity) ?? d.minimumSimilarity
        maxSemanticHits   = try c.decodeIfPresent(Int.self, forKey: .maxSemanticHits) ?? d.maxSemanticHits
    }
}

/// Wie der Sucher sich verhält, wenn ein Bild im Kasten ist.
///
/// Zwei Modi und kein dritter, weil es zwei Arten gibt, diese App zu benutzen: man
/// hält ein Ding in der Hand und will es eintragen, oder man geht einen Keller ab.
/// Der erste Fall will den Sucher danach zu haben, der zweite will ihn offen —
/// und für den zweiten gab es bisher nur den Weg über zwölfmal aufmachen.
enum CaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Ein Bild, dann zurück zur Liste. Das Verhalten von vorher.
    case single
    /// Der Sucher bleibt offen, jedes Bild geht sofort in die Reihe.
    case doku
    /// Nach dem Auslösen zeigt das Gerät, was es als einzelne Gegenstände erkennt;
    /// der Nutzer tippt an, was er davon will.
    case objects

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single:  return "Einzelfoto"
        case .doku:    return "Doku"
        case .objects: return "Objekte"
        }
    }

    var hint: String {
        switch self {
        case .single:  return "Ein Bild, dann zurück."
        case .doku:    return "Der Sucher bleibt offen — durchfotografieren."
        case .objects: return "Nach dem Auslösen antippen, was aufgenommen wird."
        }
    }
}

struct AppSettings: Codable, Equatable {
    var model = ModelConfig()
    var search = SearchConfig()
    var lookup = LookupConfig()
    /// Ob ein bestätigter Vorschlag automatisch eingebettet wird. Aus heißt: die
    /// Suche findet das Ding über den Namen, aber nicht über die Bedeutung.
    var indexAutomatically: Bool = true

    /// Wie viele Fotos gleichzeitig gelesen werden.
    ///
    /// Einstellbar und nicht fest, weil die richtige Zahl nicht von der App abhängt,
    /// sondern vom Anbieter: der eine nimmt sechs Aufrufe nebeneinander an, der
    /// nächste drosselt ab zwei und schickt 429 zurück. Wer nach einem Regalgang
    /// zwanzig Fotos einreiht, merkt den Unterschied zwischen „in zwei Minuten fertig“
    /// und „in zwanzig“ — und wer in eine Drosselung läuft, merkt ihn auch.
    ///
    /// Zwei als Vorgabe: spürbar schneller als nacheinander, und noch weit unter dem,
    /// was ein Anbieter als Schwarm auffasst.
    var intakeConcurrency: Int = 2

    /// Welcher Modus im Sucher zuletzt eingestellt war.
    ///
    /// Gemerkt und nicht jedes Mal zurückgesetzt: wer einen Keller abgeht, stellt
    /// einmal auf Doku und will das nicht bei jedem Regal wieder tun. Einzelfoto ist
    /// die Vorgabe, weil es das gewohnte Verhalten ist.
    var captureMode: CaptureMode = .single

    /// Die Sprache der Oberflaeche.
    var language: AppLanguage = .system

    /// Hell oder dunkel.
    var appearance: AppAppearance = .system

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model  = try c.decodeIfPresent(ModelConfig.self, forKey: .model) ?? ModelConfig()
        search = try c.decodeIfPresent(SearchConfig.self, forKey: .search) ?? SearchConfig()
        lookup = try c.decodeIfPresent(LookupConfig.self, forKey: .lookup) ?? LookupConfig()
        indexAutomatically = try c.decodeIfPresent(Bool.self, forKey: .indexAutomatically) ?? true
        // Begrenzt statt übernommen: eine Zahl von der Platte kann aus einer älteren
        // oder kaputten Ablage kommen, und 0 hieße „nie wieder ein Foto lesen“.
        intakeConcurrency = (try c.decodeIfPresent(Int.self, forKey: .intakeConcurrency) ?? 2)
            .clamped(to: IntakeSchedule.concurrencyRange)
        captureMode = c.decodeLenient(CaptureMode.self, forKey: .captureMode) ?? .single
        language = c.decodeLenient(AppLanguage.self, forKey: .language) ?? .system
        appearance = c.decodeLenient(AppAppearance.self, forKey: .appearance) ?? .system
    }
}
