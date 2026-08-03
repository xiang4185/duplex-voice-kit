import SwiftUI
import DuplexVoiceKitCompanion
import DuplexVoiceKitUI

@main
@MainActor
struct DVKCompanionShowcaseApp: App {
    private let configuration: DVKRuntimeConfiguration
    private let tokenStore: any DVKTokenStoring
    private let store: DVKCompanionStore

    init() {
        let configuration = DVKRuntimeConfiguration.fromInfoDictionary(Bundle.main.infoDictionary ?? [:])
        #if os(iOS)
        let tokenStore: any DVKTokenStoring = DVKKeychainTokenStore()
        #else
        let tokenStore: any DVKTokenStoring = DVKMemoryTokenStore()
        #endif
        let chat: any DVKChatServicing
        if configuration.isLive, let baseURL = configuration.apiBaseURL {
            chat = DVKChatService(
                baseURL: baseURL,
                tokenStore: tokenStore,
                deviceID: configuration.deviceID
            )
        } else {
            chat = DVKMockChatService()
        }
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.store = DVKCompanionStore(chat: chat)
    }

    var body: some Scene {
        WindowGroup {
            DVKCompanionStartupView(
                store: store,
                runtimeConfiguration: configuration,
                tokenStore: tokenStore
            )
        }
    }
}
