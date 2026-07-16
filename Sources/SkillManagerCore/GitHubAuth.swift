import Foundation
import Security

/// Optional GitHub token storage in the system Keychain — used for private
/// repositories and higher API rate limits. Never persisted anywhere else.
public enum GitHubAuth {
    static let service = "com.skillmanager.github-token"
    static let account = "github"

    public static func token() -> String? {
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
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    /// Stores the token, replacing any existing one. Passing nil/empty deletes.
    @discardableResult
    public static func setToken(_ token: String?) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return true
        }
        var attributes = base
        attributes[kSecValueData as String] = Data(token.utf8)
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Decorates a GitHub request with auth (when available) and API headers.
    public static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }
}
