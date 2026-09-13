import Foundation

/// Wo die Daten liegen: im gemeinsamen Container der eigenhand-Apps, wenn er da ist.
///
/// `group.dev.eigenhand.shared` ist der Ort, an dem Spind, Faden und Fundus sich
/// treffen. Für Spind heißt das, dass es diesen Bestand mitsynchronisieren kann, ohne
/// Fundus zu kennen; für Faden, dass es ihn lesen könnte, ohne ihn zu kopieren.
///
/// Der Rückfall ist nicht Kosmetik. Eine App Group gilt nur, wenn das Bereitstellungs-
/// profil sie enthält — im Simulator mit automatischer Signierung, in einem Fork mit
/// fremder Team-ID und in einem Build ohne dieses Recht liefert
/// `containerURL(forSecurityApplicationGroupIdentifier:)` einfach `nil`. Ohne Rückfall
/// startete die App dann ohne Speicher, und zwar lautlos.
///
/// Deshalb steht `isShared` hier und in den Einstellungen: welcher der beiden Orte
/// benutzt wird, entscheidet darüber, ob Spind diesen Bestand überhaupt sieht. Das
/// ist keine Kleinigkeit, die man erraten sollte.
enum SharedContainer {
    static let groupIdentifier = "group.dev.eigenhand.shared"

    /// Das Verzeichnis, in dem Fundus arbeitet.
    static let directory: URL = {
        let base = groupURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Fundus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Für alles, was sich die Apps teilen — nicht unter „Fundus“, sondern daneben.
    static let sharedDirectory: URL? = {
        guard let groupURL else { return nil }
        let dir = groupURL.appendingPathComponent("eigenhand", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let groupURL: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)

    static var isShared: Bool { groupURL != nil }

    /// Was in den Einstellungen stehen soll — ohne Vermutung, mit dem echten Pfad.
    static var describe: String {
        isShared
            ? "Gemeinsamer Ordner der eigenhand-Apps (\(groupIdentifier))"
            : "Nur in dieser App — die App Group ist in diesem Build nicht freigeschaltet."
    }
}

/// Der Endpoint, den sich die Apps teilen können.
///
/// Die kleinste ehrliche Fassung eines Konnektors: eine Datei im gemeinsamen Ordner
/// mit Adresse, Pfad und Modellname, und der Schlüssel daneben in der gemeinsamen
/// Schlüsselbundgruppe. Wer eine der drei Apps einrichtet, hat damit alle drei
/// eingerichtet.
///
/// Kein Austausch von Daten, nur von Zugang. Das ist die Grenze, die diese Datei
/// absichtlich zieht: den Bestand teilen die Apps über den Container, und wer welchen
/// Bestand sehen darf, entscheidet nicht diese Datei.
///
/// Faden schreibt sie noch nicht — heute ist Fundus die App, die sie anlegt. Sobald
/// Faden dasselbe tut, ist die Einrichtung in beiden Richtungen erledigt.
struct SharedEndpoint: Codable, Equatable {
    var baseURL: String
    var path: String
    var model: String
    /// Immer `Keychain.sharedAccount`. Steht mit in der Datei, damit sie für sich
    /// verständlich ist und ein späterer Wechsel nichts stillschweigend bricht.
    var keychainAccount: String
    var writtenBy: String
    var writtenAt: Date

    static var url: URL? {
        SharedContainer.sharedDirectory?.appendingPathComponent("endpoint.json")
    }

    static func read() -> SharedEndpoint? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(SharedEndpoint.self, from: data)
    }

    static func write(_ config: ModelConfig, app: String = "Fundus") {
        guard let url, config.isComplete else { return }
        let record = SharedEndpoint(
            baseURL: config.baseURL, path: config.path, model: config.model,
            keychainAccount: Keychain.sharedAccount, writtenBy: app, writtenAt: Date())
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? e.encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
