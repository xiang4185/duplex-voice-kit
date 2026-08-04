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

    var isRuntimeConfigurationReady: Bool {
        if enableMockVoice { return true }
        return Self.isAllowedRemoteURL(apiBaseURL, scheme: "https")
            && Self.isAllowedRemoteURL(voiceWebSocketURL, scheme: "wss")
            && !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var runtimeConfigurationMessage: String {
        if enableMockVoice || isRuntimeConfigurationReady {
            return "服务器配置已就绪"
        }
        return "此安装包尚未配置 HTTPS API、WSS 语音地址或设备 ID。请使用手动 Actions 构建参数重新生成测试包。"
    }

    static func fromBundle(_ bundle: Bundle = .main) -> AppEnvironment {
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
            appBuildTime: value("APP_BUILD_TIME")
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
