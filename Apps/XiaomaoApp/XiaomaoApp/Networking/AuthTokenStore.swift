import Foundation
import Security

enum RuntimeCredentialNormalizer {
    static func token(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("bearer ") {
            normalized = String(normalized.dropFirst(7))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized
    }

    static func deviceID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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

enum CredentialState: Equatable, Sendable {
    case noCredentials
    case loading
    case valid(AuthCredentials)
    case refreshing(AuthCredentials)
    case expired
    case revoked

    var allowsChat: Bool {
        if case .valid(let credentials) = self { return credentials.hasAccessToken }
        return false
    }

    var allowsVoice: Bool { allowsChat }

    var allowsHome: Bool { allowsChat }

    var allowsBindingFlow: Bool {
        switch self {
        case .noCredentials, .expired, .revoked:
            return true
        case .loading, .valid, .refreshing:
            return false
        }
    }
}

actor MemoryCredentialProvider: CredentialProviding {
    private var credentials: AuthCredentials?

    init(credentials: AuthCredentials? = nil) {
        self.credentials = credentials
    }

    func obtainCredentials() async throws -> AuthCredentials? { credentials }

    func refreshCredentials(_ credentials: AuthCredentials) async throws -> AuthCredentials? {
        self.credentials = credentials
        return credentials
    }

    func clearCredentials() async throws { credentials = nil }
}

actor MockCredentialProvider: CredentialProviding {
    private(set) var obtainCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var clearCallCount = 0
    private var credentials: AuthCredentials?

    init(credentials: AuthCredentials? = nil) {
        self.credentials = credentials
    }

    func obtainCredentials() async throws -> AuthCredentials? {
        obtainCallCount += 1
        return credentials
    }

    func refreshCredentials(_ credentials: AuthCredentials) async throws -> AuthCredentials? {
        refreshCallCount += 1
        self.credentials = credentials
        return credentials
    }

    func clearCredentials() async throws {
        clearCallCount += 1
        credentials = nil
    }
}

enum DeviceBindingState: Equatable, Sendable {
    case unbound
    case binding
    case bound(deviceID: String)
    case expired
    case rebinding
    case unbinding

    var allowsHome: Bool {
        if case .bound(let deviceID) = self {
            return !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    var allowsBindingFlow: Bool {
        switch self {
        case .unbound, .expired:
            return true
        case .binding, .bound(_), .rebinding, .unbinding:
            return false
        }
    }

    func canTransition(to next: DeviceBindingState) -> Bool {
        switch (self, next) {
        case (.unbound, .binding),
             (.binding, .bound(_)),
             (.binding, .unbound),
             (.bound(_), .expired),
             (.bound(_), .unbinding),
             (.expired, .rebinding),
             (.expired, .binding),
             (.rebinding, .bound(_)),
             (.rebinding, .expired),
             (.unbinding, .unbound):
            return true
        default:
            return false
        }
    }
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

actor MemoryDeviceBindingProvider: DeviceBindingProviding {
    private var state: DeviceBindingState

    init(state: DeviceBindingState = .unbound) {
        self.state = state
    }

    func currentState() async -> DeviceBindingState { state }

    func bind() async throws -> DeviceBindingState {
        state = .binding
        return state
    }

    func unbind() async throws -> DeviceBindingState {
        state = .unbinding
        return state
    }

    func transition(to next: DeviceBindingState) -> Bool {
        guard state.canTransition(to: next) else { return false }
        state = next
        return true
    }
}

actor MockDeviceBindingProvider: DeviceBindingProviding {
    private(set) var currentStateCallCount = 0
    private(set) var bindCallCount = 0
    private(set) var unbindCallCount = 0
    private var state: DeviceBindingState

    init(state: DeviceBindingState = .unbound) {
        self.state = state
    }

    func currentState() async -> DeviceBindingState {
        currentStateCallCount += 1
        return state
    }

    func bind() async throws -> DeviceBindingState {
        bindCallCount += 1
        state = .binding
        return state
    }

    func unbind() async throws -> DeviceBindingState {
        unbindCallCount += 1
        state = .unbinding
        return state
    }
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
        let normalized = RuntimeCredentialNormalizer.token(token)
        guard !normalized.isEmpty else { throw AppError.unauthorized }
        try clear()
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(normalized.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
    func save(_ token: String) throws { self.token = RuntimeCredentialNormalizer.token(token) }
    func clear() throws { token = nil }
}
