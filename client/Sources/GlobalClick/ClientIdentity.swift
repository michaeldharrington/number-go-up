import Foundation
import Security

/// Opaque per-install identity: a UUID minted on first launch and kept in
/// the Keychain (generic password) so it survives app reinstalls and never
/// syncs anywhere. No accounts, no PII — the server only ever sees the UUID.
enum ClientIdentity {
    private static let service = "com.globalclick.client-id"
    private static let account = "default"

    static let id: String = load() ?? create()

    private static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8)
        else { return nil }
        return s
    }

    private static func create() -> String {
        let uuid = UUID().uuidString.lowercased()
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: Data(uuid.utf8),
        ]
        SecItemAdd(attrs as CFDictionary, nil)
        // If the add failed (e.g. sandbox oddity) we still return the UUID;
        // worst case a new one is minted next launch and the old click
        // history is orphaned — cosmetic, not fatal.
        return uuid
    }
}
