import Foundation

/// Where the data lives: in the shared container of the eigenhand apps, when there is
/// one.
///
/// `group.dev.eigenhand.shared` is the place where the eigenhand apps meet. For Faden
/// that means it can read this inventory without copying it.
///
/// The fallback is not cosmetic. An App Group only applies when the provisioning
/// profile contains it — in the simulator with automatic signing, in a fork with
/// somebody else's team ID and in a build without this entitlement,
/// `containerURL(forSecurityApplicationGroupIdentifier:)` simply returns `nil`. Without
/// a fallback the app would then start with no storage, and silently at that.
///
/// That is why `isShared` stands here and in the settings: which of the two places is
/// used decides whether Faden sees this inventory at all. That is not a small thing to
/// be left to guesswork.
enum SharedContainer {
    static let groupIdentifier = "group.dev.eigenhand.shared"

    /// The directory Fundus works in.
    static let directory: URL = {
        let base = groupURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Fundus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// For everything the apps share — not under "Fundus" but beside it.
    static let sharedDirectory: URL? = {
        guard let groupURL else { return nil }
        let dir = groupURL.appendingPathComponent("eigenhand", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let groupURL: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)

    static var isShared: Bool { groupURL != nil }

    /// What the settings should say — no guesswork, with the real path.
    static var describe: String {
        isShared
            ? String(localized: "Gemeinsamer Ordner der eigenhand-Apps (\(groupIdentifier))")
            : String(localized: "Nur in dieser App — die App Group ist in diesem Build nicht freigeschaltet.")
    }
}

/// The endpoint the apps can share.
///
/// The smallest honest version of a connector: a file in the shared folder with
/// address, path and model name, and the key beside it in the shared keychain group.
/// Meant so that setting up one app sets up the others — once they read it.
///
/// No exchange of data, only of access. That is the line this file deliberately draws:
/// the apps share the inventory through the container, and who may see which inventory
/// is not something this file decides.
///
/// Neither Faden nor Spind reads or writes it yet — today Fundus is the only app that
/// touches it. Until that changes, the setting says only what is stored where.
struct SharedEndpoint: Codable, Equatable {
    var baseURL: String
    var path: String
    var model: String
    /// Always `Keychain.sharedAccount`. It stands in the file so that the file makes
    /// sense on its own and a later change breaks nothing silently.
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
