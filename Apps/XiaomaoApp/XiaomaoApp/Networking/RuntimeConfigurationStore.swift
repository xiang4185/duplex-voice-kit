import Foundation
import Security

struct RuntimeConfiguration: Codable, Equatable, Sendable {
    let apiBaseURL: URL
    let voiceWebSocketURL: URL
    let deviceID: String
    let chatTargetDeviceID: String?

    init(
        apiBaseURL: URL,
        voiceWebSocketURL: URL,
        deviceID: String,
        chatTargetDeviceID: String? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.voiceWebSocketURL = voiceWebSocketURL
        self.deviceID = deviceID
        self.chatTargetDeviceID = chatTargetDeviceID
    }
}

enum RuntimeConnectionBundleError: Error, Equatable {
    case invalidFormat
    case invalidConfiguration
}

struct RuntimeConnectionBundle: Equatable, Sendable {
    private struct Payload: Codable, Equatable, Sendable {
        let backend: String
        let voice: String
        let device: String
        let token: String
        let target: String?
    }

    static let prefix = "XM1."

    let configuration: RuntimeConfiguration
    let token: String

    static func decode(_ value: String) throws -> RuntimeConnectionBundle {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix(prefix) else {
            throw RuntimeConnectionBundleError.invalidFormat
        }
        let encoded = String(normalized.dropFirst(prefix.count))
        guard !encoded.isEmpty,
              let data = Data(base64URLString: encoded),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw RuntimeConnectionBundleError.invalidFormat
        }

        let backend = payload.backend.trimmingCharacters(in: .whitespacesAndNewlines)
        let voice = payload.voice.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = RuntimeCredentialNormalizer.deviceID(payload.device)
        let token = RuntimeCredentialNormalizer.token(payload.token)
        let target = payload.target.map(RuntimeCredentialNormalizer.deviceID)
        guard let backendURL = URL(string: backend),
              backendURL.scheme?.lowercased() == "https",
              backendURL.host?.isEmpty == false,
              let voiceURL = URL(string: voice),
              voiceURL.scheme?.lowercased() == "wss",
              voiceURL.host?.isEmpty == false,
              !device.isEmpty,
              !token.isEmpty else {
            throw RuntimeConnectionBundleError.invalidConfiguration
        }
        return RuntimeConnectionBundle(
            configuration: RuntimeConfiguration(
                apiBaseURL: backendURL,
                voiceWebSocketURL: voiceURL,
                deviceID: device,
                chatTargetDeviceID: target?.isEmpty == false ? target : nil
            ),
            token: token
        )
    }

    static func encode(configuration: RuntimeConfiguration, token: String) throws -> String {
        let normalizedToken = RuntimeCredentialNormalizer.token(token)
        let normalizedTarget = configuration.chatTargetDeviceID
            .map(RuntimeCredentialNormalizer.deviceID)
        guard !normalizedToken.isEmpty else {
            throw RuntimeConnectionBundleError.invalidConfiguration
        }
        let payload = Payload(
            backend: configuration.apiBaseURL.absoluteString,
            voice: configuration.voiceWebSocketURL.absoluteString,
            device: RuntimeCredentialNormalizer.deviceID(configuration.deviceID),
            token: normalizedToken,
            target: normalizedTarget?.isEmpty == false ? normalizedTarget : nil
        )
        let data = try JSONEncoder().encode(payload)
        return prefix + data.base64URLEncodedString()
    }
}

private extension Data {
    init?(base64URLString: String) {
        var base64 = base64URLString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
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
