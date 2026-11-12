import Foundation
import Security

/// The relay token lives in the login Keychain. It used to sit in UserDefaults, a plist any
/// process of the user can read and that ends up in backups; whoever holds it can pose as
/// this Mac on the relay and receive the phone's commands.
enum RelayTokenStore {
    /// Tests point this at their own item so they never touch the real token.
    static var service = "dev.mikaeldavid.hatchling.relay"
    private static let account = "mac-token"

    static var token: String {
        get {
            // A value still in UserDefaults is newer than anything in the Keychain: only an
            // older build writes there. If the Keychain refuses it, keep using it from there.
            if let legacy = migrateFromDefaults() { return legacy }
            return read() ?? ""
        }
        set { write(newValue) }
    }

    /// One-time move out of UserDefaults. The old value is removed only after the Keychain
    /// accepted it, so a failure never loses the token. Returns the value when it could not move.
    private static func migrateFromDefaults() -> String? {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: SettingsKey.mobileRelayToken), !legacy.isEmpty else { return nil }
        guard write(legacy) else { return legacy }
        defaults.removeObject(forKey: SettingsKey.mobileRelayToken)
        return nil
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func write(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [errSecSuccess, errSecItemNotFound].contains(SecItemDelete(baseQuery() as CFDictionary))
        }
        let data = Data(trimmed.utf8)
        let update = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = baseQuery()
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
