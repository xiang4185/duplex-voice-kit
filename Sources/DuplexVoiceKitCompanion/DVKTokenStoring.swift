import Foundation

/// Stores the private live token. Token values are never printed, never written
/// to UserDefaults or Info.plist, and never included in diagnostics.
public protocol DVKTokenStoring: Sendable {
    func load() -> String?
    func save(_ token: String) throws
    func clear() throws
}

public enum DVKTokenStoreError: Error, Equatable, Sendable {
    case keychainSaveFailed
    case keychainClearFailed
}

#if canImport(Security)
import Security

/// Apple-platform Keychain implementation with neutral service/account values.
public struct DVKKeychainTokenStore: DVKTokenStoring {
    private let service = "com.example.duplexvoicekit.auth"
    private let account = "dvk-device-token"

    public init() {}

    public func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) throws {
        try clear()
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8)
        ] as CFDictionary, nil)
        guard status == errSecSuccess else { throw DVKTokenStoreError.keychainSaveFailed }
    }

    public func clear() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw DVKTokenStoreError.keychainClearFailed
        }
    }
}
#endif

/// In-memory implementation used by unit tests and non-Apple platforms.
public final class DVKMemoryTokenStore: DVKTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init() {}

    public func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    public func save(_ token: String) throws {
        lock.lock()
        self.token = token
        lock.unlock()
    }

    public func clear() throws {
        lock.lock()
        token = nil
        lock.unlock()
    }
}
