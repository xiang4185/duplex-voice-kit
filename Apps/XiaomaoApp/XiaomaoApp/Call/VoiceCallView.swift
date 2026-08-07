import SwiftUI
import UIKit

// MARK: - 屏 3 陪聊主界面 / 通话中 (VoiceCallView)
// v6.1 视觉: 呼吸形象(隐私头像) + 情绪气泡 + 头像涟漪 + 控制区(关心我/静音/挂断/换个提示)
// 保留 VoiceCallViewModel 全部逻辑; 挂断二次确认 + 情绪共情浮层
// P2.7B-HOME-CALL-VISUAL-POLISH:
// · 主视觉切换为完整形象 portrait 模式 (新小猫图, 2:3 自然比例 + 底部柔边渐隐 + halo 融合)
// · 整体节奏更清晰: 顶部状态区紧凑 / 中央人物区更有存在感 / 语音反馈改为头像后自然扩散涟漪
// · 三按钮(静音/挂断/换个提示)布局更稳, 间距统一
// · 结束确认弹窗圆角与高光与主页卡片统一 (cardTopHighlight)
// · 免按键用户提示恢复 (P2.7B-FIX): 普通界面显示"直接说话就好, 小猫在听"
// · 公开诊断按钮移除 (P2.7B-FIX): stethoscope 不再出现在普通界面; 诊断 Sheet 保留,
//   通过长按状态行(受控手势)进入, 不删除排障能力
// · hero 高度弹性适配 (P2.7B-FIX): 空间不足(气泡/大字号/长转写)时头像等比缩小,
//   底部控制区不被压缩裁切; 转写 lineLimit 2 行
// · finishCall(closePage:) 单一收口保持不变

struct VoiceCallView: View {
    @StateObject var viewModel: VoiceCallViewModel
    @Environment(\.scenePhase) private var scenePhase
    let close: () -> Void

    // 浮层状态
    @State private var showHangupConfirm = false
    @State private var showEmpathy = false
    @State private var showDiagnostics = false
    // P2.7B-FINAL-IDLE: "继续聊"本地抑制预警弹窗 (不伪造语音活动; 真实 speech_start 由 controller 清空)
    @State private var idleWarningDismissed = false
    @State private var copiedDiagnostics = false
    @State private var emotionBubbleVisible = false
    // P2.8A: 静音状态单一来源 = controller.isMuted (UI 不再持有本地 muted)
    @State private var topicIndex = 0
    @State private var appeared = false
    // P2.6B: 防重复结束 (URL scheme 挂断 + onDisappear 双路径)
    @State private var hasEnded = false
    // P2.6F: 共情卡状态 (welcome/longCall/reconnect 中性触发 + manual 手动彩蛋)
    @State private var currentEmpathyCard: EmpathyCard = .welcome
    @State private var empathyReason: EmpathyCard.Kind? = nil
    @State private var reconnectCardShown = false   // reconnect 卡只自动出现一次

    private let topics = [
        "今天过得怎么样？",
        "最近有没有什么开心的小事？",
        "周末想怎么安排？",
        "有没有什么想聊又没处说的话题？"
    ]

    // P2.7B: 通话页主视觉尺寸上限 (portrait 模式 width=size, height=size*3/2 自动)
    private let heroSize: CGFloat = 220
    // P2.7B-FIX: hero 弹性下限 (空间不足时等比缩小到此)
    private let heroMinSize: CGFloat = 150

    var body: some View {
        ZStack {
            // P2.7B-FINAL-MESH: 有机渐变背景 (替换原背景渐变 + 背景循环呼吸)
            OrganicMeshBackground(mode: .call)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部: 关闭 + 状态 (P2.7B-FIX: 移除公开诊断按钮)
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // 状态行 (计时 / 降噪) — P2.7B-FIX: 长按打开诊断 (受控手势)
                statusRow
                    .padding(.top, 8)
                    .padding(.horizontal, 20)
                    .onLongPressGesture(minimumDuration: 1.0) {
                        WarmHaptics.action()
                        showDiagnostics = true
                    }
                    .accessibilityHint("长按查看语音诊断")
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)

                // P2.7B-FIX: 恢复免按键用户提示 (不是开发信息, 是免按键语音的重要说明)
                Text("直接说话就好，小猫在听")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 6)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)

                Spacer(minLength: 0)

                // 中央形象 (呼吸辉光 + 隐私头像 portrait) — P2.7B-FIX: 高度弹性, 空间不足时等比缩小
                heroSection
                    .frame(minHeight: heroMinSize * 3.0 / 2.0 + 16, maxHeight: heroSize * 3.0 / 2.0 + 24)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.95)
                    .animation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.25), value: appeared)
                    // P2.8A: 首次连接加载反馈 (idle/connecting 时浮在人物上方, .ready 自动淡出)
                    .overlay {
                        if !viewModel.controller.hasCompletedInitialConnection,
                           viewModel.controller.state != .failed,
                           viewModel.controller.state != .closed,
                           viewModel.controller.state != .closing {
                            connectingCard
                                .transition(.opacity)
                        }
                    }

                // 名字 (宋体)
                Text("小猫")
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 4)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)

                // 转写 / 回复文本 (P2.7B-FIX: lineLimit 2 控制纵向占用)
                // P2.7B-FINAL-VISUAL-FIX: 通过 displayConversationText 过滤孤立纯标点,
                // 仅展示包含字母/数字/中文/Emoji 等实质字符的会话文字.
                if let text = displayConversationText {
                    Text(text)
                        .font(Theme.subheadFont)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .opacity(appeared ? 1 : 0)
                }

                if viewModel.controller.state == .reconnecting {
                    Text(viewModel.controller.reconnectStatusText)
                        .font(Theme.footnoteFont)
                        .foregroundStyle(Theme.warning)
                        .padding(.top, 6)
                }
                if !viewModel.controller.errorMessage.isEmpty {
                    Text(viewModel.controller.errorMessage)
                        .font(Theme.footnoteFont)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }

                Spacer(minLength: 0)

                // 情绪提示气泡
                if emotionBubbleVisible {
                    emotionBubble
                        .padding(.horizontal, 24)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 底部控制区 (P2.7B-FIX: layoutPriority 保证不被压缩)
                controlArea
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                    .layoutPriority(1)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: appeared)
            }
        }
        .accessibilityIdentifier("call.screen")
        // P2.7B-FINAL-IDLE-FIX: 单一 overlay 优先级链 —
        // 空闲结束 > 空闲预警 > 挂断确认 > 共情卡.
        // SwiftUI 同一 overlay 内 if/else 互斥, 保证高优先级浮层独占显示.
        .overlay {
            if viewModel.controller.idleTimeoutEnded {
                idleEndedOverlay
            } else if viewModel.controller.idleWarningRemainingSeconds != nil, !idleWarningDismissed {
                idleWarningOverlay
            } else if showHangupConfirm {
                hangupConfirmOverlay
            } else if showEmpathy {
                empathyOverlay
            }
        }
        .onChange(of: viewModel.controller.idleWarningRemainingSeconds) { newValue in
            // P2.7B-FINAL-IDLE-FIX: 移除恒真条件 —
            // 仅在服务端下发新一轮预警 (非 nil) 时复位本地抑制, 让新预警重新可见;
            // 真实语音恢复 (nil) 时无需复位 (弹窗因 nil 条件自然消失).
            if newValue != nil {
                idleWarningDismissed = false
            }
        }
        .onChange(of: viewModel.controller.idleTimeoutEnded) { ended in
            // P2.7B-FINAL-IDLE: 空闲自动结束立即结束 Live Activity 并恢复屏幕常亮,
            // 不等用户点击"回到首页"; 后续 finishCall 内部幂等再次调用 Live Activity end,
            // 不造成重复业务请求 (finishCall 内部 hasEnded 防重复).
            guard ended else { return }
            // P2.7B-FINAL-IDLE-FIX: 空闲结束时清理其他通话浮层,
            // 避免挂断确认/共情卡/情绪气泡残留在结束弹窗之后.
            showHangupConfirm = false
            showEmpathy = false
            emotionBubbleVisible = false
            idleWarningDismissed = false
            CallLiveActivityManager.shared.end()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            // P2.6A: 启动 Live Activity, 传入 controller 驱动真实状态 (幂等, 前后台不重复创建)
            // P2.6D: Live Activity 一律使用生产语音角色 (恒为小猫), 不随预览角色变化
            CallLiveActivityManager.shared.start(
                characterName: CompanionRoleStore.shared.productionRole.displayName,
                controller: viewModel.controller
            )
            // P2.6H: 先显示页面, 再建立语音会话 — 连接耗时不再表现为页面空白/卡顿
            appeared = true
            await Task.yield()
            await viewModel.appear()

            // P2.6F-B: 初始中性提示 (2.8s) — welcome, 不标记 longCall, 不随机推断情绪
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            currentEmpathyCard = .welcome
            empathyReason = .welcome
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { emotionBubbleVisible = true }

            // P2.6F-C: 真实长通话提示 (通话满 300s) — 同一可取消 .task, 无 Timer
            try? await Task.sleep(nanoseconds: 297_200_000_000)
            guard !Task.isCancelled else { return }
            currentEmpathyCard = .longCall
            empathyReason = .longCall
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { emotionBubbleVisible = true }
        }
        // P2.6F-FIX-1: 重连提示改为 onChange 立即监听 (reconnectAttempt >= 2 首次, 不等 300s, 无轮询)
        .onChange(of: viewModel.controller.reconnectAttempt) { attempt in
            guard attempt >= 2, !reconnectCardShown else { return }
            reconnectCardShown = true
            currentEmpathyCard = .reconnect
            empathyReason = .reconnect
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { emotionBubbleVisible = true }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background: viewModel.enterBackground()
            case .active: viewModel.enterForeground()
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMuteFromActivity)) { _ in
            // 灵动岛静音按钮 → 直通主 App (状态由 controller 统一管理, UI 无需本地 toggle)
            if viewModel.canMute {
                viewModel.toggleMute()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hangupFromActivity)) { _ in
            // 灵动岛挂断按钮 → 直通主 App (统一结束路径, 防重复由 finishCall 保证)
            WarmHaptics.action()
            finishCall()
        }
        .sheet(isPresented: $showDiagnostics) {
            diagnosticsSheet
        }
    }

    // MARK: - 唯一通话结束路径 (P2.6B-FIX-1)
    /// 所有结束路径统一入口:
    /// 1. 先设置 hasEnded 防重复 (每次页面生命周期只允许一次 teardown)
    /// 2. 结束 Live Activity
    /// 3. viewModel.disappear() (只调用一次)
    /// 4. 按需关闭页面 (onDisappear 场景由系统 dismiss 触发, 不再手动 close)
    private func finishCall(closePage: Bool = true) {
        guard !hasEnded else { return }
        hasEnded = true
        CallLiveActivityManager.shared.end()
        viewModel.disappear()
        if closePage {
            close()
        }
    }

    // MARK: 顶部栏 — 左上仅收起页面，通话生命周期保持不变
    private var topBar: some View {
        HStack {
            Button {
                WarmHaptics.action()
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface.opacity(0.7), in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel("收起通话")
            .accessibilityHint("通话会继续，可从当前通话状态条重新进入")
            .accessibilityIdentifier("call.close")

            Spacer()

            // P2.7B-FIX: 普通界面不再显示诊断入口; 诊断仅可通过长按状态行进入
            Color.clear
                .frame(width: 40, height: 40)
        }
        .opacity(appeared ? 1 : 0)
    }

    // MARK: 状态行 (P2.6J: 真实会话状态文案, 普通界面隐藏内部技术信息)
    private var statusRow: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(callStatusColor)
                    .frame(width: 7, height: 7)
                Text(callStatusText)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // P2.6J: 通话状态文案 (纯 UI 映射, 不接入连接流程)
    private var callStatusText: String {
        if !viewModel.controller.hasCompletedInitialConnection,
           viewModel.controller.state != .failed,
           viewModel.controller.state != .closed,
           viewModel.controller.state != .closing,
           viewModel.controller.state != .reconnecting,
           viewModel.controller.state != .degraded {
            return "正在准备麦克风"
        }
        switch viewModel.controller.state {
        case .idle, .connecting: return "正在连接小猫"
        case .ready, .listening, .endpointing: return "小猫正在听你说话"
        case .processing: return "小猫正在想"
        case .speaking, .interrupting: return "小猫正在说话"
        case .reconnecting: return "正在重新连接"
        case .degraded: return "网络状态不稳定"
        case .closing, .closed: return "正在结束"
        case .failed: return "连接失败"
        }
    }

    // P2.6K: 通话状态点颜色 (与真实 Session 状态一致, 纯 UI 映射)
    private var callStatusColor: Color {
        if !viewModel.controller.hasCompletedInitialConnection,
           viewModel.controller.state != .failed,
           viewModel.controller.state != .closed,
           viewModel.controller.state != .closing,
           viewModel.controller.state != .reconnecting,
           viewModel.controller.state != .degraded {
            return Theme.textTertiary
        }
        switch viewModel.controller.state {
        case .idle, .connecting, .closing, .closed:
            return Theme.textTertiary
        case .ready, .listening, .endpointing, .processing, .speaking, .interrupting:
            return Theme.online
        case .reconnecting, .degraded:
            return Theme.warning
        case .failed:
            return Theme.danger
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // P2.7B-FINAL-MESH: 删除背景循环光效状态; 仅保留人物极轻呼吸
    @State private var avatarBreathScale = false

    // P2.7A: 正在聆听时麦克风轻微 pulse (ready/listening/endpointing 且未静音; Reduce Motion 停止; 非 Timer 驱动)
    private var micPulseActive: Bool {
        guard !viewModel.controller.isMuted, !reduceMotion else { return false }
        switch viewModel.controller.state {
        case .ready, .listening, .endpointing: return true
        default: return false
        }
    }

    // MARK: 首次连接加载反馈 (P2.8A: 明显但克制, 不伪造进度, 不阻塞左上结束入口)
    private var connectingCard: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(Theme.primary)
            Text("正在连接小猫")
                .font(Theme.subheadFont)
                .foregroundStyle(Theme.textPrimary)
            Text("通常只需要几秒")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .glassEffect(
            .regular
                .tint(Theme.primarySoft.opacity(0.25)),
            in: .rect(cornerRadius: Theme.Radius.card)
        )
        .shadow(color: Theme.shadowRaised, radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("call.connecting")
    }

    // MARK: 中央人物区 (P2.7B-FIX: GeometryReader 等比适配可用高度)
    private var heroSection: some View {
        GeometryReader { heroGeo in
            let maxH = heroGeo.size.height
            let availableSize = min(heroSize, max(heroMinSize, maxH * 2.0 / 3.0))

            ZStack {
                // 人物局部 halo — P2.7B-FINAL-MESH: 静态 RadialGradient (固定透明度/尺寸,
                // 不再独立循环放大缩小; 背景流动由 Mesh 承担)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.roleGold.opacity(0.30), Theme.primarySoft.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 50,
                            endRadius: 200
                        )
                    )
                    .frame(width: 380, height: 380)

                VoiceAvatarRipples(
                    muted: viewModel.controller.isMuted,
                    state: viewModel.controller.state,
                    level: viewModel.controller.vadNormalizedRMS
                )
                .frame(width: availableSize * 1.46, height: availableSize * 1.34)
                .accessibilityHidden(true)

                // 底部光斑 (与 portrait 底部渐隐融合)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Theme.heroGlow, Theme.heroGlow.opacity(0.4), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 130
                        )
                    )
                    .frame(width: 280, height: 50)
                    .offset(y: availableSize * 0.55)
                    .blur(radius: 22)
                    .opacity(0.8)
                    .accessibilityHidden(true)

                PrivacyAvatar(
                    size: availableSize,
                    tappable: false,
                    variant: .xiaomao
                )
                .scaleEffect(avatarBreathScale ? 1.012 : 0.988)
                .offset(y: avatarBreathScale ? -3 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: avatarBreathScale)
                .onAppear { avatarBreathScale = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 情绪气泡
    private var emotionBubble: some View {
        HStack(alignment: .top, spacing: 12) {
            PrivacyAvatar(size: 36, tappable: false)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(currentEmpathyCard.label)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.primaryPressed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.primary100, in: Capsule())
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeIn(duration: 0.2)) { emotionBubbleVisible = false }
                    } label: {
                        Text("继续聊聊")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .accessibilityLabel("关闭情绪提示")
                }
                Text(currentEmpathyCard.body)
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.surfaceWarm, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: Theme.shadowFloating, radius: 20, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("情绪提示：\(currentEmpathyCard.label)")
        .accessibilityIdentifier("call.emotion")
    }

    // MARK: 会话文字过滤 (P2.7B-FINAL-VISUAL-FIX)
    // 避免孤立显示纯标点 (? . 。 … ... ! ！ , 、 等);
    // 保留包含 Letter / Decimal Digit / 中文 / Emoji 等实质字符的内容.
    // responseText 优先, transcript 兜底; 两者均不展示时返回 nil.
    // 不修改 controller 字段, 不读网络/磁盘/随机数; 仅 Unicode 标量遍历.
    private var displayConversationText: String? {
        let raw = viewModel.controller.responseText.isEmpty
            ? viewModel.controller.transcript
            : viewModel.controller.responseText
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let scalars = trimmed.unicodeScalars
        let hasContent = scalars.contains { s in
            CharacterSet.letters.contains(s)
                || CharacterSet.decimalDigits.contains(s)
                // Emoji Presentation 标量 + 部分非字母数字 Emoji 标量
                || s.properties.isEmojiPresentation
                || (s.properties.isEmoji && s.value > 0x2000)
                // CJK Unified Ideographs (中文) 及兼容汉字
                || (s.value >= 0x4E00 && s.value <= 0x9FFF)
        }
        return hasContent ? trimmed : nil
    }

    // MARK: 底部控制区
    private var controlArea: some View {
        VStack(spacing: 12) {
            // 聊天提示行 (P2.8A: 仅本地建议文案, 不修改模型对话主题)
            HStack(spacing: 6) {
                Text("聊天提示")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
                Text(topics[topicIndex])
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Theme.surface.opacity(0.6), in: Capsule())

            // 关心我胶囊
            Button {
                WarmHaptics.comfort()
                // P2.6F-E: 手动「关心我」是唯一允许随机彩蛋卡的入口
                currentEmpathyCard = .randomManual()
                empathyReason = .userRequest
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { showEmpathy = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15))
                    Text("关心我")
                        .font(Theme.subheadFont)
                }
                .foregroundStyle(Theme.primaryPressed)
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(Theme.primary100, in: Capsule())
                .shadow(color: Theme.shadowRaised, radius: 8, x: 0, y: 3)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("call.care")

            // 控制按钮行 (P2.7B: 三按钮布局更稳 — 间距统一, 与玻璃容器协调)
            GlassEffectContainer {
                HStack(spacing: 36) {
                    controlButton(
                        icon: viewModel.controller.isMuted ? "mic.slash.fill" : "mic.fill",
                        title: viewModel.controller.isMuted ? "取消静音" : "静音",
                        style: viewModel.controller.isMuted ? .active : .normal,
                        identifier: "call.mute",
                        micPulse: micPulseActive
                    ) {
                        viewModel.toggleMute()
                    }
                    // P2.8A: 已静音时保持可点 — 断连但可恢复状态下取消静音会触发现有重连
                    .disabled(!viewModel.canMute && !viewModel.controller.isMuted)
                    .opacity((viewModel.canMute || viewModel.controller.isMuted) ? 1 : 0.4)

                    controlButton(
                        icon: "phone.down.fill",
                        title: "挂断",
                        style: .danger,
                        identifier: "call.hangup"
                    ) {
                        WarmHaptics.action()
                        withAnimation(.easeOut(duration: 0.28)) { showHangupConfirm = true }
                    }

                    controlButton(
                        icon: "lightbulb",
                        title: "换个提示",
                        style: .normal,
                        identifier: "call.topic",
                        accessibilityHint: "更换一个聊天提示"
                    ) {
                        WarmHaptics.action()
                        // P2.8A: 仅切换本地建议文案, 不发送协议事件, 不修改模型对话主题
                        withAnimation(.easeInOut(duration: 0.2)) {
                            topicIndex = (topicIndex + 1) % topics.count
                        }
                    }
                }
                .padding(.top, 2)
            }

            if viewModel.showReconnect {
                Button("重新连接") { viewModel.reconnect() }
                    .font(Theme.subheadFont)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(Theme.warning, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("call.reconnect")
            }
        }
    }

    private enum ControlStyle {
        case normal, active, danger
    }

    private func controlButton(icon: String, title: String, style: ControlStyle,
                               identifier: String, micPulse: Bool = false,
                               accessibilityHint: String? = nil,
                               action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(iconColor(style))
                    // P2.7A: 静音图标 Symbol 替换过渡 (每次状态改变执行一次)
                    .contentTransition(.symbolEffect(.replace))
                    // P2.7A: 正在聆听时麦克风状态驱动轻微 pulse (非 Timer, 跟随 Reduce Motion)
                    .symbolEffect(.pulse, options: .repeating, isActive: micPulse)
                    .frame(width: 60, height: 60)
                    .glassEffect(glassEffect(style), in: .circle)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(title)
            .accessibilityHint(accessibilityHint ?? "")
            .accessibilityIdentifier(identifier)
            Text(title)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // P2.7A: 三按钮玻璃状态映射 (normal=regular 无 tint / active=primarySoft 轻 tint / danger=interactive+danger 强 tint)
    private func glassEffect(_ style: ControlStyle) -> Glass {
        switch style {
        case .normal: return .regular
        case .active: return .regular.tint(Theme.primarySoft)
        case .danger: return .regular.tint(Theme.danger).interactive()
        }
    }

    private func iconColor(_ style: ControlStyle) -> Color {
        switch style {
        case .normal: return Theme.textPrimary
        case .active: return Theme.primaryPressed
        case .danger: return .white
        }
    }

    // MARK: 空闲预警弹窗 (P2.7B-FINAL-IDLE)
    // 服务端 idle_warning → 用户可见的友好提示; 半透明背景不遮挡人物,
    // 不暂停麦克风; "继续聊"仅关闭提示, 不伪造语音活动 (真实 speech_start 由 VAD 上报);
    // 剩余秒数来自服务端 remaining_seconds, 不做本地倒计时.
    private var idleWarningOverlay: some View {
        ZStack {
            // P2.7B-FINAL-IDLE-FIX: 预警背景仅作半透明遮罩, 不响应点击关闭
            // (空闲预警只能通过"继续聊"/"结束通话"或真实语音恢复关闭)
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)

                Text("小猫还在等你")
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("再说句话就能继续。如果继续安静，通话将在约 \(viewModel.controller.idleWarningRemainingSeconds ?? 30) 秒后自动结束。")
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeIn(duration: 0.2)) { dismissIdleWarning() }
                    } label: {
                        Text("继续聊")
                            .font(Theme.headlineFont)
                            .foregroundStyle(Theme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.primary, in: Capsule())
                            .shadow(color: Theme.ctaShadow, radius: 10, x: 0, y: 5)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("继续聊")
                    .accessibilityHint("关闭提示，直接说话即可继续通话")
                    .accessibilityIdentifier("idle.warning.continue")

                    Button {
                        WarmHaptics.action()
                        withAnimation(.easeIn(duration: 0.2)) { dismissIdleWarning() }
                        finishCall()
                    } label: {
                        Text("结束通话")
                            .font(Theme.headlineFont)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("结束通话")
                    .accessibilityIdentifier("idle.warning.end")
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .cardTopHighlight()
            .shadow(color: Theme.shadowOverlay, radius: 32, x: 0, y: 12)
            .padding(.horizontal, 32)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("空闲提示")
        .accessibilityValue("小猫还在等你，剩余约 \(viewModel.controller.idleWarningRemainingSeconds ?? 30) 秒")
        .accessibilityIdentifier("idle.warning.overlay")
    }

    // MARK: 空闲自动结束弹窗 (P2.7B-FINAL-IDLE)
    // session.ended(idle_timeout) → 最终提示; 优先于挂断确认/共情卡显示.
    // 结束通话时同时结束 Live Activity 并恢复屏幕常亮 (finishCall 内幂等处理).
    private var idleEndedOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)

                Text("通话已暂时结束")
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("一段时间没有听到你的声音，小猫先帮你结束了这次通话。")
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    WarmHaptics.action()
                    finishCall()
                } label: {
                    Text("回到首页")
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.primary, in: Capsule())
                        .shadow(color: Theme.ctaShadow, radius: 10, x: 0, y: 5)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("回到首页")
                .accessibilityHint("结束本次通话并返回首页，可重新进入开始新的通话")
                .accessibilityIdentifier("idle.ended.home")
                .padding(.top, 4)
            }
            .padding(24)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .cardTopHighlight()
            .shadow(color: Theme.shadowOverlay, radius: 32, x: 0, y: 12)
            .padding(.horizontal, 40)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("通话已暂时结束")
        .accessibilityValue("一段时间没有听到你的声音，小猫先帮你结束了这次通话")
        .accessibilityIdentifier("idle.ended.overlay")
    }

    // MARK: 关闭空闲预警 (仅隐藏提示, 不伪造语音活动)
    private func dismissIdleWarning() {
        // 仅本地隐藏当前提示; 不发送假 VAD 事件, 不修改控制器状态.
        // 用户真实开口后由现有 VAD 上报 speech_start 并清空 controller 预警.
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            idleWarningDismissed = true
        }
    }

    // MARK: 挂断确认浮层 (P2.7B 视觉统一: 圆角 22 与主页卡片一致, cardTopHighlight 顶部高光)
    private var hangupConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.2)) { showHangupConfirm = false }
                }

            VStack(spacing: 18) {
                Text("确定要结束这次陪伴吗？")
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)
                Text("今天聊得刚刚好，随时回来找我。")
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeIn(duration: 0.2)) { showHangupConfirm = false }
                    } label: {
                        Text("再聊一会儿")
                            .font(Theme.subheadFont)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hangup.cancel")

                    Button {
                        WarmHaptics.action()
                        withAnimation(.easeIn(duration: 0.2)) {
                            showHangupConfirm = false
                            // 挂断确认 → 统一结束路径
                            finishCall()
                        }
                    } label: {
                        Text("结束通话")
                            .font(Theme.subheadFont)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.danger, in: Capsule())
                            // P2.7B: 挂断按钮双层阴影 (外层柔散 + 内层贴近), 与首页 CTA 视觉一致
                            .shadow(color: Theme.danger.opacity(0.30), radius: 14, x: 0, y: 6)
                            .shadow(color: Theme.danger.opacity(0.15), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hangup.confirm")
                }
            }
            .padding(24)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            // P2.7B: 卡片顶部 1px 高光, 与主页陪伴记录卡视觉统一
            .cardTopHighlight()
            .shadow(color: Theme.shadowOverlay, radius: 32, x: 0, y: 12)
            .padding(.horizontal, 40)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .transition(.opacity)
        .accessibilityIdentifier("hangup.overlay")
    }

    // MARK: 情绪共情浮层
    // P2.6F: 共情触发说明 (安全文案, 不声称识别真实情绪)
    private var reasonCopy: String {
        switch empathyReason {
        case .welcome: return "小猫的悄悄话"
        case .longCall: return "聊了挺久，小猫想看看你好不好。"
        case .reconnect: return "刚才网络有点抖，小猫一直没走开。"
        case .userRequest: return "你点了一下，小猫就来了。"
        case nil: return "小猫的悄悄话"
        }
    }

    private var empathyOverlay: some View {
        ZStack {
            Theme.bg.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.2)) { showEmpathy = false }
                }

            VStack(spacing: 16) {
                Text(currentEmpathyCard.label)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.primaryPressed)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.primary100, in: Capsule())

                Text(currentEmpathyCard.title)
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)

                Text(currentEmpathyCard.body)
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                // 抱抱卡
                HStack(alignment: .top, spacing: 12) {
                    PrivacyAvatar(size: 44, tappable: false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentEmpathyCard.hugLine)
                            .font(Theme.subheadFont)
                            .foregroundStyle(Theme.textPrimary)
                        Text(currentEmpathyCard.hugDetail)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(Theme.surfaceWarm, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                HStack(spacing: 12) {
                    Button {
                        WarmHaptics.comfort()
                        withAnimation(.easeIn(duration: 0.2)) { showEmpathy = false }
                        withAnimation(.easeOut(duration: 0.3)) { emotionBubbleVisible = true }
                    } label: {
                        Text("抱抱我")
                            .font(Theme.headlineFont)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.primary, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("empathy.hug")

                    Button {
                        withAnimation(.easeIn(duration: 0.2)) { showEmpathy = false }
                        withAnimation(.easeOut(duration: 0.2)) {
                            topicIndex = (topicIndex + 1) % topics.count
                        }
                    } label: {
                        Text("换个话题")
                            .font(Theme.headlineFont)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("empathy.topic")
                }
                .padding(.top, 4)

                Text(reasonCopy)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(24)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.shadowOverlay, radius: 32, x: 0, y: 12)
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
        .transition(.opacity)
        .accessibilityIdentifier("empathy.overlay")
    }

    // MARK: 诊断 sheet (P2.7B-FIX: 仅受控手势可进入, 普通界面无入口)
    private var diagnosticsSheet: some View {
        NavigationStack {
            ScrollView {
                // P2.6J: 固定技术路线标识, 仅诊断可见
                Text("SC2.0 · 路线 B")
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 12)
                Text(viewModel.controller.diagnosticText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("语音诊断")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copiedDiagnostics ? "已复制" : "复制诊断信息") {
                        UIPasteboard.general.string = viewModel.controller.diagnosticText
                        copiedDiagnostics = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showDiagnostics = false }
                }
            }
        }
    }
}

// MARK: - 头像后自然扩散涟漪
struct VoiceAvatarRipples: View {
    let muted: Bool
    let state: VoiceSessionState
    /// 真实输入音量 (0...1), 来自 controller.vadNormalizedRMS。
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanding = false

    var body: some View {
        ZStack {
            // 贴近头像的柔光只做“呼吸”，避免出现清晰圆环边界。
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.primarySoft.opacity(0.16 + 0.14 * activityStrength),
                            Theme.roleGold.opacity(0.06 + 0.08 * activityStrength),
                            .clear
                        ],
                        center: .center,
                        startRadius: 18,
                        endRadius: 150
                    )
                )
                .scaleEffect(CGFloat(1.01 + 0.045 * activityStrength))
                .blur(radius: 8)

            // 宽而软的“能量带”错相位向外散开。每层椭圆比例/角度固定不同，
            // 不使用随机数，因此自然但可复现，也不会出现两个硬圆圈同步扩张。
            ForEach(0..<5, id: \.self) { index in
                Ellipse()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: .clear, location: 0.55),
                                .init(
                                    color: rippleColor(index)
                                        .opacity(0.055 + 0.075 * activityStrength),
                                    location: 0.70
                                ),
                                .init(
                                    color: Theme.primarySoft
                                        .opacity(0.035 + 0.055 * activityStrength),
                                    location: 0.82
                                ),
                                .init(color: .clear, location: 1.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .rotationEffect(.degrees(rippleRotation(index)))
                    .scaleEffect(
                        x: reduceMotion ? 1.08 : (expanding ? rippleEndScaleX(index) : rippleStartScale(index)),
                        y: reduceMotion ? 1.03 : (expanding ? rippleEndScaleY(index) : rippleStartScale(index))
                    )
                    .blur(radius: 2.4 + CGFloat(index) * 0.55)
                    .opacity(
                        reduceMotion
                            ? 0.34 + 0.18 * activityStrength
                            : (expanding ? 0 : rippleOpacity(index))
                    )
                    .animation(
                        reduceMotion
                            ? nil
                            : .timingCurve(0.16, 0.72, 0.30, 1, duration: rippleDuration(index))
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.52),
                        value: expanding
                    )
            }
        }
        .onAppear { expanding = true }
        .onDisappear { expanding = false }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: level)
        .accessibilityHidden(true)
    }

    private var activityStrength: Double {
        let clampedLevel = min(max(level, 0.0), 1.0)
        switch state {
        case .ready, .listening:
            return muted ? 0.10 : min(1.0, 0.24 + clampedLevel * 2.8)
        case .endpointing:
            return muted ? 0.10 : min(0.86, 0.34 + clampedLevel * 2.2)
        case .processing:
            return 0.32
        case .speaking:
            return 0.78
        case .interrupting:
            return 0.62
        case .reconnecting, .degraded:
            return 0.18
        default:
            return 0.08
        }
    }

    private func rippleOpacity(_ index: Int) -> Double {
        let depth = 1.0 - Double(index) * 0.10
        return (0.42 + 0.22 * activityStrength) * depth
    }

    private func rippleDuration(_ index: Int) -> Double {
        3.25 + Double(index) * 0.18
    }

    private func rippleStartScale(_ index: Int) -> CGFloat {
        0.72 + CGFloat(index) * 0.025
    }

    private func rippleEndScaleX(_ index: Int) -> CGFloat {
        1.28 + CGFloat(index) * 0.055 + CGFloat(activityStrength) * 0.08
    }

    private func rippleEndScaleY(_ index: Int) -> CGFloat {
        1.18 + CGFloat(index) * 0.047 + CGFloat(activityStrength) * 0.06
    }

    private func rippleRotation(_ index: Int) -> Double {
        [-8, 6, -3, 10, -6][index]
    }

    private func rippleColor(_ index: Int) -> Color {
        index.isMultiple(of: 2) ? Theme.primary : Theme.roleGold
    }
}

// MARK: - 预览
#Preview {
    VoiceCallView(viewModel: VoiceCallViewModel(
        controller: VoiceSessionController(
            environment: AppEnvironment.fromBundle(
                hostAdapters: .mock
            ).replacingHostAdapters(.mock),
            socket: MockVoiceAdapter(),
            capture: MockAudioCapture(),
            playback: MockAudioPlayback(),
            audioSession: MockAudioSessionController(),
            networkMonitor: MockNetworkMonitor()
        )
    ), close: {})
}
