import SwiftUI

// MARK: - 主 Tab 框架 (MainTabView)
// 4 Tab — 陪伴 / 聊天 / 小事 / 我的
// 主色西柚玫瑰 #D9486B, 原生 TabView + 西柚玫瑰 tint

struct MainTabView: View {
    let environment: AppEnvironment
    let startCall: () -> Void
    let onReconfigure: () -> Void
    @ObservedObject private var voiceController: VoiceSessionController

    @StateObject private var chatViewModel: ChatViewModel
    @ObservedObject private var smallThingsStore: SmallThingsStore
    @State private var selectedTab: Tab = .companion
    @Environment(\.appVisualMode) private var visualMode

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
        startCall: @escaping () -> Void,
        voiceController: VoiceSessionController,
        chatService: any ChatServicing,
        smallThingsStore: SmallThingsStore,
        onReconfigure: @escaping () -> Void = {}
    ) {
        self.environment = environment
        self.startCall = startCall
        self.onReconfigure = onReconfigure
        _voiceController = ObservedObject(wrappedValue: voiceController)
        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(service: chatService)
        )
        _smallThingsStore = ObservedObject(wrappedValue: smallThingsStore)
    }

    var body: some View {
        let tokens = Theme.visual(visualMode)
        TabView(selection: tabSelection) {
            CompanionHomeView(
                startCall: startCall,
                openSettings: { selectedTab = .settings }
            )
            .tabItem {
                Label(Tab.companion.title, systemImage: Tab.companion.icon)
                    .accessibilityIdentifier("main.tab.companion")
            }
            .tag(Tab.companion)

            ChatView(
                viewModel: chatViewModel,
                isMockMode: environment.hostAdapters.mode == .mock,
                localParticipant: environment.chatTargetDeviceID == nil ? .user : .developer,
                onReconfigure: onReconfigure
            )
                .tabItem {
                    Label(Tab.chat.title, systemImage: Tab.chat.icon)
                        .accessibilityIdentifier("main.tab.chat")
                }
                .tag(Tab.chat)

            SmallThingsRootView(store: smallThingsStore)
                .tabItem {
                    Label(Tab.smallThings.title, systemImage: Tab.smallThings.icon)
                        .accessibilityIdentifier("main.tab.smallThings")
                }
                .tag(Tab.smallThings)
                .accessibilityIdentifier("smallThings.tab")

            SettingsView(store: SettingsStore(environment: environment), close: {})
                .tabItem {
                    Label(Tab.settings.title, systemImage: Tab.settings.icon)
                        .accessibilityIdentifier("main.tab.settings")
                }
                .tag(Tab.settings)
        }
        .tint(tokens.primary)
        .toolbarColorScheme(visualMode == .mystery ? .dark : .light, for: .tabBar)
        .accessibilityIdentifier("main.tabs")
        .safeAreaInset(edge: .top, spacing: 0) {
            if voiceController.callIsActive {
                currentCallBar
            }
        }
        .onAppear {
            WarmHaptics.prepareAction()
        }
    }

    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                guard newTab != selectedTab else { return }
                WarmHaptics.action()
                selectedTab = newTab
            }
        )
    }

    private var currentCallBar: some View {
        let tokens = Theme.visual(visualMode)
        return Button(action: startCall) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(tokens.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前通话仍在继续")
                        .font(Theme.subheadFont.weight(.semibold))
                        .foregroundStyle(tokens.textPrimary)
                    Text(voiceController.state == .speaking ? "小猫正在说话" : "点此返回通话")
                        .font(Theme.captionFont)
                        .foregroundStyle(tokens.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .foregroundStyle(tokens.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, 10)
            .background(tokens.glassTint)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Divider().overlay(tokens.border.opacity(0.5)) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("call.resume.bar")
    }
}

// MARK: - 预览
#Preview {
    MainTabView(
        environment: .fromBundle(),
        startCall: {},
        voiceController: AppCoordinator().voiceController,
        chatService: MockChatService(),
        smallThingsStore: SmallThingsStore()
    )
    .environmentObject(CompanionModeStore())
}
