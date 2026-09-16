import Foundation

/// Everything Fundus needs in order to talk to a model.
///
/// The same premise as in Faden: the app brings no infrastructure of its own.
/// Endpoint, key and model name come from the user. Unlike Faden, Fundus needs only a
/// fraction of that — an image out, JSON back — which is why there is no wire format
/// to choose here. Practically every provider speaks the OpenAI-compatible format,
/// and for the one call this app makes, a second translation would be effort without
/// return.
struct ModelConfig: Codable, Equatable {
    var baseURL: String = ""
    var path: String = "/v1/chat/completions"
    var model: String = ""
    /// Only the reference. The key itself lives in the keychain.
    var keychainAccount: String = "fundus.model.key"
    /// Generous, and that is a lesson from the first test flight.
    ///
    /// 4,000 was too little: a reasoning model like `glm-5.3-flash` thinks longer
    /// about a photo with forty parts in it than it then has to write, and ran into
    /// the limit before the first JSON character arrived. What came out was an empty
    /// answer — paid for dearly and not recognisable as a limit. Output tokens are
    /// only billed when they occur; a high limit costs nothing, one that is too low
    /// costs the whole shot.
    var maxOutputTokens: Int = 32_000
    /// Extra headers, such as `HTTP-Referer` for OpenRouter.
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
        // A stored 4,000 comes from the first version and was never a choice, only a
        // default that was too tight. Anyone still carrying it would otherwise get the
        // same failure back after every update.
        let storedTokens = try c.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        maxOutputTokens = (storedTokens == nil || storedTokens == 4000)
            ? d.maxOutputTokens : storedTokens!
        extraHeaders    = try c.decodeIfPresent([String: String].self, forKey: .extraHeaders) ?? [:]
    }
}

/// The web search that resolves identifiers.
///
/// Off as long as nothing has been entered. That is not a gesture of caution but the
/// premise of this app: it brings no infrastructure of its own, and a search running
/// silently over somebody else's service would be exactly that.
struct LookupConfig: Codable, Equatable {
    var enabled: Bool = false
    /// Preset to Brave because Faden already speaks it and one key in the household is
    /// enough for both. Any service that returns JSON with title, URL and description
    /// works too.
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

/// Where the vectors for the search come from.
struct SearchConfig: Codable, Equatable {
    enum Source: String, Codable, CaseIterable {
        /// Apple's model on the device. The default here — unlike in Faden, and for a
        /// reason: an inventory gets searched in the cellar, and a search field that
        /// finds nothing without reception is broken at exactly the moment you need
        /// it. The 108 MB are the price of that.
        case onDevice
        /// Over the user's endpoint. More accurate, but it costs a connection.
        case endpoint
    }
    var source: Source = .onDevice

    var embeddingPath: String = "/v1/embeddings"
    var embeddingModel: String = ""
    /// Empty means: the same endpoint and key as for reading the photos.
    var embeddingBaseURL: String = ""

    /// The similarity at which a hit is shown at all.
    ///
    /// 0.18 after centring. Before centring, every value from the local model lies
    /// above 0.95 and a threshold filters nothing; after the mean vector has been
    /// subtracted they spread out again over the range in which a limit means
    /// something.
    var minimumSimilarity: Double = 0.18
    /// How many similarity hits may appear below the name hits at most.
    var maxSemanticHits: Int = 12

    /// The name that stands on every vector as its origin.
    ///
    /// Not `embeddingModel`: on the device there is no field for anybody to type a
    /// name into, and the stamp still needs one — otherwise the two sources could not
    /// be told apart, and telling them apart is exactly what it is for.
    var effectiveModel: String {
        switch source {
        case .onDevice: return LocalEmbedder.modelIdentifier
        case .endpoint: return embeddingModel
        }
    }

    /// Whether the similarities have to be centred before they are compared.
    ///
    /// With the local model every cosine value lies above 0.95 — measured in Faden:
    /// dog against "which pet do I have?" 0.979, car against the same question 0.970.
    /// The ranking is still right, but a threshold no longer filters anything.
    /// Subtracting the mean vector of the inventory is the usual remedy and restores
    /// the meaning of the limit.
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

/// How the viewfinder behaves once a picture is in the box.
///
/// Two modes and no third, because there are two ways to use this app: you hold a
/// thing in your hand and want to enter it, or you walk through a cellar. The first
/// case wants the viewfinder closed afterwards, the second wants it open — and for
/// the second there used to be only the route through opening it twelve times.
enum CaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// One picture, then back to the list. The behaviour from before.
    case single
    /// The viewfinder stays open, every picture goes straight into the queue.
    case doku
    /// After the shutter the device shows what it recognises as individual objects;
    /// the user taps whichever of them they want.
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
    /// Whether a confirmed suggestion is embedded automatically. Off means: the search
    /// finds the thing by name but not by meaning.
    var indexAutomatically: Bool = true

    /// How many photos are read at once.
    ///
    /// Adjustable rather than fixed, because the right number does not depend on the
    /// app but on the provider: one accepts six calls side by side, the next throttles
    /// from two onwards and sends back 429. Whoever queues twenty photos after a walk
    /// along a shelf notices the difference between "done in two minutes" and "in
    /// twenty" — and whoever runs into a throttle notices it too.
    ///
    /// Two as the default: noticeably faster than one after another, and still far
    /// below what a provider reads as a swarm.
    var intakeConcurrency: Int = 2

    /// Which mode the viewfinder was last set to.
    ///
    /// Remembered rather than reset each time: whoever walks through a cellar switches
    /// to documentation once and does not want to do it again at every shelf. Single
    /// photo is the default because it is the familiar behaviour.
    var captureMode: CaptureMode = .single

    /// The language of the interface.
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
        // Clamped rather than taken as given: a number off the disk can come from an
        // older or broken store, and 0 would mean "never read a photo again".
        intakeConcurrency = (try c.decodeIfPresent(Int.self, forKey: .intakeConcurrency) ?? 2)
            .clamped(to: IntakeSchedule.concurrencyRange)
        captureMode = c.decodeLenient(CaptureMode.self, forKey: .captureMode) ?? .single
        language = c.decodeLenient(AppLanguage.self, forKey: .language) ?? .system
        appearance = c.decodeLenient(AppAppearance.self, forKey: .appearance) ?? .system
    }
}
