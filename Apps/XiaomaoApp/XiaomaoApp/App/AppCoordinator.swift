import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    enum Screen { case launch, binding, privacy, main }
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

    func start() {
        guard environment.isRuntimeConfigurationReady else {
            screen = .binding
            return
        }
        if tokenStore.load() == nil {
            screen = .binding
        } else if !hasAgreedPrivacy {
            screen = .privacy
        } else {
            screen = .main
        }
    }
}
