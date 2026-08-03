import Foundation

/// Identifies whether the runtime is in public mock mode, private live mode,
/// or an unusable partial configuration that must never reach the network.
public enum DVKRuntimeMode: String, Codable, Equatable, Sendable {
    case mock
    case live
    case misconfigured
}

/// Provider-neutral runtime configuration for the Companion showcase.
///
/// Public default: all three connection values empty -> mock mode, zero network
/// access. Private live mode is enabled only through a local, never-committed
/// build configuration that supplies an HTTPS API base URL, a WSS voice URL and
/// a non-empty device identifier. A partial set is an explicit misconfiguration.
public struct DVKRuntimeConfiguration: Codable, Equatable, Sendable {
    public let apiBaseURL: URL?
    public let voiceWebSocketURL: URL?
    public let deviceID: String
    public let enableMock: Bool
    public let buildSHA: String
    public let buildTime: String

    public init(
        apiBaseURL: URL?,
        voiceWebSocketURL: URL?,
        deviceID: String,
        enableMock: Bool = false,
        buildSHA: String = "",
        buildTime: String = ""
    ) {
        self.apiBaseURL = apiBaseURL
        self.voiceWebSocketURL = voiceWebSocketURL
        self.deviceID = deviceID
        self.enableMock = enableMock
        self.buildSHA = buildSHA
        self.buildTime = buildTime
    }

    /// The public default configuration: fully empty, mock-only, no network.
    public static let mock = DVKRuntimeConfiguration(
        apiBaseURL: nil,
        voiceWebSocketURL: nil,
        deviceID: ""
    )

    /// Defines the three distinct runtime states:
    /// 1. all connection values empty -> mock;
    /// 2. all connection values present and valid -> live;
    /// 3. a partial set -> misconfigured (no network requests are allowed).
    public var mode: DVKRuntimeMode {
        if enableMock || Self.isMissing(apiBaseURL, voiceWebSocketURL, deviceID) {
            return .mock
        }
        if Self.isAllowedRemoteURL(apiBaseURL, scheme: "https"),
           Self.isAllowedRemoteURL(voiceWebSocketURL, scheme: "wss"),
           !Self.normalizedDeviceID(deviceID).isEmpty {
            return .live
        }
        return .misconfigured
    }

    public var isLive: Bool { mode == .live }
    public var isMock: Bool { mode == .mock }

    public var statusDescription: String {
        switch mode {
        case .mock: return "Mock — local only, no network access."
        case .live: return "Live — ready for a private gateway connection."
        case .misconfigured: return "Misconfigured — partial values, network disabled."
        }
    }

    /// Builds a configuration from Info.plist keys that a local build
    /// configuration may inject (API_BASE_URL, VOICE_WS_URL, DEVICE_ID,
    /// ENABLE_MOCK, APP_BUILD_SHA, APP_BUILD_TIME). Missing values stay empty
    /// and the runtime defaults to mock mode.
    public static func fromInfoDictionary(_ info: [String: Any]) -> DVKRuntimeConfiguration {
        func value(_ key: String) -> String { info[key] as? String ?? "" }
        return DVKRuntimeConfiguration(
            apiBaseURL: Self.cleanURL(value("API_BASE_URL")),
            voiceWebSocketURL: Self.cleanURL(value("VOICE_WS_URL")),
            deviceID: value("DEVICE_ID"),
            enableMock: value("ENABLE_MOCK").uppercased() == "YES",
            buildSHA: value("APP_BUILD_SHA"),
            buildTime: value("APP_BUILD_TIME")
        )
    }

    /// Builds a configuration from process environment variables. Exists so
    /// command-line tooling and tests can construct configurations without
    /// touching Bundle or Info.plist.
    public static func fromProcessInfo(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DVKRuntimeConfiguration {
        DVKRuntimeConfiguration(
            apiBaseURL: Self.cleanURL(environment["API_BASE_URL"] ?? ""),
            voiceWebSocketURL: Self.cleanURL(environment["VOICE_WS_URL"] ?? ""),
            deviceID: environment["DEVICE_ID"] ?? "",
            enableMock: (environment["ENABLE_MOCK"] ?? "").uppercased() == "YES",
            buildSHA: environment["APP_BUILD_SHA"] ?? "",
            buildTime: environment["APP_BUILD_TIME"] ?? ""
        )
    }

    // MARK: - Validation

    private static func isMissing(_ api: URL?, _ voice: URL?, _ device: String) -> Bool {
        api == nil && voice == nil && normalizedDeviceID(device).isEmpty
    }

    /// Live URLs must use the required scheme and carry a non-empty host.
    /// No real default address is ever provided by the repository.
    public static func isAllowedRemoteURL(_ url: URL?, scheme: String) -> Bool {
        guard let url,
              url.scheme?.lowercased() == scheme,
              let host = url.host?.lowercased(),
              !host.isEmpty else { return false }
        return true
    }

    private static func cleanURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private static func normalizedDeviceID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
