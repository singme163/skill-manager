import Foundation
import Security

/// Optional Anthropic API key storage in the system Keychain — powers the
/// AI-assisted authoring features (Skill Doctor). Bring-your-own-key: the
/// call goes straight to Anthropic on the user's own account, nothing is
/// persisted anywhere else and no data passes through any server of ours.
public enum AnthropicAuth {
    static let service = "com.skillmanager.anthropic-key"
    static let account = "anthropic"

    public static func key() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    public static var hasKey: Bool { key() != nil }

    /// Stores the key, replacing any existing one. Passing nil/empty deletes.
    @discardableResult
    public static func setKey(_ key: String?) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return true
        }
        var attributes = base
        attributes[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
