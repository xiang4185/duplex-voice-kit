import Combine
import Foundation

@MainActor
final class VoiceCallViewModel: ObservableObject {
    let controller: VoiceSessionController
    private var controllerUpdates: AnyCancellable?
    // P2.8A: 启动幂等标记 — 同一页面生命周期内 appear() 最多执行一次 startNewCall,
    // 防止 SwiftUI .task 重算重复建立 Session. 不放入全局单例.
    private var hasAppeared = false

    init(controller: VoiceSessionController) {
        self.controller = controller
        controllerUpdates = controller.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    var canMute: Bool { controller.canMute }
    var canInterrupt: Bool { controller.canInterrupt }
    var showReconnect: Bool { controller.shouldShowReconnect }

    // P2.8A: appear() 幂等 — 页面生命周期内只建立一次 Session
    func appear() async {
        guard !hasAppeared else { return }
        hasAppeared = true
        await controller.startNewCall()
    }
    func disappear() { Task { await controller.endCurrentCall() } }
    func interrupt() { Task { await controller.interrupt() } }
    func toggleMute() { Task { await controller.setMuted(!controller.isMuted) } }
    func reconnect() { controller.reconnectCurrentCall() }
    func enterBackground() { Task { await controller.appDidEnterBackground() } }
    func enterForeground() { Task { await controller.appWillEnterForeground() } }
}
