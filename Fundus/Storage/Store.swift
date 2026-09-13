import Foundation

/// Bestand und Einstellungen als zwei Dateien. Klein genug, dass eine Datenbank
/// nur Abhängigkeit ohne Gegenwert wäre — ein Haushaltsbestand sind einige hundert
/// Zeilen, und die werden einmal geladen und danach im Speicher gehalten.
///
/// Als Klartext-JSON und nicht in einem eigenen Format, weil der Bestand dem Nutzer
/// gehört: er liegt im gemeinsamen Ordner, Spind kann ihn synchronisieren, und wer
/// ihn woanders braucht, kann ihn lesen, ohne diese App zu besitzen.
actor Store {
    static let shared = Store()

    private let inventoryURL: URL
    private let settingsURL: URL

    init() {
        let dir = SharedContainer.directory
        inventoryURL = dir.appendingPathComponent("inventory.json")
        settingsURL = dir.appendingPathComponent("settings.json")
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        // Sortiert und eingerückt: damit zwei Fassungen derselben Datei sich in
        // einem Diff unterscheiden lassen. Spind synchronisiert sie, und eine
        // Zeilenordnung, die sich bei jedem Speichern dreht, macht aus einer
        // Änderung an einem Ding eine Änderung an allem.
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func loadInventory() -> Inventory {
        guard let data = try? Data(contentsOf: inventoryURL),
              let inv = try? decoder.decode(Inventory.self, from: data)
        else { return Inventory() }
        return inv
    }

    func save(_ inventory: Inventory) {
        guard let data = try? encoder.encode(inventory) else { return }
        try? data.write(to: inventoryURL, options: .atomic)
    }

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let s = try? decoder.decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return s
    }

    func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    /// Der Bestand als Datei zum Weitergeben. Dasselbe JSON, nur woanders — es gibt
    /// keinen Grund, für einen Export ein zweites Format zu erfinden.
    func exportInventory(_ inventory: Inventory) -> URL? {
        guard let data = try? encoder.encode(inventory) else { return nil }
        let name = "Fundus-\(Self.stamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
