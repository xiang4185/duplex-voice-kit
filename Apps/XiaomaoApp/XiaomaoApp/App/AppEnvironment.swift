import Foundation

struct AppEnvironment: Sendable {
    let apiBaseURL: URL?
    let voiceWebSocketURL: URL?
    let deviceID: String
    let appEnvironment: String
    let enableMockVoice: Bool
    let enableMemory: Bool
    let defaultVoiceRoute: VoiceRoute
    let appBuildSHA: String
    let appBuildTime: String
    let requestedHostAdapterMode: HostAdapterMode
    let hostAdapters: HostAdapterDependencies

    init(
        apiBaseURL: URL?,
        voiceWebSocketURL: URL?,
        deviceID: String,
        appEnvironment: String,
        enableMockVoice: Bool,
        enableMemory: Bool,
        defaultVoiceRoute: VoiceRoute,
        appBuildSHA: String,
        appBuildTime: String,
        requestedHostAdapterMode: HostAdapterMode? = nil,
        hostAdapters: HostAdapterDependencies = .empty
    ) {
        self.apiBaseURL = apiBaseURL
        self.voiceWebSocketURL = voiceWebSocketURL
        self.deviceID = deviceID
        self.appEnvironment = appEnvironment
        self.enableMockVoice = enableMockVoice
        self.enableMemory = enableMemory
        self.defaultVoiceRoute = defaultVoiceRoute
        self.appBuildSHA = appBuildSHA
        self.appBuildTime = appBuildTime
        self.requestedHostAdapterMode = requestedHostAdapterMode
            ?? (enableMockVoice ? .mock : .empty)
        self.hostAdapters = hostAdapters
    }

    var isRuntimeConfigurationReady: Bool {
        switch hostAdapters.mode {
        case .empty:
            return false
        case .mock:
            return true
        case .production:
            return isBackendConfigurationReady && isVoiceConfigurationReady
        }
    }

    var isBackendConfigurationReady: Bool {
        Self.isAllowedRemoteURL(apiBaseURL, scheme: "https") && hasDeviceID
    }

    var isVoiceConfigurationReady: Bool {
        if hostAdapters.mode == .mock { return true }
        return Self.isAllowedRemoteURL(voiceWebSocketURL, scheme: "wss") && hasDeviceID
    }

    func canStartBackendRequest(hasToken: Bool) -> Bool {
        hostAdapters.mode == .production && isBackendConfigurationReady && hasToken
    }

    func canStartVoiceConnection(hasToken: Bool) -> Bool {
        hostAdapters.mode == .mock || (
            hostAdapters.mode == .production && isVoiceConfigurationReady && hasToken
        )
    }

    private var hasDeviceID: Bool {
        !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var runtimeConfigurationMessage: String {
        if isRuntimeConfigurationReady {
            return "服务器配置已就绪"
        }
        return "此安装包未启用完整的安全运行配置。请在可信构建环境中注入 HTTPS、WSS、设备绑定与凭据材料。"
    }

    static func fromBundle(
        _ bundle: Bundle = .main,
        hostAdapters: HostAdapterDependencies = .empty
    ) -> AppEnvironment {
        func value(_ key: String) -> String { bundle.object(forInfoDictionaryKey: key) as? String ?? "" }
        let enableMockVoice = value("ENABLE_MOCK_VOICE").uppercased() == "YES"
        return AppEnvironment(
            apiBaseURL: URL(string: value("API_BASE_URL")),
            voiceWebSocketURL: URL(string: value("VOICE_WS_URL")),
            deviceID: value("DEVICE_ID"),
            appEnvironment: value("APP_ENVIRONMENT"),
            enableMockVoice: enableMockVoice,
            enableMemory: value("ENABLE_MEMORY").uppercased() == "YES",
            defaultVoiceRoute: VoiceRoute(rawValue: value("DEFAULT_VOICE_ROUTE")) ?? .b,
            appBuildSHA: value("APP_BUILD_SHA"),
            appBuildTime: value("APP_BUILD_TIME"),
            requestedHostAdapterMode: HostAdapterMode.requested(
                value("HOST_ADAPTER_MODE"),
                enableMock: enableMockVoice
            ),
            hostAdapters: hostAdapters
        )
    }

    func replacingHostAdapters(_ dependencies: HostAdapterDependencies) -> AppEnvironment {
        AppEnvironment(
            apiBaseURL: apiBaseURL,
            voiceWebSocketURL: voiceWebSocketURL,
            deviceID: deviceID,
            appEnvironment: appEnvironment,
            enableMockVoice: enableMockVoice,
            enableMemory: enableMemory,
            defaultVoiceRoute: defaultVoiceRoute,
            appBuildSHA: appBuildSHA,
            appBuildTime: appBuildTime,
            requestedHostAdapterMode: requestedHostAdapterMode,
            hostAdapters: dependencies
        )
    }

    private static func isAllowedRemoteURL(_ url: URL?, scheme: String) -> Bool {
        guard let url,
              url.scheme?.lowercased() == scheme,
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost") {
            return false
        }
        return true
    }
}
