import SwiftUI

@main
struct XiaomaoApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
                .task { coordinator.start() }
                .onOpenURL { url in
                    handleCallURL(url)
                }
        }
    }

    // MARK: Live Activity App Intent → URL scheme 处理
    private func handleCallURL(_ url: URL) {
        guard url.scheme == "xiaomao" else { return }
        switch url.path {
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
    static let toggleMuteFromActivity = Notification.Name("xiaomao.toggleMute")
    static let hangupFromActivity = Notification.Name("xiaomao.hangup")
}

private struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var activeCall = false
#if DEBUG
    @State private var showingDiagnostics = false
#endif

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
                    completed: {}
                )
            case .binding:
                DeviceBindingView(
                    deviceID: coordinator.environment.deviceID,
                    configurationReady: coordinator.environment.isRuntimeConfigurationReady,
                    configurationMessage: coordinator.environment.runtimeConfigurationMessage,
                    tokenStore: coordinator.tokenStore,
                    completed: { coordinator.screen = coordinator.hasAgreedPrivacy ? .main : .privacy }
                )
            case .privacy:
                PrivacyView(
                    agreed: { coordinator.agreePrivacy() },
                    declined: { coordinator.declinePrivacy() }
                )
            case .main:
                MainTabView(
                    environment: coordinator.environment,
                    tokenStore: coordinator.tokenStore,
                    startCall: { requestCall() }
                )
                .fullScreenCover(isPresented: $activeCall) {
                    VoiceCallView(
                        viewModel: VoiceCallViewModel(controller: coordinator.voiceController),
                        close: { activeCall = false }
                    )
                }
            }
#if DEBUG
            VStack {
                HStack {
                    Spacer()
                    Button {
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
        .preferredColorScheme(.light)
#if DEBUG
        .sheet(isPresented: $showingDiagnostics) {
            DeveloperDiagnosticsView(snapshot: diagnosticsSnapshot)
        }
#endif
    }

#if DEBUG
    private var diagnosticsSnapshot: DeveloperDiagnosticsSnapshot {
        let credentials = coordinator.tokenStore.load().map {
            CredentialState.valid(AuthCredentials(accessToken: $0, refreshToken: nil))
        } ?? .noCredentials
        let device: DeviceBindingState = coordinator.environment.deviceID.isEmpty
            ? .unbound : .bound(deviceID: coordinator.environment.deviceID)
        let route = AppCoordinator.launchRoute(
            environmentReady: coordinator.environment.isRuntimeConfigurationReady,
            mockMode: coordinator.environment.enableMockVoice,
            credentialState: credentials,
            bindingState: device
        )
        return .make(
            environment: coordinator.environment,
            hasCredentials: credentials.allowsHome,
            hasBoundDevice: device.allowsHome,
            launchRoute: route
        )
    }
#endif

    // MARK: P2.8A 单次启动门禁 (同一时间只允许一次通话页面展示请求)
    // 连续点击/URL scheme 重复触发不会重复创建 VoiceCallView;
    // 不使用人工延迟, 点击后立即置 activeCall.
    private func requestCall() {
        guard !activeCall else { return }
        activeCall = true
    }
}
