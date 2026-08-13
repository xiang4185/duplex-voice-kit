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
    @State private var showCompanionPicker = false
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
    @Environment(\.appVisualMode) private var visualMode
    @ObservedObject private var privacy = AvatarPrivacy.shared

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    private var usesSceneBackground: Bool {
        viewModel.companionStore.current.sceneBackgroundAssetName != nil
    }

    private var usesDarkSceneChrome: Bool {
        switch viewModel.companionStore.current {
        case .assertive, .mystery: return true
        case .warm, .romantic: return false
        }
    }

    private var callTextPrimary: Color {
        usesDarkSceneChrome ? .white.opacity(0.96) : visual.textPrimary
    }

    private var callTextSecondary: Color {
        usesDarkSceneChrome ? .white.opacity(0.72) : visual.textSecondary
    }

    private var callTextTertiary: Color {
        usesDarkSceneChrome ? .white.opacity(0.50) : visual.textTertiary
    }

    private var callGlassTint: Color {
        usesDarkSceneChrome ? .black.opacity(0.24) : visual.glassTint
    }

    private var callBorder: Color {
        usesDarkSceneChrome ? .white.opacity(0.14) : visual.border
    }

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
            callBackground

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

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

                Spacer(minLength: 0)

                heroSection
                    .frame(
                        minHeight: usesSceneBackground ? 280 : heroMinSize * 3.0 / 2.0 + 16,
                        maxHeight: usesSceneBackground ? 370 : heroSize * 3.0 / 2.0 + 24
                    )
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.95)
                    .animation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.25), value: appeared)

                VStack(spacing: 4) {
                    Text(CompanionRoleStore.shared.productionRole.displayName)
                        .font(Theme.title3Font)
                        .foregroundStyle(callTextPrimary)
                    Text(viewModel.companionStore.current.displayName)
                        .font(Theme.captionFont.weight(.medium))
                        .foregroundStyle(callTextSecondary)
                }
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)

                ZStack(alignment: .top) {
                    Color.clear
                    if let text = displayConversationText {
                        Text(text)
                            .font(Theme.subheadFont)
                            .foregroundStyle(callTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 32)
                            .transition(.opacity)
                    }
                }
                .frame(height: 38)
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)

                if viewModel.controller.state == .reconnecting {
                    Text(viewModel.controller.reconnectStatusText)
                        .font(Theme.footnoteFont)
                        .foregroundStyle(usesDarkSceneChrome ? .white.opacity(0.72) : Theme.warning)
                        .padding(.top, 6)
                }
                if !viewModel.controller.errorMessage.isEmpty {
                    Text(viewModel.controller.errorMessage)
                        .font(Theme.footnoteFont)
                        .foregroundStyle(visual.danger)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                if !viewModel.companionSwitchError.isEmpty {
                    Text(viewModel.companionSwitchError)
                        .font(Theme.footnoteFont)
                        .foregroundStyle(visual.danger)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }

                controlArea
                    .padding(.top, usesSceneBackground ? 14 : 8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
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
        .sheet(isPresented: $showDiagnostics) {
            diagnosticsSheet
        }
        .sheet(isPresented: $showCompanionPicker) {
            CompanionSelectionSheet(
                store: viewModel.companionStore,
                isSwitching: viewModel.isSwitchingCompanion,
                select: { type in
                    showCompanionPicker = false
                    Task { await viewModel.switchCompanion(to: type) }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var callBackground: some View {
        if let assetName = viewModel.companionStore.current.sceneBackgroundAssetName {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .scaleEffect(privacy.effectiveReveal() ? 1.0 : 1.04)
                .blur(radius: privacy.effectiveReveal() ? 0 : 14)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: usesDarkSceneChrome ? .black.opacity(0.18) : .white.opacity(0.05), location: 0.0),
                    .init(color: .clear, location: 0.35),
                    .init(color: visual.background.opacity(usesDarkSceneChrome ? 0.10 : 0.14), location: 0.62),
                    .init(color: usesDarkSceneChrome ? .black.opacity(0.80) : visual.background.opacity(0.88), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else {
            OrganicMeshBackground(mode: .call)
                .ignoresSafeArea()
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(callTextSecondary)
                    .frame(width: 40, height: 40)
                    .background(callGlassTint, in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(callBorder.opacity(0.9), lineWidth: 0.8))
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
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Circle()
                    .fill(callStatusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: callStatusColor.opacity(0.42), radius: 4)
                Image(systemName: callStatusIcon)
                    .font(.system(size: 12, weight: .semibold))
                Text(callStatusText)
                    .font(Theme.captionFont.weight(.semibold))
            }
            .foregroundStyle(callTextSecondary)
            .padding(.horizontal, 13)
            .frame(minHeight: 34)
            .background(callGlassTint, in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(callBorder.opacity(0.8), lineWidth: 0.8))
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("通话状态：\(callStatusText)")
    }

    private var callStatusIcon: String {
        if viewModel.isSwitchingCompanion { return "person.2.badge.gearshape" }
        switch viewModel.controller.state {
        case .idle, .connecting: return "antenna.radiowaves.left.and.right"
        case .ready, .listening, .endpointing: return "mic.fill"
        case .processing: return "ellipsis.bubble.fill"
        case .speaking, .interrupting: return "waveform"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .degraded: return "wifi.exclamationmark"
        case .closing, .closed: return "phone.down.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    // P2.6J: 通话状态文案 (纯 UI 映射, 不接入连接流程)
    private var callStatusText: String {
        if viewModel.isSwitchingCompanion {
            return "正在切换陪伴方式"
        }
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
        if viewModel.isSwitchingCompanion {
            return callTextTertiary
        }
        if !viewModel.controller.hasCompletedInitialConnection,
           viewModel.controller.state != .failed,
           viewModel.controller.state != .closed,
           viewModel.controller.state != .closing,
           viewModel.controller.state != .reconnecting,
           viewModel.controller.state != .degraded {
            return callTextTertiary
        }
        switch viewModel.controller.state {
        case .idle, .connecting, .closing, .closed:
            return callTextTertiary
        case .ready, .listening, .endpointing, .processing, .speaking, .interrupting:
            return usesDarkSceneChrome ? .white.opacity(0.82) : Theme.online
        case .reconnecting, .degraded:
            return usesDarkSceneChrome ? .white.opacity(0.68) : Theme.warning
        case .failed:
            return visual.danger
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // P2.7B-FINAL-MESH: 删除背景循环光效状态; 仅保留人物极轻呼吸
    @State private var avatarBreathScale = false

    // 正在聆听时麦克风轻微 pulse；扬声器静音不影响持续采集。
    private var micPulseActive: Bool {
        guard !reduceMotion else { return false }
        switch viewModel.controller.state {
        case .ready, .listening, .endpointing: return true
        default: return false
        }
    }

    // MARK: 首次连接加载反馈 (P2.8A: 明显但克制, 不伪造进度, 不阻塞左上结束入口)
    private var connectingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(visual.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在连接小猫")
                    .font(Theme.captionFont.weight(.semibold))
                    .foregroundStyle(visual.textPrimary)
                Text("通常只需要几秒")
                    .font(Theme.footnoteFont)
                    .foregroundStyle(visual.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(visual.glassTint, in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(visual.border.opacity(0.9), lineWidth: 0.8)
        }
        .shadow(color: visual.shadow, radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("call.connecting")
    }

    private var switchingCompanionCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(visual.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在切换陪伴方式…")
                    .font(Theme.captionFont.weight(.semibold))
                    .foregroundStyle(visual.textPrimary)
                Text("会为你重新建立一段通话")
                    .font(Theme.footnoteFont)
                    .foregroundStyle(visual.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(visual.glassTint, in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(visual.border.opacity(0.9), lineWidth: 0.8)
        }
        .shadow(color: visual.shadow, radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("call.companion.switching")
    }

    // MARK: 中央人物区 (P2.7B-FIX: GeometryReader 等比适配可用高度)
    private var heroSection: some View {
        Group {
            if usesSceneBackground {
                Color.clear
            } else {
                GeometryReader { heroGeo in
                    let maxH = heroGeo.size.height
                    let availableSize = min(heroSize, max(heroMinSize, maxH * 2.0 / 3.0))

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [visual.halo.opacity(0.30), visual.primarySoft.opacity(0.12), .clear],
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 200
                                )
                            )
                            .frame(width: 380, height: 380)

                        VoiceAvatarAura(
                            muted: viewModel.controller.isMuted,
                            state: viewModel.controller.state,
                            level: viewModel.controller.vadNormalizedRMS
                        )
                        .frame(width: availableSize * 1.52, height: availableSize * 1.38)
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
                        .foregroundStyle(visual.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(visual.primarySoft, in: Capsule())
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeIn(duration: 0.2)) { emotionBubbleVisible = false }
                    } label: {
                        Text("继续聊聊")
                            .font(Theme.captionFont)
                            .foregroundStyle(visual.textTertiary)
                    }
                    .accessibilityLabel("关闭情绪提示")
                }
                Text(currentEmpathyCard.body)
                    .font(Theme.subheadFont)
                    .foregroundStyle(visual.textSecondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(visual.surfaceSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(visual.border.opacity(visualMode == .mystery ? 0.84 : 0.46), lineWidth: 0.7)
        }
        .shadow(color: visual.shadow, radius: 20, x: 0, y: 8)
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
        VStack(spacing: 10) {
            GlassEffectContainer {
                HStack(spacing: 42) {
                    controlButton(
                        icon: viewModel.controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        title: viewModel.controller.isMuted ? "取消静音" : "静音",
                        style: viewModel.controller.isMuted ? .active : .normal,
                        identifier: "call.mute",
                        micPulse: micPulseActive
                    ) {
                        viewModel.toggleMute()
                    }
                    .disabled(!viewModel.canMute && !viewModel.controller.isMuted)
                    .opacity((viewModel.canMute || viewModel.controller.isMuted) ? 1 : 0.4)

                    controlButton(
                        icon: "phone.down.fill",
                        title: "挂断",
                        style: .danger,
                        identifier: "call.hangup"
                    ) {
                        withAnimation(.easeOut(duration: 0.28)) { showHangupConfirm = true }
                    }

                    controlButton(
                        icon: "heart.text.square",
                        title: "陪伴",
                        style: .normal,
                        identifier: "call.companion",
                        accessibilityHint: "选择陪伴方式并重新建立通话"
                    ) {
                        showCompanionPicker = true
                    }
                }
            }

            if viewModel.showReconnect {
                Button("重新连接") { viewModel.reconnect() }
                    .font(Theme.subheadFont)
                    .foregroundStyle(visualMode == .mystery ? visual.textPrimary : .white)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(visualMode == .mystery ? visual.primarySoft : Theme.warning, in: Capsule())
                    .overlay {
                        if visualMode == .mystery {
                            Capsule().stroke(visual.border.opacity(0.9), lineWidth: 0.7)
                        }
                    }
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
            Button {
                WarmHaptics.action()
                action()
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(iconColor(style))
                    // 扬声器静音图标 Symbol 替换过渡 (每次状态改变执行一次)
                    .contentTransition(.symbolEffect(.replace))
                    // P2.7A: 正在聆听时麦克风状态驱动轻微 pulse (非 Timer, 跟随 Reduce Motion)
                    .symbolEffect(.pulse, options: .repeating, isActive: micPulse)
                    .frame(width: 76, height: 76)
                    .glassEffect(glassEffect(style), in: .circle)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(title)
            .accessibilityHint(accessibilityHint ?? "")
            .accessibilityIdentifier(identifier)
            Text(title)
                .font(Theme.captionFont.weight(.medium))
                .foregroundStyle(callTextSecondary)
        }
    }

    // P2.7A: 三按钮玻璃状态映射 (normal=regular 无 tint / active=primarySoft 轻 tint / danger=interactive+danger 强 tint)
    private func glassEffect(_ style: ControlStyle) -> Glass {
        switch style {
        case .normal:
            return usesDarkSceneChrome ? .regular.tint(callGlassTint) : .regular
        case .active:
            return usesDarkSceneChrome ? .regular.tint(.white.opacity(0.12)) : .regular.tint(visual.primarySoft)
        case .danger:
            return .regular.tint(Color(uiColor: .systemRed)).interactive()
        }
    }

    private func iconColor(_ style: ControlStyle) -> Color {
        switch style {
        case .normal: return callTextPrimary
        case .active: return usesDarkSceneChrome ? .white : Theme.primaryPressed
        case .danger: return usesDarkSceneChrome ? .white : .white
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
                    .foregroundStyle(visual.textPrimary)
                Text("今天聊得刚刚好，随时回来找我。")
                    .font(Theme.subheadFont)
                    .foregroundStyle(visual.textSecondary)
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeIn(duration: 0.2)) { showHangupConfirm = false }
                    } label: {
                        Text("再聊一会儿")
                            .font(Theme.subheadFont)
                            .foregroundStyle(visual.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(visual.surfaceSoft, in: Capsule())
                            .overlay(Capsule().stroke(visual.border.opacity(0.9), lineWidth: 0.8))
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
                            .foregroundStyle(visualMode == .mystery ? visual.textPrimary : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(visualMode == .mystery ? visual.dangerSoft : visual.danger, in: Capsule())
                            .overlay {
                                if visualMode == .mystery {
                                    Capsule().stroke(visual.danger.opacity(0.72), lineWidth: 0.8)
                                }
                            }
                            // P2.7B: 挂断按钮双层阴影 (外层柔散 + 内层贴近), 与首页 CTA 视觉一致
                            .shadow(color: visual.danger.opacity(0.22), radius: 14, x: 0, y: 6)
                            .shadow(color: visual.danger.opacity(0.12), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hangup.confirm")
                }
            }
            .padding(24)
            .background(visual.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(visual.border.opacity(visualMode == .mystery ? 0.88 : 0.5), lineWidth: 0.7)
            }
            // P2.7B: 卡片顶部 1px 高光, 与主页陪伴记录卡视觉统一
            .cardTopHighlight()
            .shadow(color: visual.shadow, radius: 32, x: 0, y: 12)
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
            visual.background.opacity(visualMode == .mystery ? 0.96 : 0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.2)) { showEmpathy = false }
                }

            VStack(spacing: 16) {
                Text(currentEmpathyCard.label)
                    .font(Theme.captionFont)
                    .foregroundStyle(visual.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(visual.primarySoft, in: Capsule())

                Text(currentEmpathyCard.title)
                    .font(Theme.title3Font)
                    .foregroundStyle(visual.textPrimary)

                Text(currentEmpathyCard.body)
                    .font(Theme.subheadFont)
                    .foregroundStyle(visual.textSecondary)
                    .multilineTextAlignment(.center)

                // 抱抱卡
                HStack(alignment: .top, spacing: 12) {
                    PrivacyAvatar(size: 44, tappable: false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentEmpathyCard.hugLine)
                            .font(Theme.subheadFont)
                            .foregroundStyle(visual.textPrimary)
                        Text(currentEmpathyCard.hugDetail)
                            .font(Theme.captionFont)
                            .foregroundStyle(visual.textSecondary)
                            .lineSpacing(3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(visual.surfaceSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                // 不再放“抱抱我 / 换个话题”这类看起来会改变会话、实际却只是本地 UI 的假操作。
                // 关心卡只负责展示陪伴文案；真正会改变通话的操作仍只有麦克风、挂断和真实语音输入。
                Button {
                    WarmHaptics.comfort()
                    withAnimation(.easeIn(duration: 0.2)) { showEmpathy = false }
                } label: {
                    Text("继续通话")
                        .font(Theme.headlineFont)
                        .foregroundStyle(visualMode == .mystery ? visual.textPrimary : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(visualMode == .mystery ? visual.primarySoft : visual.primary, in: Capsule())
                        .overlay {
                            if visualMode == .mystery {
                                Capsule().stroke(visual.border.opacity(0.9), lineWidth: 0.8)
                            }
                        }
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("empathy.continue")
                .padding(.top, 4)

                Text(reasonCopy)
                    .font(Theme.captionFont)
                    .foregroundStyle(visual.textTertiary)
            }
            .padding(24)
            .background(visual.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(visual.border.opacity(visualMode == .mystery ? 0.88 : 0.5), lineWidth: 0.7)
            }
            .shadow(color: visual.shadow, radius: 32, x: 0, y: 12)
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
                Text(viewModel.controller.latencyDiagnosticText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceWarm, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
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
                        UIPasteboard.general.string = [
                            viewModel.controller.latencyDiagnosticText,
                            viewModel.controller.diagnosticText
                        ].joined(separator: "\n\n")
                        copiedDiagnostics = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showDiagnostics = false }
                }
            }
            .task {
                await viewModel.controller.refreshLatencyProbe()
            }
        }
    }
}

struct CompanionSelectionSheet: View {
    @ObservedObject var store: CompanionModeStore
    let isSwitching: Bool
    var identifierPrefix: String = "call.companion"
    let select: (CompanionType) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appVisualMode) private var visualMode

    var body: some View {
        let visual = Theme.visual(visualMode)
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(CompanionType.allCases) { type in
                        Button {
                            if type == store.current {
                                dismiss()
                            } else {
                                select(type)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(type.thumbnailAssetName)
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(type.thumbnailDisplayScale)
                                    .offset(y: type.thumbnailVerticalOffset)
                                    .frame(width: 44, height: 52)
                                    .clipped()
                                    .background(rowAccent(for: type), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(type.displayName)
                                        .font(Theme.headlineFont)
                                        .foregroundStyle(type == .mystery ? Color(hex: 0xF1EFF7) : visual.textPrimary)
                                    Text(type.summary)
                                        .font(Theme.captionFont)
                                        .foregroundStyle(type == .mystery ? Color(hex: 0xADA8BA) : visual.textSecondary)
                                }
                                Spacer(minLength: 0)
                                if store.current == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(type == .mystery ? Color(hex: 0xC9C5DE) : visual.primary)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(type == .mystery ? Color(hex: 0x777482) : visual.textTertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 68)
                            .background(rowBackground(for: type), in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                                    .stroke(rowBorder(for: type), lineWidth: 0.7)
                            }
                        }
                        .buttonStyle(PressableCardStyle())
                        .disabled(isSwitching)
                        .accessibilityIdentifier("\(identifierPrefix).\(type.rawValue)")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(visual.background.ignoresSafeArea())
            .navigationTitle("陪伴")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("\(identifierPrefix).sheet")
    }

    private func rowBackground(for type: CompanionType) -> Color {
        if type == .mystery { return Color(hex: 0x171923) }
        return Theme.visual(visualMode).surface.opacity(0.84)
    }

    private func rowAccent(for type: CompanionType) -> Color {
        if type == .mystery { return Color(hex: 0x292738) }
        return Theme.visual(visualMode).primarySoft
    }

    private func rowBorder(for type: CompanionType) -> Color {
        if type == .mystery { return Color(hex: 0x343140) }
        return Theme.visual(visualMode).border.opacity(0.52)
    }
}

// MARK: - 头像后流体氛围光
struct VoiceAvatarAura: View {
    let muted: Bool
    let state: VoiceSessionState
    /// 真实输入音量 (0...1), 来自 controller.vadNormalizedRMS。
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode
    @State private var drifting = false

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    var body: some View {
        ZStack {
            // 稳定的近场柔光：只随语音强度改变亮度，不改变几何尺寸。
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            visual.primarySoft.opacity(0.22 + 0.18 * activityStrength),
                            (visualMode == .mystery ? visual.halo : Theme.roleGold).opacity(0.08 + 0.10 * activityStrength),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 170
                    )
                )
                .blur(radius: 18)
                .opacity(0.72 + 0.18 * activityStrength)

            // 成熟语音产品常用“纹理/光流变化”而不是同心圆扩张。
            // 这里用几团无轮廓、非对称的柔光缓慢漂移；真实音量只改变光强。
            ForEach(0..<4, id: \.self) { index in
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                auraColor(index).opacity(0.12 + 0.16 * activityStrength),
                                auraColor(index).opacity(0.045 + 0.075 * activityStrength),
                                .clear
                            ],
                            center: auraCenter(index),
                            startRadius: 8,
                            endRadius: 135 + CGFloat(index) * 10
                        )
                    )
                    .frame(width: auraWidth(index), height: auraHeight(index))
                    .rotationEffect(.degrees(
                        reduceMotion
                            ? auraRotationA(index)
                            : (drifting ? auraRotationB(index) : auraRotationA(index))
                    ))
                    .offset(
                        x: reduceMotion ? 0 : (drifting ? auraOffsetB(index).width : auraOffsetA(index).width),
                        y: reduceMotion ? 0 : (drifting ? auraOffsetB(index).height : auraOffsetA(index).height)
                    )
                    .blur(radius: 24 + CGFloat(index) * 3)
                    .opacity(0.56 + 0.24 * activityStrength)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: auraDuration(index))
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.33),
                        value: drifting
                    )
            }
        }
        .compositingGroup()
        .onAppear { drifting = true }
        .onDisappear { drifting = false }
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

    private func auraDuration(_ index: Int) -> Double {
        [5.8, 6.6, 7.2, 6.1][index] * (visualMode == .mystery ? 1.45 : 1.0)
    }

    private func auraWidth(_ index: Int) -> CGFloat {
        [230, 205, 250, 190][index]
    }

    private func auraHeight(_ index: Int) -> CGFloat {
        [170, 225, 155, 210][index]
    }

    private func auraRotationA(_ index: Int) -> Double {
        [-18, 14, -8, 22][index]
    }

    private func auraRotationB(_ index: Int) -> Double {
        [8, -12, 15, -6][index]
    }

    private func auraOffsetA(_ index: Int) -> CGSize {
        [
            CGSize(width: -24, height: -16),
            CGSize(width: 30, height: -8),
            CGSize(width: -8, height: 28),
            CGSize(width: 20, height: 24)
        ][index]
    }

    private func auraOffsetB(_ index: Int) -> CGSize {
        [
            CGSize(width: 14, height: -28),
            CGSize(width: 18, height: 20),
            CGSize(width: -26, height: 8),
            CGSize(width: 34, height: -2)
        ][index]
    }

    private func auraCenter(_ index: Int) -> UnitPoint {
        [
            UnitPoint(x: 0.34, y: 0.42),
            UnitPoint(x: 0.68, y: 0.38),
            UnitPoint(x: 0.43, y: 0.68),
            UnitPoint(x: 0.70, y: 0.66)
        ][index]
    }

    private func auraColor(_ index: Int) -> Color {
        if visualMode == .mystery {
            return index.isMultiple(of: 2) ? visual.primary : visual.halo
        }
        return switch index {
        case 0, 2: Theme.primary
        case 1: Theme.roleGold
        default: Theme.primarySoft
        }
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
