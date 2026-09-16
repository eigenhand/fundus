import Foundation

/// Inventory and settings as two files. Small enough that a database would be a
/// dependency without return — a household inventory is a few hundred lines, and those
/// are loaded once and then kept in memory.
///
/// As plain-text JSON and not in a format of its own, because the inventory belongs to
/// the user: it lies in the shared folder, Spind can synchronise it, and whoever needs
/// it elsewhere can read it without owning this app.
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
        // Sorted and indented, so that two versions of the same file can be told apart
        // in a diff. Spind synchronises it, and a line order that shuffles on every save
        // turns a change to one thing into a change to everything.
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

    /// The inventory as a file to pass on. The same JSON, only elsewhere — there is no
    /// reason to invent a second format for an export.
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
