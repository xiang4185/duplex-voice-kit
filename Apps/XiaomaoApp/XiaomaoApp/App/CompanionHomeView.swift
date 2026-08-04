import SwiftUI
import UIKit

// MARK: - 屏 3 陪聊主界面 · 单页极简 + 活人感 (CompanionHomeView)
// v6.1 重构: 顶栏齿轮 + 时段问候(在呢☀️/🌙/⭐, 9s 文案轮换) · 居中柔光晕头像+呼吸
// · 宋体角色名(letter-spacing 8s 呼吸) · 状态点声呐+动态波形 · 大胶囊 CTA(4.2s 脉冲)
// · 时间脚注 · 底部回顾入口浮层 · 隐私解锁仪式
// P2.7B-HOME-CALL-VISUAL-POLISH:
// · 主视觉放大并切换为完整形象 portrait 模式 (新小猫图, 2:3 自然比例 + 底部柔边渐隐 + halo 融合)
// · hero 区 halo 光晕层与人物比例匹配, 不再硬圆裁切
// · CTA 微调 (阴影更柔, 呼吸幅度更克制)
// · 整体节奏更紧, 上半屏让位主视觉

struct CompanionHomeView: View {
    var startCall: () -> Void
    var openHistory: () -> Void
    var openSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var privacy = AvatarPrivacy.shared
    @ObservedObject private var roleStore = CompanionRoleStore.shared
    @State private var appeared = false
    // P2.6D: 本地轻提示 (可取消 Task)
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var showPrivacyConfirm = false
    @State private var greetingIndex = 0
    @State private var nameBreath = false
    @State private var sonarPulse = false
    // P2.7B-FINAL-MESH: 删除首页旧背景循环光效状态
    // (背景改为 OrganicMeshBackground 慢流动; CTA 仅按压反馈; 人物 halo 静态)
    // P2.6B: 生命周期安全的 Timer 持有 (onDisappear 释放) — 仅问候文字轮换使用
    @State private var greetingTimer: Timer?

    private let greetings: [(text: String, icon: String)] = [
        ("在呢", "sun.max.fill"),
        ("想你了", "moon.stars.fill"),
        ("一直在", "star.fill")
    ]

    // P2.7B: hero 区中央人物高度 (portrait 模式以 width=size 渲染, height=size*3/2 自动)
    private let heroSize: CGFloat = 200

    var body: some View {
        ZStack {
            // P2.7B-FINAL-MESH: 有机渐变背景 (替换原静态线性渐变背景 + 顶部大圆呼吸)
            OrganicMeshBackground(mode: .home)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -8)
                    .animation(.easeOut(duration: 0.4).delay(0.05), value: appeared)

                Spacer(minLength: 0)

                // 中央: 柔光晕 + 完整形象 (portrait 模式, 2:3 自然比例 + 底部渐隐)
                ZStack {
                    // 人物局部 halo — P2.7B-FINAL-MESH: 静态 RadialGradient (固定透明度/尺寸,
                    // 不再独立 repeatForever 呼吸; 背景流动由 Mesh 承担)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [roleStore.previewRole.themeColor.opacity(0.30), Theme.primarySoft.opacity(0.15), .clear],
                                center: .center,
                                startRadius: 50,
                                endRadius: 200
                            )
                        )
                        .frame(width: 380, height: 380)
                        .accessibilityHidden(true)

                    // 底部光斑 (与 portrait 底部渐隐融合, 强化"人像融入光里") — 静态
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [Theme.heroGlow, Theme.heroGlow.opacity(0.4), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 140
                            )
                        )
                        .frame(width: 300, height: 60)
                        .offset(y: heroSize * 0.55)
                        .blur(radius: 24)
                        .opacity(0.85)
                        .accessibilityHidden(true)

                    PrivacyAvatar(
                        size: heroSize,
                        tappable: true,
                        variant: roleStore.previewRole.avatarVariant
                    ) {
                        // 轻触解锁 → 弹确认浮层
                        showPrivacyConfirm = true
                    }
                    .scaleEffect(avatarBreath ? 1.012 : 0.988)
                    .offset(y: avatarBreath ? -3 : 0)   // breathe translateY -3px (微浮)
                    .animation(reduceMotion ? nil : .easeInOut(duration: Theme.avatarBreathDuration).repeatForever(autoreverses: true), value: avatarBreath)
                    .onAppear { avatarBreath = true }
                }
                // 容器高度 = portrait 高度 + 渐隐预留, 让底部光斑有空间铺开
                .frame(height: heroSize * 3.0 / 2.0 + 40)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.94)
                .animation(.spring(response: Theme.entranceDuration, dampingFraction: 0.82).delay(0.15), value: appeared)

                // 状态点声呐 + 动态波形
                HStack(spacing: 10) {
                    sonarDot
                    Text("正在陪你")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                    MiniVoiceWave(active: true, mode: .primary, barCount: 5)
                        .frame(width: 44, height: 16)
                        .opacity(0.75)
                }
                .padding(.top, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                // 宋体角色名 (letter-spacing 呼吸, 跟随预览角色)
                Text(roleStore.previewRole.displayName)
                    .font(Theme.title1Font)
                    .foregroundStyle(Theme.textPrimary)
                    .tracking(nameBreath ? 2.5 : 0.5)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 8).repeatForever(autoreverses: true), value: nameBreath)
                    .onAppear { nameBreath = true }
                    .padding(.top, 12)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)

                // 时段问候文案轮换 (9s)
                HStack(spacing: 6) {
                    Text(greetings[greetingIndex].text)
                        .font(Theme.subheadFont)
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: greetings[greetingIndex].icon)
                        .font(.system(size: 13))
                        .foregroundStyle(roleStore.previewRole.themeColor)
                }
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)
                .onAppear {
                    guard !reduceMotion else { return }
                    // P2.6B: 持有 Timer 引用, onDisappear 释放, 避免视图销毁后仍更新 UI
                    greetingTimer?.invalidate()
                    greetingTimer = Timer.scheduledTimer(withTimeInterval: 9, repeats: true) { _ in
                        withAnimation(.easeInOut(duration: 0.6)) {
                            greetingIndex = (greetingIndex + 1) % greetings.count
                        }
                    }
                }

                Spacer(minLength: 4)

                // 大胶囊 CTA (待机脉冲)
                Button(action: {
                    WarmHaptics.comfort()
                    // P2.6D: 非小猫预览角色不得启动真实通话
                    if roleStore.previewRole.isProductionVoice {
                        startCall()
                    } else {
                        showLocalToast("先和小猫说说话吧。")
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 17, weight: .medium))
                        Text(roleStore.previewRole.introCopy)
                            .font(Theme.headlineFont)
                    }
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    // P2.8A: 整个胶囊区域可点击, 单击一次立即进入通话页
                    .contentShape(Capsule())
                    .glassEffect(
                        .regular
                            .tint(Theme.primary)
                            .interactive(),
                        in: .capsule
                    )
                    // P2.7B: 更柔的双层阴影 (外层柔散 + 内层贴近), 避免"硬贴"感
                    .shadow(color: Theme.ctaShadow.opacity(0.35), radius: 18, x: 0, y: 8)
                    .shadow(color: Theme.primary.opacity(0.18), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 40)
                // P2.6J: Toast 锚定 CTA 上方, 不遮挡按钮文字, 不拦截点击
                .overlay(alignment: .top) {
                    if let toastMessage {
                        Text(toastMessage)
                            .font(Theme.subheadFont)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(
                                .regular
                                    .tint(Theme.primarySoft.opacity(0.35)),
                                in: .capsule
                            )
                            .offset(y: -52)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                            .allowsHitTesting(false)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(.spring(response: Theme.entranceDuration, dampingFraction: 0.75).delay(0.5), value: appeared)
                .accessibilityIdentifier("home.start")

                // 时间脚注 (无真实数据时诚实文案, 不显示假时长)
                Text("连接后即可开始陪伴")
                    .font(Theme.footnoteFont)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 10)
                    .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.6), value: appeared)

                // 底部回顾入口
                Button(action: {
                    WarmHaptics.action()
                    // P2.6I: 直接进入回顾页, 不再弹出静态假历史
                    openHistory()
                }) {
                    HStack(spacing: 12) {
                        PrivacyAvatar(size: 38, tappable: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("陪伴记录")
                                .font(Theme.subheadFont)
                                .foregroundStyle(Theme.textPrimary)
                            Text("当前版本暂不展示聊天或录音历史")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    .cardTopHighlight()
                    .shadow(color: Theme.shadowRaised, radius: 10, x: 0, y: 3)
                }
                // P2.6J+: 可点击卡片按压反馈
                .buttonStyle(PressableCardStyle())
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.7), value: appeared)
                .accessibilityIdentifier("home.history")
            }
        }
        .accessibilityIdentifier("home.screen")
        .sheet(isPresented: $showPrivacyConfirm) {
            AvatarPrivacyConfirmView(
                onAgree: { privacy.unlock() },
                onDecline: { privacy.keepLocked() }
            )
            .presentationDetents([.medium])
        }
        .onAppear { appeared = true }
        // P2.6J: 角色切换时清除残留 Toast (切回小猫不再显示预览提示)
        .onChange(of: roleStore.previewRole) { _ in
            toastTask?.cancel()
            toastMessage = nil
        }
        // P2.6B: 视图销毁时释放 Timer, 避免泄漏与退出后更新 UI
        .onDisappear {
            greetingTimer?.invalidate()
            greetingTimer = nil
            // P2.6D: 视图销毁取消延时 toast
            toastTask?.cancel()
        }
    }

    // MARK: 顶栏
    // MARK: 顶栏 (P2.7B-FINAL-VISUAL-FIX)
    // 删除中间"在呢"绿点+文字+太阳图标+胶囊 (与人物下方"正在陪你"+ 名字下问候轮换重复),
    // 删除右侧透明 Color.clear 占位, 顶栏仅保留设置按钮.
    // 问候数组中的"在呢"不属于重复顶栏, 不得删除.
    private var topBar: some View {
        HStack {
            Button {
                WarmHaptics.action()
                // P2.6J: 齿轮进入设置, 不再进入回顾页
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface.opacity(0.7), in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel("设置")
            .accessibilityIdentifier("home.settings")

            Spacer()
        }
    }

    // MARK: 本地轻提示 (可取消 Task, 2.2s 自动消失)
    private func showLocalToast(_ text: String) {
        toastMessage = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { toastMessage = nil }
        }
    }

    // MARK: 状态点声呐
    private var sonarDot: some View {
        ZStack {
            Circle()
                .stroke(Theme.online.opacity(0.5), lineWidth: 1.5)
                .frame(width: 18, height: 18)
                .scaleEffect(sonarPulse ? 2.2 : 0.8)
                .opacity(sonarPulse ? 0 : 0.7)
                .animation(reduceMotion ? nil : .easeOut(duration: Theme.sonarDuration).repeatForever(autoreverses: false), value: sonarPulse)
                .onAppear { sonarPulse = true }
            Circle()
                .fill(Theme.online)
                .frame(width: 7, height: 7)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    @State private var avatarBreath = false
}

// MARK: - 按压弹簧按钮样式 (v6.1 cubic-bezier(.34,1.56,.64,1))
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.64), value: configuration.isPressed)
    }
}

// MARK: - 可点击卡片按压样式 (P2.6J+)
// 用于首页记录入口 / 角色卡 / 设置关于行等真实可点击卡片;
// 按下 scale ~0.985 + 轻微 opacity, 遵循 Reduce Motion; 不作用于 Toggle 与纯展示卡片
struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

// MARK: - 微型动态波形 (MiniVoiceWave)
// v6.1 状态点旁/回顾列表的动态小波形, 柱高 120ms 缓动

struct MiniVoiceWave: View {
    let active: Bool
    var mode: Mode = .primary
    var barCount: Int = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false
    // P2.6B: 持有 Timer, onDisappear 释放
    @State private var waveTimer: Timer?

    enum Mode {
        case primary, gold, warm, sakura, caramel

        var color: Color {
            switch self {
            case .primary: return Theme.primary
            case .gold: return Theme.roleGold
            case .warm: return Theme.roleGold
            case .sakura: return Theme.roleBlush
            case .caramel: return Theme.roleCaramel
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width / CGFloat(barCount) * 0.42
            let spacing = (geo.size.width - barWidth * CGFloat(barCount)) / CGFloat(barCount - 1)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(mode.color.opacity(active ? 0.85 : 0.30))
                        .frame(width: barWidth, height: barHeight(i, geo: geo))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: phase)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            guard active && !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.12)) { phase = true }
            // P2.6B: 持有 Timer, onDisappear 释放
            waveTimer?.invalidate()
            waveTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { _ in
                withAnimation(.easeOut(duration: 0.12)) { phase.toggle() }
            }
        }
        .onDisappear {
            waveTimer?.invalidate()
            waveTimer = nil
        }
    }

    private func barHeight(_ i: Int, geo: GeometryProxy) -> CGFloat {
        guard active else { return geo.size.height * 0.3 }
        let maxH = geo.size.height
        let amplitudes: [CGFloat] = [0.55, 0.95, 0.4, 1.0, 0.7, 0.85, 0.5, 0.9, 0.62, 0.78]
        let base = amplitudes[i % amplitudes.count]
        let pulse = phase ? 1.0 : 0.65
        return maxH * base * pulse
    }
}

// MARK: - 预览
#Preview {
    CompanionHomeView(startCall: {}, openHistory: {}, openSettings: {})
}
