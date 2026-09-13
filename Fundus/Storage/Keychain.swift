import Foundation
import Security

/// API-Schlüssel liegen hier und nirgends sonst. Die Einstellungen halten nur den
/// Verweis.
///
/// Mit Zugriffsgruppe, anders als in Faden: ein Schlüssel, den der Nutzer für seinen
/// eigenen Endpoint einträgt, soll nicht dreimal eingetragen werden müssen. Die
/// Gruppe `dev.eigenhand.shared` steht in den Berechtigungen und ist der Ort, an dem
/// sich die Apps einen Zugang teilen.
///
/// Ein Element *ohne* Gruppe landet in der Standardgruppe der App und ist für die
/// anderen unsichtbar — das ist der richtige Ort für alles, was nur diese App
/// betrifft. Beides gibt es deshalb, und der Aufrufer entscheidet.
enum Keychain {
    private static let service = "dev.eigenhand.fundus.keys"

    /// Der Kontoname, unter dem der geteilte Endpoint-Schlüssel liegt. Stabil und
    /// nicht zufällig, denn die anderen Apps müssen ihn kennen, ohne ihn zu erfahren.
    static let sharedAccount = "eigenhand.shared.endpoint"

    /// Die Gruppe, in der geteilte Elemente liegen. Der Präfix mit der Team-ID kommt
    /// vom System; hier steht nur der Rest, denn `kSecAttrAccessGroup` erwartet die
    /// aufgelöste Form und die Berechtigungsdatei setzt `$(AppIdentifierPrefix)`
    /// davor. Ohne Team-Präfix schlägt der Zugriff mit `errSecMissingEntitlement`
    /// fehl — deshalb wird er hier aus dem eigenen Zugriffsrecht gelesen statt
    /// einkompiliert.
    private static var sharedGroup: String? {
        guard let prefix = teamPrefix else { return nil }
        return prefix + "dev.eigenhand.shared"
    }

    /// Der Team-Präfix, aus einem Testelement erfragt.
    ///
    /// Es gibt keine API, die ihn direkt nennt. Der übliche Weg ist, ein Element ohne
    /// Gruppe anzulegen und dessen `kSecAttrAccessGroup` zu lesen — das System füllt
    /// dabei die Standardgruppe ein, und die beginnt mit dem Präfix. Einmal pro
    /// Programmlauf, danach gemerkt.
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
        // Fehlt die Gruppe im Profil, schlägt der geteilte Weg fehl. Dann in die
        // eigene Gruppe, statt den Nutzer ohne Schlüssel dastehen zu lassen.
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
        // Ein Schlüssel, der vor der Freischaltung der Gruppe angelegt wurde, liegt
        // in der eigenen Gruppe. Dort nachsehen, statt ihn für verloren zu erklären.
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
