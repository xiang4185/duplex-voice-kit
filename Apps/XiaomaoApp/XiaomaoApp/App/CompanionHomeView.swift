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
    var openSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode
    @EnvironmentObject private var companionStore: CompanionModeStore
    @ObservedObject private var privacy = AvatarPrivacy.shared
    @ObservedObject private var roleStore = CompanionRoleStore.shared
    @State private var appeared = false
    // P2.6D: 本地轻提示 (可取消 Task)
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var showPrivacyConfirm = false
    @State private var showCompanionPicker = false
    @State private var sceneDrift = false

    // All companion portrait assets share the same 2:3 master template.
    private let heroSize: CGFloat = 200

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }
    private var accent: Color {
        visualMode == .mystery ? visual.primary : roleStore.previewRole.themeColor
    }

    private var usesSceneBackground: Bool {
        companionStore.current.sceneBackgroundAssetName != nil
    }

    private var usesDarkSceneChrome: Bool {
        switch companionStore.current {
        case .assertive, .mystery: return true
        case .warm, .romantic: return false
        }
    }

    private var homeTextPrimary: Color {
        usesDarkSceneChrome ? .white.opacity(0.96) : visual.textPrimary
    }

    private var homeTextSecondary: Color {
        usesDarkSceneChrome ? .white.opacity(0.70) : visual.textSecondary
    }

    private var homeGlassTint: Color {
        usesDarkSceneChrome ? .black.opacity(0.24) : visual.glassTint
    }

    private var homeBorder: Color {
        usesDarkSceneChrome ? .white.opacity(0.14) : visual.border
    }

    var body: some View {
        ZStack {
            homeBackground

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -8)
                    .animation(.easeOut(duration: 0.4).delay(0.05), value: appeared)

                Spacer(minLength: 0)

                homeHero
                .frame(height: usesSceneBackground ? 390 : heroSize * 3.0 / 2.0 + 40)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.94)
                .animation(.spring(response: Theme.entranceDuration, dampingFraction: 0.82).delay(0.15), value: appeared)

                Text(roleStore.previewRole.displayName)
                    .font(Theme.title1Font)
                    .foregroundStyle(homeTextPrimary)
                    .tracking(0.4)
                    .padding(.top, 4)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)

                Text("\(companionStore.current.displayName) · 在呢")
                    .font(Theme.captionFont.weight(.medium))
                    .foregroundStyle(homeTextSecondary)
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)

                Spacer(minLength: 12)

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
                            .font(.system(size: 19, weight: .medium))
                        Text(roleStore.previewRole.introCopy)
                            .font(Theme.headlineFont)
                    }
                    .foregroundStyle(usesDarkSceneChrome ? .white : visual.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    // P2.8A: 整个胶囊区域可点击, 单击一次立即进入通话页
                    .contentShape(Capsule())
                    .glassEffect(
                        .regular
                            .tint(usesDarkSceneChrome ? .black.opacity(0.28) : visual.primary)
                            .interactive(),
                        in: .capsule
                    )
                    .overlay {
                        if usesSceneBackground {
                            Capsule().stroke(homeBorder.opacity(0.9), lineWidth: 0.8)
                        }
                    }
                    .shadow(color: visual.shadow.opacity(0.75), radius: 16, x: 0, y: 7)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 40)
                // P2.6J: Toast 锚定 CTA 上方, 不遮挡按钮文字, 不拦截点击
                .overlay(alignment: .top) {
                    if let toastMessage {
                        Text(toastMessage)
                            .font(Theme.subheadFont)
                            .foregroundStyle(visual.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(
                                .regular
                                    .tint(visual.primarySoft.opacity(0.35)),
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

                Spacer(minLength: 18)
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
        .sheet(isPresented: $showCompanionPicker) {
            CompanionSelectionSheet(
                store: companionStore,
                isSwitching: false,
                identifierPrefix: "home.companion",
                select: { type in
                    companionStore.select(type)
                    showCompanionPicker = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            appeared = true
            sceneDrift = true
        }
        // P2.6J: 角色切换时清除残留 Toast (切回小猫不再显示预览提示)
        .onChange(of: roleStore.previewRole) { _ in
            toastTask?.cancel()
            toastMessage = nil
        }
        // P2.6B: 视图销毁时释放 Timer, 避免泄漏与退出后更新 UI
        .onDisappear {
            toastTask?.cancel()
        }
    }

    @ViewBuilder
    private var homeBackground: some View {
        if let assetName = companionStore.current.sceneBackgroundAssetName {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .scaleEffect(
                    (privacy.effectiveReveal() ? 1.0 : 1.04)
                        * (sceneDrift && !reduceMotion ? 1.018 : 1.0)
                )
                .offset(
                    x: sceneDrift && !reduceMotion ? 4 : -4,
                    y: sceneDrift && !reduceMotion ? -3 : 3
                )
                .blur(radius: privacy.effectiveReveal() ? 0 : 14)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 12).repeatForever(autoreverses: true),
                    value: sceneDrift
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: usesDarkSceneChrome ? .black.opacity(0.18) : .white.opacity(0.03), location: 0.0),
                    .init(color: .clear, location: 0.42),
                    .init(color: visual.background.opacity(usesDarkSceneChrome ? 0.08 : 0.12), location: 0.66),
                    .init(color: usesDarkSceneChrome ? .black.opacity(0.76) : visual.background.opacity(0.86), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else {
            OrganicMeshBackground(mode: .home)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var homeHero: some View {
        if usesSceneBackground {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if !privacy.effectiveReveal() {
                        showPrivacyConfirm = true
                    }
                }
                .accessibilityIdentifier(privacy.effectiveReveal() ? "avatar.revealed" : "avatar.locked")
        } else {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.20), visual.primarySoft.opacity(0.10), .clear],
                            center: .center,
                            startRadius: 50,
                            endRadius: 200
                        )
                    )
                    .frame(width: 380, height: 380)
                    .accessibilityHidden(true)

                PrivacyAvatar(
                    size: heroSize,
                    tappable: true,
                    variant: roleStore.previewRole.avatarVariant
                ) {
                    showPrivacyConfirm = true
                }
                .scaleEffect(avatarBreath ? 1.012 : 0.988)
                .offset(y: avatarBreath ? -3 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: Theme.avatarBreathDuration).repeatForever(autoreverses: true), value: avatarBreath)
                .onAppear { avatarBreath = true }
            }
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
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(homeTextSecondary)
                    .frame(width: 40, height: 40)
                    .background(homeGlassTint, in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(homeBorder.opacity(0.88), lineWidth: 0.7))
            }
            .accessibilityLabel("设置")
            .accessibilityIdentifier("home.settings")

            Spacer()

            Button {
                WarmHaptics.action()
                showCompanionPicker = true
            } label: {
                Label(companionStore.current.displayName, systemImage: "person.2.fill")
                    .font(Theme.captionFont.weight(.semibold))
                    .foregroundStyle(homeTextSecondary)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 40)
                    .background(homeGlassTint, in: Capsule())
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(homeBorder.opacity(0.88), lineWidth: 0.7))
            }
            .accessibilityLabel("切换陪伴")
            .accessibilityIdentifier("home.companion")
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
        Circle()
            .fill(visualMode == .mystery ? visual.primary.opacity(0.72) : Theme.online)
            .frame(width: 7, height: 7)
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
    CompanionHomeView(startCall: {}, openSettings: {})
        .environmentObject(CompanionModeStore())
}
