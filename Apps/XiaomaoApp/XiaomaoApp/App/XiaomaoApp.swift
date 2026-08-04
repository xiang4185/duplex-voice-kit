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

    var body: some View {
        ZStack {
            switch coordinator.screen {
            case .launch:
                ProgressView("正在启动…")
                    .tint(Theme.primary)
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
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.screen)
        .preferredColorScheme(.light)
    }

    // MARK: P2.8A 单次启动门禁 (同一时间只允许一次通话页面展示请求)
    // 连续点击/URL scheme 重复触发不会重复创建 VoiceCallView;
    // 不使用人工延迟, 点击后立即置 activeCall.
    private func requestCall() {
        guard !activeCall else { return }
        activeCall = true
    }
}
