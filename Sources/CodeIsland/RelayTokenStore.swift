import Foundation
import Security

/// The relay token lives in the login Keychain. It used to sit in UserDefaults, a plist any
/// process of the user can read and that ends up in backups; whoever holds it can pose as
/// this Mac on the relay and receive the phone's commands.
enum RelayTokenStore {
    private static let service = "dev.mikaeldavid.hatchling.relay"
    private static let account = "mac-token"

    static var token: String {
        get {
            migrateFromDefaultsIfNeeded()
            return read() ?? ""
        }
        set { write(newValue) }
    }

    /// One-time move out of UserDefaults. The old value is removed only after the Keychain
    /// accepted it, so a failure never loses the token.
    private static func migrateFromDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: SettingsKey.mobileRelayToken), !legacy.isEmpty else { return }
        if read() == nil, !write(legacy) { return }
        defaults.removeObject(forKey: SettingsKey.mobileRelayToken)
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
