import ActivityKit
import Combine
import Foundation
import XiaomaoShared

// MARK: - 通话 Live Activity 管理器 (CallLiveActivityManager)
// P2.6A: Live Activity 准确反映通话状态。
// 设计原则:
//   - 计时器只更新 elapsedSeconds, 绝不覆盖 isMuted/isSpeaking 真实状态
//   - 静音/说话状态由 VoiceSessionController 驱动 (controller.isMuted / controller.state)
//   - 通话开始只创建一次 Activity; 后台/前台切换不重复创建 (activity 已存在则直接复用)
//   - 挂断/失败/主动退出时结束 Activity
//   - 保留 URL Scheme 控制, 本任务不扩展 App Intent

@MainActor
final class CallLiveActivityManager {
    static let shared = CallLiveActivityManager()

    private var activity: Activity<CallLiveActivityAttributes>?
    private var timerTask: Task<Void, Never>?
    private var controller: VoiceSessionController?
    private var controllerSubscriptions = Set<AnyCancellable>()
    private var elapsedSeconds = 0

    /// 是否已有活跃 Activity (防止重复创建)
    var isActive: Bool { activity != nil }

    private init() {}

    /// 启动 Live Activity 并开始监听会话状态。
    /// - 幂等: 若已存在 Activity 则不重复创建 (前后台切换安全)。
    func start(characterName: String = "小猫", controller: VoiceSessionController) {
        self.controller = controller
        // 无论是否创建新 Activity, ���确保状态监听已挂上 (后台返回后重新订阅)
        subscribeToController()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else {
            // 已存在 → 仅推送一次最新状态, 不重复创建
            pushState()
            return
        }

        let initialState = CallLiveActivityAttributes.ContentState(
            isMuted: controller.isMuted,
            isSpeaking: speakingState(from: controller),
            phase: phase(from: controller),
            elapsedSeconds: 0,
            progress: 0,
            sessionMinutes: 0,
            goalMinutes: 30
        )

        let attributes = CallLiveActivityAttributes(
            characterName: characterName,
            characterID: "xiaomao"
        )

        do {
            let newActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            activity = newActivity
            elapsedSeconds = 0
            startTimer()
        } catch {
            // Live Activity 启动失败 (如设备不支持/系统限制) — 静默降级, 不影响通话
            activity = nil
        }
    }

    /// 结束并移除 Live Activity (挂断/失败/主动退出)
    func end() {
        timerTask?.cancel()
        timerTask = nil
        controllerSubscriptions.removeAll()
        controller = nil
        elapsedSeconds = 0

        guard let activity else { return }

        let finalContent = ActivityContent(
            state: activity.content.state,
            staleDate: nil
        )

        Task { [weak self] in
            await activity.end(finalContent, dismissalPolicy: .immediate)
            self?.activity = nil
        }
    }

    // MARK: - 状态监听 (真实状态驱动)

    private func subscribeToController() {
        guard let controller else { return }
        // 每次 start 先清空旧订阅再重挂, 避免重复订阅
        controllerSubscriptions.removeAll()

        // 静音状态变化 → 立即推送 (灵动岛即时显示静音)
        controller.$isMuted
            .dropFirst()
            .sink { [weak self] _ in self?.pushState() }
            .store(in: &controllerSubscriptions)

        // 会话状态变化 → 说话/聆听/思考状态即时反映 (waveform 活跃度)
        controller.$state
            .dropFirst()
            .sink { [weak self] _ in self?.pushState() }
            .store(in: &controllerSubscriptions)

        // 真正结束 Session 才移除 Activity。临时 failed/reconnecting 时保留灵动岛，
        // 让用户能看到重连状态并重新进入当前通话。
        controller.$callIsActive
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] active in
                if active {
                    self?.pushState()
                } else {
                    self?.end()
                }
            }
            .store(in: &controllerSubscriptions)
    }

    // MARK: - 状态推送

    /// 用当前 controller 真实状态 + 累计时长推送一次 (计时器与状态事件共用)
    private func pushState() {
        guard let activity, let controller else { return }

        let content = ActivityContent(
            state: CallLiveActivityAttributes.ContentState(
                isMuted: controller.isMuted,
                isSpeaking: speakingState(from: controller),
                phase: phase(from: controller),
                elapsedSeconds: elapsedSeconds,
                progress: progress(for: elapsedSeconds),
                sessionMinutes: max(0, elapsedSeconds / 60),
                goalMinutes: 30
            ),
            staleDate: nil
        )

        Task {
            await activity.update(content)
        }
    }

    // MARK: - 计时器 (只更新时间, 不覆盖状态)

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.elapsedSeconds += 1
                self.pushState()
            }
        }
    }

    // MARK: - 状态映射

    /// 会话状态 → 波形活跃度 (AI 说话时活跃; 聆听/思考时保持待机)
    private func speakingState(from controller: VoiceSessionController) -> Bool {
        switch controller.state {
        case .speaking, .interrupting:
            return true
        case .listening, .endpointing, .processing, .ready, .connecting,
             .reconnecting, .degraded, .idle, .closing, .closed, .failed:
            return false
        }
    }

    private func phase(from controller: VoiceSessionController) -> CallLiveActivityPhase {
        if controller.isMuted {
            return .calling
        }
        switch controller.state {
        case .ready, .listening, .endpointing:
            return .listening
        case .processing:
            return .thinking
        case .speaking, .interrupting:
            return .speaking
        case .reconnecting, .degraded, .failed:
            return .reconnecting
        case .idle, .connecting, .closing, .closed:
            return .calling
        }
    }

    private func progress(for elapsed: Int) -> Double {
        min(Double(elapsed) / (30 * 60), 1.0)
    }
}
