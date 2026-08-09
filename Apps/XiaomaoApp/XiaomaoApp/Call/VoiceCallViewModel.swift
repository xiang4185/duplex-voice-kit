import Combine
import Foundation

@MainActor
final class VoiceCallViewModel: ObservableObject {
    let controller: VoiceSessionController
    let companionStore: CompanionModeStore
    private var controllerUpdates: AnyCancellable?
    private var companionUpdates: AnyCancellable?
    // P2.8A: 启动幂等标记 — 同一页面生命周期内 appear() 最多执行一次 startNewCall,
    // 防止 SwiftUI .task 重算重复建立 Session. 不放入全局单例.
    private var hasAppeared = false
    @Published private(set) var isSwitchingCompanion = false
    @Published private(set) var companionSwitchError = ""

    init(controller: VoiceSessionController, companionStore: CompanionModeStore) {
        self.controller = controller
        self.companionStore = companionStore
        controller.setCompanionTypeID(companionStore.current.rawValue)
        controllerUpdates = controller.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        companionUpdates = companionStore.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    convenience init(controller: VoiceSessionController) {
        self.init(controller: controller, companionStore: CompanionModeStore())
    }

    var canMute: Bool { controller.canMute }
    var canInterrupt: Bool { controller.canInterrupt }
    var showReconnect: Bool { controller.shouldShowReconnect }

    // P2.8A: appear() 幂等 — 页面生命周期内只建立一次 Session
    func appear() async {
        guard !hasAppeared else { return }
        hasAppeared = true
        guard !controller.callIsActive else { return }
        await controller.startNewCall()
    }
    func disappear() { Task { await controller.endCurrentCall() } }
    func interrupt() { Task { await controller.interrupt() } }
    func toggleMute() { Task { await controller.setMuted(!controller.isMuted) } }
    func reconnect() { controller.reconnectCurrentCall() }
    func enterBackground() { Task { await controller.appDidEnterBackground() } }
    func enterForeground() { Task { await controller.appWillEnterForeground() } }

    func switchCompanion(to type: CompanionType) async {
        guard !isSwitchingCompanion else { return }
        guard companionStore.current != type else { return }

        isSwitchingCompanion = true
        companionSwitchError = ""

        if controller.canInterrupt {
            await controller.interrupt()
        }
        await controller.endCurrentCall()
        companionStore.select(type)
        controller.setCompanionTypeID(type.rawValue)
        await controller.startNewCall()

        if controller.state == .failed {
            companionSwitchError = "陪伴切换未完成，请重试。"
        }
        isSwitchingCompanion = false
    }
}
