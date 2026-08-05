import Foundation
import Security

struct AuthCredentials: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?

    var hasAccessToken: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

protocol CredentialProviding: Sendable {
    func obtainCredentials() async throws -> AuthCredentials?
    func refreshCredentials(_ credentials: AuthCredentials) async throws -> AuthCredentials?
    func clearCredentials() async throws
}

struct EmptyCredentialProvider: CredentialProviding {
    func obtainCredentials() async throws -> AuthCredentials? { nil }
    func refreshCredentials(_ credentials: AuthCredentials) async throws -> AuthCredentials? {
        _ = credentials
        return nil
    }
    func clearCredentials() async throws {}
}

enum DeviceBindingState: Equatable, Sendable {
    case unbound
    case binding
    case bound(deviceID: String)
    case invalid
    case unbinding
}

protocol DeviceBindingProviding: Sendable {
    func currentState() async -> DeviceBindingState
    func bind() async throws -> DeviceBindingState
    func unbind() async throws -> DeviceBindingState
}

struct EmptyDeviceBindingProvider: DeviceBindingProviding {
    func currentState() async -> DeviceBindingState { .unbound }
    func bind() async throws -> DeviceBindingState { .unbound }
    func unbind() async throws -> DeviceBindingState { .unbound }
}

protocol AuthTokenStoring: Sendable {
    func load() -> String?
    func save(_ token: String) throws
    func clear() throws
}

struct KeychainAuthTokenStore: AuthTokenStoring {
    private let service = "com.example.xiaomao.auth"
    private let account = "development-token"

    func load() -> String? {
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

    func save(_ token: String) throws {
        try clear()
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8)
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

final class MemoryAuthTokenStore: AuthTokenStoring, @unchecked Sendable {
    private var token: String?
    func load() -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}
