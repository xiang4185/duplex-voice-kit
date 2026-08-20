import SwiftUI

// MARK: - 主 Tab 框架 (MainTabView)
// 4 Tab — 陪伴 / 聊天 / 小事 / 我的
// 主色西柚玫瑰 #D9486B, 原生 TabView + 西柚玫瑰 tint

struct MainTabView: View {
    let environment: AppEnvironment
    let startCall: () -> Void
    let characterNamespace: Namespace.ID
    let onReconfigure: () -> Void
    @ObservedObject private var voiceController: VoiceSessionController

    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var chatAvatarStore: ChatAvatarStore
    @ObservedObject private var smallThingsStore: SmallThingsStore
    @State private var selectedTab: Tab = .companion
    @State private var characterRelayVisible = false
    @State private var characterRelayArrived = false
    @State private var reducedTabFade = false
    @State private var characterRelayTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        characterNamespace: Namespace.ID,
        voiceController: VoiceSessionController,
        chatService: any ChatServicing,
        smallThingsStore: SmallThingsStore,
        onReconfigure: @escaping () -> Void = {}
    ) {
        self.environment = environment
        self.startCall = startCall
        self.characterNamespace = characterNamespace
        self.onReconfigure = onReconfigure
        _voiceController = ObservedObject(wrappedValue: voiceController)
        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(service: chatService)
        )
        let localParticipant: ChatParticipant = environment.chatTargetDeviceID == nil ? .user : .developer
        _chatAvatarStore = StateObject(
            wrappedValue: ChatAvatarStore(
                service: ChatAvatarService(
                    backend: environment.hostAdapters.backend,
                    targetDeviceID: environment.chatTargetDeviceID
                ),
                localParticipant: localParticipant
            )
        )
        _smallThingsStore = ObservedObject(wrappedValue: smallThingsStore)
    }

    var body: some View {
        let tokens = Theme.visual(visualMode)
        TabView(selection: tabSelection) {
            CompanionHomeView(
                startCall: startCall,
                openSettings: { selectedTab = .settings },
                voiceController: voiceController,
                characterNamespace: characterNamespace
            )
            .modifier(V2TabSceneMotion(isActive: selectedTab == .companion))
            .tabItem {
                Label(Tab.companion.title, systemImage: Tab.companion.icon)
                    .symbolEffect(
                        .bounce,
                        value: !reduceMotion && selectedTab == .companion
                    )
                    .accessibilityIdentifier("main.tab.companion")
            }
            .tag(Tab.companion)

            ChatView(
                viewModel: chatViewModel,
                isMockMode: environment.hostAdapters.mode == .mock,
                localParticipant: environment.chatTargetDeviceID == nil ? .user : .developer,
                avatarStore: chatAvatarStore,
                onReconfigure: onReconfigure
            )
                .modifier(V2TabSceneMotion(isActive: selectedTab == .chat))
                .tabItem {
                    Label(Tab.chat.title, systemImage: Tab.chat.icon)
                        .symbolEffect(
                            .bounce,
                            value: !reduceMotion && selectedTab == .chat
                        )
                        .accessibilityIdentifier("main.tab.chat")
                }
                .tag(Tab.chat)

            SmallThingsRootView(store: smallThingsStore)
                .modifier(V2TabSceneMotion(isActive: selectedTab == .smallThings))
                .tabItem {
                    Label(Tab.smallThings.title, systemImage: Tab.smallThings.icon)
                        .symbolEffect(
                            .bounce,
                            value: !reduceMotion && selectedTab == .smallThings
                        )
                        .accessibilityIdentifier("main.tab.smallThings")
                }
                .tag(Tab.smallThings)
                .accessibilityIdentifier("smallThings.tab")

            SettingsView(
                store: SettingsStore(environment: environment),
                avatarStore: chatAvatarStore,
                close: {}
            )
                .modifier(V2TabSceneMotion(isActive: selectedTab == .settings))
                .tabItem {
                    Label(Tab.settings.title, systemImage: Tab.settings.icon)
                        .symbolEffect(
                            .bounce,
                            value: !reduceMotion && selectedTab == .settings
                        )
                        .accessibilityIdentifier("main.tab.settings")
                }
                .tag(Tab.settings)
        }
        .tint(tokens.primary)
        .opacity(reducedTabFade ? 0 : 1)
        .toolbarColorScheme(visualMode == .mystery ? .dark : .light, for: .tabBar)
        .accessibilityIdentifier("main.tabs")
        .overlay { characterRelayOverlay }
        .safeAreaInset(edge: .top, spacing: 0) {
            if voiceController.callIsActive {
                currentCallBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84),
            value: voiceController.callIsActive
        )
        .onAppear {
            WarmHaptics.prepareAction()
        }
        .onDisappear {
            characterRelayTask?.cancel()
        }
    }

    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                guard newTab != selectedTab else { return }
                WarmHaptics.action()
                characterRelayTask?.cancel()

                if selectedTab == .companion, newTab == .chat, !reduceMotion {
                    beginCharacterRelay(to: newTab)
                } else if reduceMotion {
                    characterRelayVisible = false
                    selectWithReducedMotion(newTab)
                } else {
                    characterRelayVisible = false
                    withAnimation(.easeInOut(duration: 0.28)) {
                        selectedTab = newTab
                    }
                }
            }
        )
    }

    private func beginCharacterRelay(to newTab: Tab) {
        var setup = Transaction()
        setup.disablesAnimations = true
        withTransaction(setup) {
            characterRelayArrived = false
            characterRelayVisible = true
            selectedTab = newTab
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.46)) {
                characterRelayArrived = true
            }
        }

        characterRelayTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            characterRelayVisible = false
            characterRelayArrived = false
        }
    }

    private func selectWithReducedMotion(_ newTab: Tab) {
        withAnimation(.linear(duration: 0.08)) {
            reducedTabFade = true
        }

        characterRelayTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            selectedTab = newTab
            withAnimation(.easeOut(duration: 0.14)) {
                reducedTabFade = false
            }
        }
    }

    @ViewBuilder
    private var characterRelayOverlay: some View {
        if characterRelayVisible, !reduceMotion {
            GeometryReader { proxy in
                let start = CGPoint(
                    x: proxy.size.width * 0.5,
                    y: proxy.size.height * 0.41
                )
                let destination = CGPoint(
                    x: proxy.size.width - 58,
                    y: max(24, proxy.safeAreaInsets.top + 22)
                )

                PrivacyAvatar(
                    size: 168,
                    tappable: false,
                    variant: .xiaomao,
                    style: .portrait
                )
                .scaleEffect(characterRelayArrived ? 0.18 : 1)
                .position(characterRelayArrived ? destination : start)
                .opacity(characterRelayArrived ? 0 : 1)
                .shadow(color: Theme.visual(visualMode).shadow, radius: 18, y: 8)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var currentCallBar: some View {
        let tokens = Theme.visual(visualMode)
        return Button(action: startCall) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(tokens.primary)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: voiceController.callIsActive && !reduceMotion
                    )
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

private struct V2TabSceneMotion: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || isActive ? 1 : 0.94)
            .scaleEffect(reduceMotion || isActive ? 1 : 0.985, anchor: .bottom)
            .offset(y: reduceMotion || isActive ? 0 : 8)
            .animation(
                reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
                value: isActive
            )
    }
}

// MARK: - 预览
private struct MainTabPreview: View {
    @Namespace private var characterNamespace

    var body: some View {
    MainTabView(
        environment: .fromBundle(),
        startCall: {},
        characterNamespace: characterNamespace,
        voiceController: AppCoordinator().voiceController,
        chatService: MockChatService(),
        smallThingsStore: SmallThingsStore()
    )
    .environmentObject(CompanionModeStore())
    }
}

#Preview {
    MainTabPreview()
}
