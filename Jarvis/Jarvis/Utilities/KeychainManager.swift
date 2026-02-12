import Foundation
import Security

/// Secure keychain storage for API keys
class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.jarvis.api-keys"
    private let anthropicKeyAccount = "anthropic-api-key"

    // MARK: - Anthropic API Key

    func saveAnthropicKey(_ key: String) -> Bool {
        return save(key: key, account: anthropicKeyAccount)
    }

    func getAnthropicKey() -> String? {
        return retrieve(account: anthropicKeyAccount)
    }

    func deleteAnthropicKey() -> Bool {
        return delete(account: anthropicKeyAccount)
    }

    // MARK: - Generic Keychain Operations

    private func save(key: String, account: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        // Delete any existing key first
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func retrieve(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    private func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
