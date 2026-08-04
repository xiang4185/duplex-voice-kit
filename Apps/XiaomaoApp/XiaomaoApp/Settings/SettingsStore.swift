import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var useSpeaker = true
    @Published var enableMemory = true
    @Published var defaultRoute: VoiceRoute = .a
    @Published var mockVoice = false

    init(environment: AppEnvironment) {
        enableMemory = environment.enableMemory
        defaultRoute = environment.defaultVoiceRoute
        mockVoice = environment.enableMockVoice
    }
}
