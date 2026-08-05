import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    enum Screen { case launch, configurationError, binding, privacy, main }
    enum LaunchRoute: Equatable { case configurationError, binding, home }
    @Published var screen: Screen = .launch
    let environment: AppEnvironment
    let tokenStore: AuthTokenStoring
    let voiceController: VoiceSessionController

    init(environment: AppEnvironment = .fromBundle()) {
        self.environment = environment
        let tokenStore: AuthTokenStoring = environment.enableMockVoice
            ? MemoryAuthTokenStore() : KeychainAuthTokenStore()
        self.tokenStore = tokenStore
        if environment.enableMockVoice { try? tokenStore.save("synthetic-development-token") }
        let socket: VoiceWebSocketClient = environment.enableMockVoice
            ? MockWebSocketClient() : URLSessionVoiceWebSocketClient()
        let capture: AudioCapturing
        let playback: AudioPlaying
        if environment.enableMockVoice {
            capture = MockAudioCapture()
            playback = MockAudioPlayback()
        } else {
            let realtimeAudio = RealtimeAudioIOEngine()
            capture = realtimeAudio
            playback = realtimeAudio
        }
        let audioSession: AudioSessionControlling = environment.enableMockVoice
            ? MockAudioSessionController() : AudioSessionController()
        let networkMonitor: NetworkMonitoring = environment.enableMockVoice
            ? MockNetworkMonitor() : NetworkMonitor()
        self.voiceController = VoiceSessionController(
            environment: environment,
            tokenStore: tokenStore,
            socket: socket,
            capture: capture,
            playback: playback,
            audioSession: audioSession,
            networkMonitor: networkMonitor
        )
    }

    // MARK: 隐私授权持久化
    private var privacyKey: String { "privacy.agreed.v3" }
    var hasAgreedPrivacy: Bool { UserDefaults.standard.bool(forKey: privacyKey) }

    func agreePrivacy() {
        UserDefaults.standard.set(true, forKey: privacyKey)
        screen = .main
    }

    func declinePrivacy() {
        // 暂不同意: 仍可进入应用, 设置页可随时重新开启
        UserDefaults.standard.set(false, forKey: privacyKey)
        screen = .main
    }

    nonisolated static func launchRoute(
        environmentReady: Bool,
        mockMode: Bool,
        credentialState: CredentialState,
        bindingState: DeviceBindingState
    ) -> LaunchRoute {
        if mockMode { return .home }
        guard environmentReady else { return .configurationError }
        guard credentialState.allowsHome, bindingState.allowsHome else { return .binding }
        return .home
    }

    func start() {
        let credentials = tokenStore.load().map {
            CredentialState.valid(AuthCredentials(accessToken: $0, refreshToken: nil))
        } ?? .noCredentials
        let bindingState: DeviceBindingState = environment.deviceID.isEmpty
            ? .unbound : .bound(deviceID: environment.deviceID)

        switch Self.launchRoute(
            environmentReady: environment.isRuntimeConfigurationReady,
            mockMode: environment.enableMockVoice,
            credentialState: credentials,
            bindingState: bindingState
        ) {
        case .configurationError:
            screen = .configurationError
        case .binding:
            screen = .binding
        case .home where !hasAgreedPrivacy:
            screen = .privacy
        case .home:
            screen = .main
        }
    }
}
