import Foundation
import Security

/// API keys live here and nowhere else. The settings hold only the reference.
///
/// With an access group, unlike in Faden: a key the user enters for their own endpoint
/// should not have to be entered three times. The group `dev.eigenhand.shared` stands
/// in the entitlements and is the place where the apps share access.
///
/// An item *without* a group lands in the app's default group and is invisible to the
/// others — that is the right place for everything that concerns only this app. Both
/// exist for that reason, and the caller decides.
enum Keychain {
    private static let service = "dev.eigenhand.fundus.keys"

    /// The account name under which the shared endpoint key lives. Stable and not
    /// random, because the other apps have to know it without being told it.
    static let sharedAccount = "eigenhand.shared.endpoint"

    /// The group shared items live in. The prefix with the team ID comes from the
    /// system; only the rest stands here, because `kSecAttrAccessGroup` expects the
    /// resolved form and the entitlements file puts `$(AppIdentifierPrefix)` in front.
    /// Without the team prefix, access fails with `errSecMissingEntitlement` — which is
    /// why it is read here out of the app's own entitlement rather than compiled in.
    private static var sharedGroup: String? {
        guard let prefix = teamPrefix else { return nil }
        return prefix + "dev.eigenhand.shared"
    }

    /// The team prefix, asked of a probe item.
    ///
    /// There is no API that states it directly. The usual route is to create an item
    /// without a group and read its `kSecAttrAccessGroup` — the system fills the default
    /// group in, and that begins with the prefix. Once per run of the program, then
    /// remembered.
    private static let teamPrefix: String? = {
        let probeAccount = "fundus.prefix.probe"
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: probeAccount,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data("x".utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
        defer { SecItemDelete(base as CFDictionary) }

        var query = base
        query[kSecReturnAttributes as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let attrs = out as? [String: Any],
              let group = attrs[kSecAttrAccessGroup as String] as? String,
              let dot = group.firstIndex(of: ".")
        else { return nil }
        return String(group[group.startIndex ... dot])
    }()

    private static func query(_ account: String, shared: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared, let sharedGroup { q[kSecAttrAccessGroup as String] = sharedGroup }
        return q
    }

    @discardableResult
    static func set(_ value: String, account: String, shared: Bool = false) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return delete(account: account, shared: shared) }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let q = query(account, shared: shared)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            return SecItemAdd(q.merging(attrs, uniquingKeysWith: { $1 }) as CFDictionary, nil) == errSecSuccess
        }
        // If the group is missing from the profile, the shared route fails. Then into
        // the app's own group, rather than leaving the user without a key.
        if shared { return set(value, account: account, shared: false) }
        return false
    }

    static func get(account: String, shared: Bool = false) -> String? {
        var q = query(account, shared: shared)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, let s = String(data: data, encoding: .utf8) {
            return s
        }
        // A key created before the group was enabled lives in the app's own group. Look
        // there rather than declaring it lost.
        if shared { return get(account: account, shared: false) }
        return nil
    }

    @discardableResult
    static func delete(account: String, shared: Bool = false) -> Bool {
        let s = SecItemDelete(query(account, shared: shared) as CFDictionary)
        if shared { SecItemDelete(query(account, shared: false) as CFDictionary) }
        return s == errSecSuccess || s == errSecItemNotFound
    }

    static func has(account: String, shared: Bool = false) -> Bool {
        get(account: account, shared: shared)?.isEmpty == false
    }
}
