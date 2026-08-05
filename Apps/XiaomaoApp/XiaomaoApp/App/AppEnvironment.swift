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
        self.hostAdapters = hostAdapters
    }

    var isRuntimeConfigurationReady: Bool {
        if enableMockVoice { return true }
        return isBackendConfigurationReady && isVoiceConfigurationReady
    }

    var isBackendConfigurationReady: Bool {
        Self.isAllowedRemoteURL(apiBaseURL, scheme: "https") && hasDeviceID
    }

    var isVoiceConfigurationReady: Bool {
        if enableMockVoice { return true }
        return Self.isAllowedRemoteURL(voiceWebSocketURL, scheme: "wss") && hasDeviceID
    }

    func canStartBackendRequest(hasToken: Bool) -> Bool {
        isBackendConfigurationReady && hasToken
    }

    func canStartVoiceConnection(hasToken: Bool) -> Bool {
        enableMockVoice || (isVoiceConfigurationReady && hasToken)
    }

    private var hasDeviceID: Bool {
        !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var runtimeConfigurationMessage: String {
        if enableMockVoice || isRuntimeConfigurationReady {
            return "服务器配置已就绪"
        }
        return "此安装包尚未配置 HTTPS API、WSS 语音地址或设备 ID。请使用手动 Actions 构建参数重新生成测试包。"
    }

    static func fromBundle(
        _ bundle: Bundle = .main,
        hostAdapters: HostAdapterDependencies = .empty
    ) -> AppEnvironment {
        func value(_ key: String) -> String { bundle.object(forInfoDictionaryKey: key) as? String ?? "" }
        return AppEnvironment(
            apiBaseURL: URL(string: value("API_BASE_URL")),
            voiceWebSocketURL: URL(string: value("VOICE_WS_URL")),
            deviceID: value("DEVICE_ID"),
            appEnvironment: value("APP_ENVIRONMENT"),
            enableMockVoice: value("ENABLE_MOCK_VOICE").uppercased() == "YES",
            enableMemory: value("ENABLE_MEMORY").uppercased() == "YES",
            defaultVoiceRoute: VoiceRoute(rawValue: value("DEFAULT_VOICE_ROUTE")) ?? .b,
            appBuildSHA: value("APP_BUILD_SHA"),
            appBuildTime: value("APP_BUILD_TIME"),
            hostAdapters: hostAdapters
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
