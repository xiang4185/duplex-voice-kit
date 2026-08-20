import Foundation

struct AppEnvironment: Sendable {
    let apiBaseURL: URL?
    let voiceWebSocketURL: URL?
    let deviceID: String
    let chatTargetDeviceID: String?
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
        chatTargetDeviceID: String? = nil,
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
        self.chatTargetDeviceID = chatTargetDeviceID
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
        hostAdapters: HostAdapterDependencies = .empty,
        runtimeConfigurationStore: any RuntimeConfigurationStoring = KeychainRuntimeConfigurationStore()
    ) -> AppEnvironment {
        func value(_ key: String) -> String { bundle.object(forInfoDictionaryKey: key) as? String ?? "" }
        let enableMockVoice = value("ENABLE_MOCK_VOICE").uppercased() == "YES"
        let runtimeConfiguration = runtimeConfigurationStore.load()
        let bundleAPIURL = URL(string: value("API_BASE_URL"))
        let bundleVoiceURL = URL(string: value("VOICE_WS_URL"))
        let bundleDeviceID = value("DEVICE_ID")
        let bundleChatTargetDeviceID = value("CHAT_TARGET_DEVICE_ID")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usesRuntimeConfiguration = runtimeConfiguration != nil
        let effectiveDeviceID = runtimeConfiguration?.deviceID ?? bundleDeviceID
        let effectiveChatTargetDeviceID = resolvedChatTargetDeviceID(
            runtimeTarget: runtimeConfiguration?.chatTargetDeviceID,
            bundleTarget: bundleChatTargetDeviceID,
            deviceID: effectiveDeviceID
        )
        return AppEnvironment(
            apiBaseURL: runtimeConfiguration?.apiBaseURL ?? bundleAPIURL,
            voiceWebSocketURL: runtimeConfiguration?.voiceWebSocketURL ?? bundleVoiceURL,
            deviceID: effectiveDeviceID,
            chatTargetDeviceID: effectiveChatTargetDeviceID,
            appEnvironment: value("APP_ENVIRONMENT"),
            enableMockVoice: enableMockVoice,
            enableMemory: value("ENABLE_MEMORY").uppercased() == "YES",
            defaultVoiceRoute: VoiceRoute(rawValue: value("DEFAULT_VOICE_ROUTE")) ?? .b,
            appBuildSHA: value("APP_BUILD_SHA"),
            appBuildTime: value("APP_BUILD_TIME"),
            requestedHostAdapterMode: usesRuntimeConfiguration
                ? .production
                : HostAdapterMode.requested(value("HOST_ADAPTER_MODE"), enableMock: enableMockVoice),
            hostAdapters: hostAdapters
        )
    }

    static func resolvedChatTargetDeviceID(
        runtimeTarget: String?,
        bundleTarget: String?,
        deviceID: String
    ) -> String? {
        let normalizedRuntimeTarget = RuntimeCredentialNormalizer.deviceID(runtimeTarget ?? "")
        let normalizedBundleTarget = RuntimeCredentialNormalizer.deviceID(bundleTarget ?? "")
        let configuredTarget = normalizedRuntimeTarget.isEmpty
            ? normalizedBundleTarget
            : normalizedRuntimeTarget
        guard !configuredTarget.isEmpty, configuredTarget != deviceID else { return nil }
        return configuredTarget
    }

    func replacingHostAdapters(_ dependencies: HostAdapterDependencies) -> AppEnvironment {
        AppEnvironment(
            apiBaseURL: apiBaseURL,
            voiceWebSocketURL: voiceWebSocketURL,
            deviceID: deviceID,
            chatTargetDeviceID: chatTargetDeviceID,
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
