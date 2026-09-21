import Foundation
import Security

/// Keeps the server's API key in the login keychain.
///
/// A credential does not belong in `UserDefaults`, where the other settings
/// live: those are a plain file, and they double as launch arguments, which
/// show up in `ps`.
nonisolated enum APIKeyStore {
    struct KeychainError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            return "The keychain refused the API key: \(reason)"
        }
    }

    private static var item: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "AppleOnDeviceOpenAI",
            kSecAttrAccount: "api-key",
        ]
    }

    /// Blocks while macOS asks the user for access, which it does when the item
    /// was written by a differently signed build. Call it off the main actor.
    static func load() -> String? {
        var query = item
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// An empty key removes the item.
    static func save(_ key: String) throws {
        let deletion = SecItemDelete(item as CFDictionary)
        guard deletion == errSecSuccess || deletion == errSecItemNotFound else {
            throw KeychainError(status: deletion)
        }
        guard !key.isEmpty else { return }

        var attributes = item
        attributes[kSecValueData] = Data(key.utf8)
        attributes[kSecAttrLabel] = "Apple On-Device OpenAI API key"
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// 32 random bytes, in the shape people recognize as an API key.
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return "sk-local-" + bytes.map { String(format: "%02x", $0) }.joined()
    }
}
