import Combine
import SwiftUI

@main
struct XiaomaoApp: App {
    var body: some Scene {
        WindowGroup {
            KeyboardViewportContainer {
                AppBootstrapView()
            }
            // UIViewControllerRepresentable otherwise inherits the SwiftUI
            // container safe-area frame, exposing the UIKit root background
            // above the status bar and below the home indicator. Let the native
            // controller own the full screen; its hosted SwiftUI hierarchy still
            // receives the real window safe-area insets for navigation and tabs.
            .ignoresSafeArea(.container, edges: .all)
            // The UIKit keyboardLayoutGuide above is the sole viewport driver.
            // Prevent the outer SwiftUI window from applying a second inset.
            .ignoresSafeArea(.keyboard)
        }
    }

    // MARK: Live Activity App Intent → URL scheme 处理
    private func handleCallURL(_ url: URL) {
        guard url.scheme == "xiaomao" else { return }
        switch url.path {
        case "/call/open":
            NotificationCenter.default.post(name: .openCallFromActivity, object: nil)
        case "/call/mute":
            NotificationCenter.default.post(name: .toggleMuteFromActivity, object: nil)
        case "/call/hangup":
            NotificationCenter.default.post(name: .hangupFromActivity, object: nil)
        default:
            break
        }
    }
}

private struct AppBootstrapView: View {
    @State private var generation = UUID()

    var body: some View {
        RootContainer(reload: { generation = UUID() })
            .id(generation)
    }
}

private struct RootContainer: View {
    @StateObject private var coordinator = AppCoordinator()
    let reload: () -> Void

    var body: some View {
        RootView(coordinator: coordinator, reload: reload)
            .task { await coordinator.start() }
            .onOpenURL { url in
                handleCallURL(url)
            }
    }

    private func handleCallURL(_ url: URL) {
        guard url.scheme == "xiaomao" else { return }
        switch url.path {
        case "/call/open":
            NotificationCenter.default.post(name: .openCallFromActivity, object: nil)
        case "/call/mute":
            NotificationCenter.default.post(name: .toggleMuteFromActivity, object: nil)
        case "/call/hangup":
            NotificationCenter.default.post(name: .hangupFromActivity, object: nil)
        default:
            break
        }
    }
}

// MARK: - Live Activity 控制通知
extension Notification.Name {
    static let openCallFromActivity = Notification.Name("xiaomao.openCall")
    static let toggleMuteFromActivity = Notification.Name("xiaomao.toggleMute")
    static let hangupFromActivity = Notification.Name("xiaomao.hangup")
    static let reconfigureConnection = Notification.Name("xiaomao.reconfigureConnection")
    static let credentialsExpired = Notification.Name("xiaomao.credentialsExpired")
}

private struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var companionStore: CompanionModeStore
    let reload: () -> Void
    @State private var activeCall = false
    @Namespace private var characterNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
#if DEBUG
    @State private var showingDiagnostics = false
#endif

    init(coordinator: AppCoordinator, reload: @escaping () -> Void) {
        self.coordinator = coordinator
        self.reload = reload
        _companionStore = ObservedObject(wrappedValue: coordinator.companionStore)
    }

    var body: some View {
        ZStack {
            switch coordinator.screen {
            case .launch:
                ProgressView("正在启动…")
                    .tint(Theme.primary)
            case .configurationError:
                DeviceBindingView(
                    deviceID: coordinator.environment.deviceID,
                    configurationReady: false,
                    configurationMessage: coordinator.environment.runtimeConfigurationMessage,
                    tokenStore: coordinator.tokenStore,
                    runtimeConfigurationStore: KeychainRuntimeConfigurationStore(),
                    completed: { rebuildAdapters() }
                )
            case .binding:
                DeviceBindingView(
                    deviceID: coordinator.environment.deviceID,
                    configurationReady: coordinator.environment.isRuntimeConfigurationReady,
                    configurationMessage: coordinator.environment.runtimeConfigurationMessage,
                    tokenStore: coordinator.tokenStore,
                    runtimeConfigurationStore: KeychainRuntimeConfigurationStore(),
                    completed: { rebuildAdapters() }
                )
            case .privacy:
                PrivacyView(
                    agreed: { coordinator.agreePrivacy() },
                    declined: { coordinator.declinePrivacy() }
                )
            case .main:
                MainTabView(
                    environment: coordinator.environment,
                    startCall: { requestCall() },
                    characterNamespace: characterNamespace,
                    voiceController: coordinator.voiceController,
                    chatService: coordinator.chatService,
                    smallThingsStore: coordinator.smallThingsStore,
                    onReconfigure: {
                        reconfigureConnection()
                    }
                )
                .fullScreenCover(isPresented: $activeCall) {
                    callPresentation
                }
            }
#if DEBUG
            VStack {
                HStack {
                    Spacer()
                    Button {
                        WarmHaptics.action()
                        showingDiagnostics = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Developer Diagnostics")
                    .padding()
                }
                Spacer()
            }
#endif
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.screen)
        .onReceive(NotificationCenter.default.publisher(for: .reconfigureConnection)) { _ in
            activeCall = false
            coordinator.screen = .binding
        }
        .onReceive(NotificationCenter.default.publisher(for: .credentialsExpired)) { _ in
            activeCall = false
            Task { @MainActor in
                await coordinator.voiceController.endCurrentCall()
                try? coordinator.tokenStore.clear()
                coordinator.screen = .binding
            }
        }
        .onReceive(coordinator.voiceController.$callIsActive.removeDuplicates()) { active in
            if active {
                CallLiveActivityManager.shared.start(
                    characterName: CompanionRoleStore.shared.productionRole.displayName,
                    controller: coordinator.voiceController
                )
            } else {
                CallLiveActivityManager.shared.end()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCallFromActivity)) { _ in
            guard coordinator.voiceController.callIsActive else { return }
            requestCall()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMuteFromActivity)) { _ in
            let controller = coordinator.voiceController
            guard controller.callIsActive, controller.canMute || controller.isMuted else { return }
            Task { @MainActor in
                await controller.setMuted(!controller.isMuted)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hangupFromActivity)) { _ in
            guard coordinator.voiceController.callIsActive else { return }
            activeCall = false
            CallLiveActivityManager.shared.end()
            Task { @MainActor in
                await coordinator.voiceController.endCurrentCall()
            }
        }
        .environmentObject(companionStore)
        .environment(\.appVisualMode, companionStore.visualMode)
        .environment(\.companionType, companionStore.current)
        .preferredColorScheme(companionStore.visualMode == .mystery ? .dark : .light)
#if DEBUG
        .sheet(isPresented: $showingDiagnostics) {
            DeveloperDiagnosticsView(snapshot: diagnosticsSnapshot)
        }
#endif
    }

#if DEBUG
    private var diagnosticsSnapshot: DeveloperDiagnosticsSnapshot {
        let route = AppCoordinator.launchRoute(
            environmentReady: coordinator.environment.isRuntimeConfigurationReady,
            mockMode: coordinator.hostAdapters.mode == .mock,
            credentialState: coordinator.credentialState,
            bindingState: coordinator.deviceBindingState
        )
        return .make(
            environment: coordinator.environment,
            hasCredentials: coordinator.credentialState.allowsHome,
            hasBoundDevice: coordinator.deviceBindingState.allowsHome,
            launchRoute: route
        )
    }
#endif

    // MARK: P2.8A 单次启动门禁 (同一时间只允许一次通话页面展示请求)
    // 连续点击/URL scheme 重复触发不会重复创建 VoiceCallView;
    // 不使用人工延迟, 点击后立即置 activeCall.
    private func requestCall() {
        guard !activeCall else { return }
        // 只有新通话才记录首次展示时间；从迷你条/灵动岛回到当前通话时
        // 不重置既有 Session 的连接耗时诊断。
        if !coordinator.voiceController.callIsActive {
            coordinator.voiceController.markPresentationRequested()
        }
        activeCall = true
    }

    @ViewBuilder
    private var callPresentation: some View {
        if reduceMotion {
            voiceCallView
        } else {
            voiceCallView
                .navigationTransition(
                    .zoom(sourceID: CharacterTransitionID.call, in: characterNamespace)
                )
        }
    }

    private var voiceCallView: some View {
        VoiceCallView(
            viewModel: VoiceCallViewModel(
                controller: coordinator.voiceController,
                companionStore: companionStore
            ),
            close: { activeCall = false }
        )
    }

    private func reconfigureConnection() {
        activeCall = false
        Task { @MainActor in
            await coordinator.voiceController.endCurrentCall()
            coordinator.screen = .binding
        }
    }

    private func rebuildAdapters() {
        Task { @MainActor in
            await coordinator.voiceController.endCurrentCall()
            reload()
        }
    }
}
