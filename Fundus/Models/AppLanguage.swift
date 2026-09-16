import Foundation

/// Die Sprache der Oberfläche.
///
/// iOS kennt dafür bereits eine Einstellung — sie steht in den Systemeinstellungen
/// unter der App und erzwingt einen Neustart. Diese hier wirkt sofort.
///
/// Der naheliegende Weg dahin funktioniert nicht, und das steht hier, weil er sonst
/// beim nächsten Aufräumen wieder eingebaut wird: `.environment(\.locale, …)` an der
/// Wurzel **stellt die Oberfläche nicht um**. Die Locale aus der Umgebung steuert,
/// wie Zahlen und Daten aussehen, nicht, in welchem `.lproj` ein `Text` seinen
/// Schlüssel sucht. Ein UI-Test darauf war rot, bevor diese Fassung entstand.
///
/// Was trägt, ist das Bündel selbst: `Bundle.main` bekommt zur Laufzeit eine
/// Unterklasse untergeschoben, die jedes Nachschlagen in das gewählte `.lproj`
/// umleitet. Damit folgt alles derselben Wahl — `Text`, `String(localized:)`, auch
/// eine Fehlermeldung, die tief in einem Modell entsteht und keine Umgebung sieht.
///
/// Die Grenze bleibt: Systemdialoge, die nach Kamera oder Mikrofon fragen, gehören
/// nicht der App. Sie folgen der Sprache des Geräts, und dafür liegen die Texte
/// übersetzt in `InfoPlist.xcstrings`.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case german
    case english

    var id: String { rawValue }

    /// `nil` heißt: das Gerät entscheidet.
    var code: String? {
        switch self {
        case .system:  return nil
        case .german:  return "de"
        case .english: return "en"
        }
    }

    /// Die Locale für Zahlen, Daten und Sortierung. `nil` lässt die des Geräts stehen.
    var locale: Locale? { code.map(Locale.init(identifier:)) }

    /// Jede Sprache nennt sich selbst — wer die Oberfläche gerade nicht versteht,
    /// erkennt „English“ auch dann, wenn ringsherum Deutsch steht. Nur die
    /// Systemzeile wird übersetzt, denn sie beschreibt keine Sprache, sondern eine
    /// Entscheidung.
    var label: String {
        switch self {
        case .system:  return String(localized: "Sprache des Geräts")
        case .german:  return "Deutsch"
        case .english: return "English"
        }
    }

    /// Das Bündel, aus dem Text außerhalb von SwiftUI kommt — Fehlermeldungen etwa,
    /// die in einem Modell entstehen und keine Umgebung sehen. Fehlt die Sprache im
    /// Bündel, bleibt es beim Hauptbündel; ein fehlendes `.lproj` ist kein Grund,
    /// gar keinen Text mehr zu haben.
    var bundle: Bundle {
        guard let code,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    // MARK: Anwenden

    /// Leitet jedes Nachschlagen in dieser App auf die gewählte Sprache um.
    ///
    /// Beim ersten Aufruf wird `Bundle.main` die Klasse getauscht. Das ist der
    /// Eingriff, den diese Funktion rechtfertigen muss: Es gibt keine unterstützte
    /// Stelle, an der sich die Sprache einer laufenden App umstellen lässt, und die
    /// Alternative wäre, jeden Aufruf im Quelltext ein Bündel
    /// mittragen zu lassen — und beim dreihundertersten zu vergessen.
    @MainActor
    static func apply(_ language: AppLanguage) {
        if !swapped {
            object_setClass(Bundle.main, SwitchableBundle.self)
            swapped = true
        }
        SwitchableBundle.chosen = language.code.flatMap {
            Bundle.main.path(forResource: $0, ofType: "lproj").flatMap(Bundle.init(path:))
        }
    }

    @MainActor private static var swapped = false
}

/// Die untergeschobene Klasse. Sie beantwortet genau eine Frage anders als das
/// Original und reicht alles übrige weiter.
private final class SwitchableBundle: Bundle, @unchecked Sendable {
    /// `nil` heißt: das Gerät entscheidet, also das Original antworten lassen.
    nonisolated(unsafe) static var chosen: Bundle?

    override func localizedString(forKey key: String, value: String?, table: String?) -> String {
        guard let chosen = SwitchableBundle.chosen else {
            return super.localizedString(forKey: key, value: value, table: table)
        }
        return chosen.localizedString(forKey: key, value: value, table: table)
    }
}
