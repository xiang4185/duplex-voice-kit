import SwiftUI

// MARK: - 主 Tab 框架 (MainTabView)
// 4 Tab — 陪伴 / 聊天 / 小事 / 我的
// 主色西柚玫瑰 #D9486B, 原生 TabView + 西柚玫瑰 tint

struct MainTabView: View {
    let environment: AppEnvironment
    let tokenStore: AuthTokenStoring
    let startCall: () -> Void

    @StateObject private var chatViewModel: ChatViewModel
    @State private var selectedTab: Tab = .companion

    enum Tab: Hashable {
        case companion, chat, smallThings, settings

        var title: String {
            switch self {
            case .companion: return "陪伴"
            case .chat: return "聊天"
            case .smallThings: return "小事"
            case .settings: return "我的"
            }
        }

        var icon: String {
            switch self {
            case .companion: return "mic.fill"
            case .chat: return "message.fill"
            case .smallThings: return "heart.text.square.fill"
            case .settings: return "person.crop.circle"
            }
        }
    }

    init(
        environment: AppEnvironment,
        tokenStore: AuthTokenStoring,
        startCall: @escaping () -> Void
    ) {
        self.init(
            environment: environment,
            tokenStore: tokenStore,
            startCall: startCall,
            chatService: Self.publicDefaultChatService()
        )
    }

    init(
        environment: AppEnvironment,
        tokenStore: AuthTokenStoring,
        startCall: @escaping () -> Void,
        chatService: any ChatServicing
    ) {
        self.environment = environment
        self.tokenStore = tokenStore
        self.startCall = startCall
        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(service: chatService)
        )
    }

    static func publicDefaultChatService() -> any ChatServicing {
        MockChatService()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CompanionHomeView(
                startCall: startCall,
                openHistory: { selectedTab = .smallThings },
                openSettings: { selectedTab = .settings }
            )
            .tabItem { Label(Tab.companion.title, systemImage: Tab.companion.icon) }
            .tag(Tab.companion)

            ChatView(viewModel: chatViewModel)
                .tabItem {
                    Label(Tab.chat.title, systemImage: Tab.chat.icon)
                        .accessibilityIdentifier("main.tab.chat")
                }
                .tag(Tab.chat)

            SmallThingsRootView()
                .tabItem { Label(Tab.smallThings.title, systemImage: Tab.smallThings.icon) }
                .tag(Tab.smallThings)
                .accessibilityIdentifier("smallThings.tab")

            SettingsView(store: SettingsStore(environment: environment), close: {})
                .tabItem { Label(Tab.settings.title, systemImage: Tab.settings.icon) }
                .tag(Tab.settings)
        }
        .tint(Theme.primary)
        .accessibilityIdentifier("main.tabs")
    }
}

// MARK: - 预览
#Preview {
    MainTabView(
        environment: .fromBundle(),
        tokenStore: MemoryAuthTokenStore(),
        startCall: {}
    )
}
