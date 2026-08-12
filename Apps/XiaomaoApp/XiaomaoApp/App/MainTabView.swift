import SwiftUI
import UIKit

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
    @State private var keyboardVisible = false
    @Namespace private var tabSelectionAnimation
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
        TabView(selection: $selectedTab) {
            CompanionHomeView(
                startCall: startCall,
                openSettings: { selectedTab = .settings }
            )
            .tabItem { Label(Tab.companion.title, systemImage: Tab.companion.icon) }
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
                .tabItem { Label(Tab.smallThings.title, systemImage: Tab.smallThings.icon) }
                .tag(Tab.smallThings)
                .accessibilityIdentifier("smallThings.tab")

            SettingsView(store: SettingsStore(environment: environment), close: {})
                .tabItem { Label(Tab.settings.title, systemImage: Tab.settings.icon) }
                .tag(Tab.settings)
        }
        .tint(tokens.primary)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(visualMode == .mystery ? .dark : .light, for: .tabBar)
        .accessibilityIdentifier("main.tabs")
        .safeAreaInset(edge: .top, spacing: 0) {
            if voiceController.callIsActive {
                currentCallBar
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                v2TabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .animation(.easeOut(duration: Theme.Motion.quick), value: keyboardVisible)
    }

    private var v2TabBar: some View {
        HStack(spacing: 5) {
            v2TabButton(.companion, identifier: "main.tab.companion")
            v2TabButton(.chat, identifier: "main.tab.chat")
            v2TabButton(.smallThings, identifier: "main.tab.smallThings")
            v2TabButton(.settings, identifier: "main.tab.settings")
        }
        .padding(6)
        .frame(height: 64)
        .background(Theme.v2InkSurface.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .accessibilityIdentifier("main.v2TabBar")
    }

    private func v2TabButton(_ tab: Tab, identifier: String) -> some View {
        let selected = selectedTab == tab
        return Button {
            WarmHaptics.action()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .semibold))
                if selected {
                    Text(tab.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.58))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if selected {
                    Capsule()
                        .fill(Theme.v2Coral)
                        .matchedGeometryEffect(id: "v2.tab.selection", in: tabSelectionAnimation)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
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
