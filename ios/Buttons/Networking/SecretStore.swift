import Foundation
import Security

/// A namespaced key-value store for secrets — Keychain-backed in
/// production, fakeable in tests. Reusable beyond pairing: any future
/// feature needing to persist a secret (a Tier 2 integration's API
/// token, say) is a new namespace, not a new protocol. See
/// docs/slices/11a. Pairing Flow Robustness.spec.md.
protocol SecretStore {
    /// The stored value for `key` under `namespace`, or nil if nothing's
    /// stored (or the read fails).
    func read(namespace: String, key: String) -> String?

    /// Stores `value` for `key` under `namespace` — an upsert,
    /// overwriting any existing value rather than failing on conflict.
    func write(_ value: String, namespace: String, key: String)

    /// Removes any stored value for `key` under `namespace`.
    /// A no-op if nothing's stored.
    func delete(namespace: String, key: String)

    /// Every key currently stored under `namespace`.
    func keys(namespace: String) -> [String]
}

/// The concrete, Keychain-backed `SecretStore`. Keychain's own
/// vocabulary (`kSecAttrService`/`kSecAttrAccount`) stays internal to
/// this class, never leaking into the protocol above.
final class KeychainStore: SecretStore {
    private func query(namespace: String, key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: namespace,
            kSecAttrAccount as String: key,
        ]
    }

    func read(namespace: String, key: String) -> String? {
        var lookup = query(namespace: namespace, key: key)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, namespace: String, key: String) {
        let base = query(namespace: namespace, key: key)
        let data = Data(value.utf8)
        let status = SecItemCopyMatching(base as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var newItem = base
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    func delete(namespace: String, key: String) {
        SecItemDelete(query(namespace: namespace, key: key) as CFDictionary)
    }

    func keys(namespace: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: namespace,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
