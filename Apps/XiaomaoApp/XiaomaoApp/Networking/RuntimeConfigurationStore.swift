import Foundation
import Security

struct RuntimeConfiguration: Codable, Equatable, Sendable {
    let apiBaseURL: URL
    let voiceWebSocketURL: URL
    let deviceID: String
}

protocol RuntimeConfigurationStoring: Sendable {
    func load() -> RuntimeConfiguration?
    func save(_ configuration: RuntimeConfiguration) throws
    func clear() throws
}

struct KeychainRuntimeConfigurationStore: RuntimeConfigurationStoring {
    private let service = "com.example.xiaomao.runtime"
    private let account = "production-configuration"

    func load() -> RuntimeConfiguration? {
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
        return try? JSONDecoder().decode(RuntimeConfiguration.self, from: data)
    }

    func save(_ configuration: RuntimeConfiguration) throws {
        try clear()
        let data = try JSONEncoder().encode(configuration)
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ] as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppError.unauthorized }
    }

    func clear() throws {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}
