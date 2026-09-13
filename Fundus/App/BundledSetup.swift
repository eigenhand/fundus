import Foundation

/// Ein Anbieter, der im Build steckt, damit ein Tester die App öffnen und
/// fotografieren kann.
///
/// Fundus' Prämisse ist wie die von Faden, dass die App keine Infrastruktur
/// mitbringt — Endpoint, Schlüssel und Modell kommen vom Nutzer. Für jeden, der sie
/// normal installiert, bleibt das so: ohne einkompilierten Schlüssel ist `isManaged`
/// falsch und die Einrichtung verhält sich wie bisher.
///
/// Ein TestFlight-Build für einen kleinen Kreis ist der eine Fall, in dem diese
/// Prämisse im Weg steht. Diese Leute haben keinen eigenen Endpoint, und sie erst
/// einen suchen zu lassen heißt, das Einrichtungsformular zu testen statt der App.
///
/// Der Schlüssel in einem ausgelieferten Binary ist für jeden lesbar, der das Binary
/// hat. Das ist eine bewusste Abwägung für einen Build an namentlich bekannte Tester,
/// kein Versehen — mit einem Schlüssel, der nur dafür ausgestellt ist und einzeln
/// widerrufen werden kann.
enum BundledSetup {

    // Wird von `release.sh` aus `.release.env` eingesetzt und danach wieder geleert,
    // damit im Arbeitsverzeichnis nie einer stehenbleibt. Hier absichtlich leer.
    static let apiKey = ""

    static var isManaged: Bool { !apiKey.isEmpty }

    static let baseURL = "https://api.tensorx.ai"
    static let chatPath = "/v1/chat/completions"
    static let providerName = "TensorX"

    /// Dasselbe Modell wie in Faden. Geprüft: es liest Bilder, und es liest sie
    /// schnell — gemessen 12 s gegen 72 s für `qwen/qwen3.8-flash-next` auf
    /// derselben Frage. Für eine Aufnahme, die hinter einer Kamera hängt, ist das
    /// der Unterschied zwischen langsam und kaputt.
    static let chatModel = "z-ai/glm-5.3-flash"
    static let maxOutputTokens = 4_000

    static let keychainAccount = "fundus.bundled.key"
}
