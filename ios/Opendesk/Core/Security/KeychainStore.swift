import Foundation
import Security

/// Generic-password Keychain items for this app: refresh tokens and App
/// Attest key ids, one per server. Readable after first unlock (push wakes
/// and background refresh) and never synced or backed up to another device.
enum KeychainStore {
    private static let service = "sh.opendesk.app"

    static func set(_ value: String, for account: String) {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.setKeychainValue(value, for: account) }
        #endif
        let data = Data(value.utf8)
        let query = baseQuery(account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func get(_ account: String) -> String? {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.keychainValue(account) }
        #endif
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.setKeychainValue(nil, for: account) }
        #endif
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
