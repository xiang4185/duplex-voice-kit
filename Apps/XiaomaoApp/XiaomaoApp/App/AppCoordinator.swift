import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    enum Screen: Equatable { case launch, configurationError, binding, privacy, main }
    enum LaunchRoute: Equatable { case configurationError, binding, home }

    @Published var screen: Screen = .launch
    @Published private(set) var credentialState: CredentialState = .noCredentials
    @Published private(set) var deviceBindingState: DeviceBindingState = .unbound

    let environment: AppEnvironment
    let hostAdapters: HostAdapterDependencies
    let tokenStore: any AuthTokenStoring
    let chatService: any ChatServicing
    let smallThingsStore: SmallThingsStore
    let voiceController: VoiceSessionController
    let companionStore: CompanionModeStore

    init(
        environment suppliedEnvironment: AppEnvironment? = nil,
        tokenStore suppliedTokenStore: (any AuthTokenStoring)? = nil,
        companionStore suppliedCompanionStore: CompanionModeStore? = nil,
        backendSession: URLSession = .shared,
        voiceClient: (any VoiceWebSocketClient)? = nil
    ) {
        let companionStore = suppliedCompanionStore ?? CompanionModeStore()
        self.companionStore = companionStore
        let baseEnvironment = suppliedEnvironment ?? .fromBundle()
        let tokenStore = suppliedTokenStore ?? Self.makeTokenStore(
            for: baseEnvironment.requestedHostAdapterMode
        )
        self.tokenStore = tokenStore

        if baseEnvironment.requestedHostAdapterMode == .mock {
            try? tokenStore.save("mock")
        }

        let dependencies: HostAdapterDependencies
        if suppliedEnvironment != nil {
            dependencies = baseEnvironment.hostAdapters
        } else {
            dependencies = HostAdapterFactory.make(
                mode: baseEnvironment.requestedHostAdapterMode,
                apiBaseURL: baseEnvironment.apiBaseURL,
                voiceWebSocketURL: baseEnvironment.voiceWebSocketURL,
                tokenStore: tokenStore,
                deviceID: baseEnvironment.deviceID,
                backendSession: backendSession,
                voiceClient: voiceClient
            )
        }

        let environment = baseEnvironment.replacingHostAdapters(dependencies)
        self.environment = environment
        self.hostAdapters = dependencies
        if dependencies.mode == .mock {
            self.chatService = MockChatService()
            self.smallThingsStore = SmallThingsStore()
        } else if dependencies.mode == .production {
            self.chatService = ChatService(backend: dependencies.backend)
            self.smallThingsStore = SmallThingsStore(
                service: ProductionSmallThingsService(backend: dependencies.backend)
            )
        } else {
            self.chatService = ChatService(backend: dependencies.backend)
            self.smallThingsStore = SmallThingsStore(entries: [])
        }

        let capture: AudioCapturing
        let playback: AudioPlaying
        if dependencies.mode == .mock {
            capture = MockAudioCapture()
            playback = MockAudioPlayback()
        } else {
            let realtimeAudio = RealtimeAudioIOEngine()
            capture = realtimeAudio
            playback = realtimeAudio
        }
        let audioSession: AudioSessionControlling = dependencies.mode == .mock
            ? MockAudioSessionController() : AudioSessionController()
        let networkMonitor: NetworkMonitoring = dependencies.mode == .mock
            ? MockNetworkMonitor() : NetworkMonitor()
        self.voiceController = VoiceSessionController(
            environment: environment,
            socket: dependencies.voice,
            capture: capture,
            playback: playback,
            audioSession: audioSession,
            networkMonitor: networkMonitor,
            voiceActivityConfiguration: .xiaomaoRealtime
        )
        self.voiceController.setCompanionTypeID(companionStore.current.rawValue)
    }

    private static func makeTokenStore(for mode: HostAdapterMode) -> any AuthTokenStoring {
        if mode == .production {
            return KeychainAuthTokenStore()
        }
        return MemoryAuthTokenStore()
    }

    // MARK: 隐私授权持久化
    private var privacyKey: String { "privacy.agreed.v3" }
    var hasAgreedPrivacy: Bool { UserDefaults.standard.bool(forKey: privacyKey) }

    func agreePrivacy() {
        UserDefaults.standard.set(true, forKey: privacyKey)
        screen = .main
    }

    func declinePrivacy() {
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

    func start() async {
        do {
            if let credentials = try await hostAdapters.credentials.obtainCredentials(),
               credentials.hasAccessToken {
                credentialState = .valid(credentials)
            } else {
                credentialState = .noCredentials
            }
        } catch {
            credentialState = .noCredentials
        }
        deviceBindingState = await hostAdapters.deviceBinding.currentState()

        switch Self.launchRoute(
            environmentReady: environment.isRuntimeConfigurationReady,
            mockMode: hostAdapters.mode == .mock,
            credentialState: credentialState,
            bindingState: deviceBindingState
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
