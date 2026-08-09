import SwiftUI

// MARK: - 隐私头像 (PrivacyAvatar)
// v6.1 隐私优先: 头像默认高斯模糊; 轻触触发解锁流程 (由父视图控制是否弹出确认浮层);
// 已解锁且总开关开启 → 显示真实形象. 支持任意尺寸.
// P2.7B: 自适应双模式 — 主视觉(size>=100)用"完整形象"portrait 风格(新小猫图, 2:3 自然比例 + 底部柔边渐隐,
// 与 halo 光晕自然融合); 小尺寸(size<100)用"缩略图"thumbnail 风格(原方形头像图, 圆形柔边遮罩).
// 默认 style = .auto, 按 size 自动选择, 现有调用方不破坏.

/// 头像角色变体
enum AvatarVariant {
    case xiaomao        // 真实原图 (小猫)
    case healingGirl    // 程序化占位 (樱粉 + 叶)
    case calmUncle      // 程序化占位 (可可 + 日)
}

/// 头像展示风格 (P2.7B)
/// - auto: 根据 size 自动选择 (>=100 视为 portrait, 否则 thumbnail)
/// - portrait: 完整人物形象, 适合主视觉场景 (首页/通话页中央)
/// - thumbnail: 方形小头像, 适合列表/浮层/小徽标
enum AvatarStyle {
    case auto
    case portrait
    case thumbnail
}

/// 隐私阈值 (size >= 此值自动切换 portrait 模式)
private let portraitStyleThreshold: CGFloat = 100

struct PrivacyAvatar: View {
    /// 头像尺寸 (pt). portrait 模式视为容器宽度 (实际高度 = size * 3/2);
    /// thumbnail 模式视为正方形边长.
    var size: CGFloat = 96
    /// 是否允许轻触解锁 (角色卡/主界面 true, 回顾列表等 false)
    var tappable: Bool = true
    /// 头像变体 (默认小猫真实原图)
    var variant: AvatarVariant = .xiaomao
    /// 展示风格 (默认 .auto, 按 size 自动判断)
    var style: AvatarStyle = .auto
    /// 轻触回调 (父视图弹确认浮层)
    var onTap: (() -> Void)? = nil

    @ObservedObject private var privacy = AvatarPrivacy.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode
    @Environment(\.companionType) private var companionType
    // P2.7A-FIX-1: 仅记录当前实例发起的解锁请求与短暂开锁展示
    @State private var requestedUnlock = false
    @State private var unlockFlash = false
    @State private var unlockTask: Task<Void, Never>?

    /// 实际使用的展示风格 (P2.7B-FIX: 仅小猫角色且大尺寸时使用 portrait 完整形象;
    /// 其他预览角色始终 thumbnail, 避免锁定遮罩 200x300 与占位形象 200x200 不一致)
    private var resolvedStyle: AvatarStyle {
        switch style {
        case .auto:
            guard variant == .xiaomao else { return .thumbnail }
            return size >= portraitStyleThreshold ? .portrait : .thumbnail
        case .portrait:
            return variant == .xiaomao ? .portrait : .thumbnail
        case .thumbnail:
            return .thumbnail
        }
    }

    var body: some View {
        let revealed = privacy.effectiveReveal()
        let tokens = Theme.visual(visualMode)

        ZStack {
            switch variant {
            case .xiaomao:
                switch resolvedStyle {
                case .portrait:
                    portraitCharacter(revealed: revealed)
                case .thumbnail, .auto:
                    thumbnailCharacter(revealed: revealed)
                }
            case .healingGirl:
                placeholderAvatar(symbol: "leaf.fill", gradient: Theme.charSakuraGradient, revealed: revealed)
            case .calmUncle:
                placeholderAvatar(symbol: "sun.max.fill", gradient: Theme.charCaramelGradient, revealed: revealed)
            }

            if !revealed || requestedUnlock || unlockFlash {
                // 覆盖全局状态切换过程；只有本头像成功解锁时替换为 lock.open
                ZStack {
                    Circle()
                        .fill(tokens.halo.opacity(unlockFlash ? 0.20 : 0.35))
                    Image(systemName: revealed && (requestedUnlock || unlockFlash) ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: resolvedStyle == .portrait ? size * 0.16 : size * 0.22, weight: .medium))
                        .foregroundStyle(visualMode == .mystery ? tokens.textPrimary : Theme.textOnHalo)
                        .shadow(color: tokens.shadow, radius: 6, x: 0, y: 2)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(
                    width: resolvedStyle == .portrait ? size : size,
                    height: resolvedStyle == .portrait ? size * 3.0 / 2.0 : size
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                )
                .transition(.opacity)
                .accessibilityLabel("头像已模糊保护，轻触解锁")
                .accessibilityHidden(revealed)
            }
        }
        .shadow(color: tokens.shadow, radius: resolvedStyle == .portrait ? size * 0.06 : size * 0.08, x: 0, y: size * 0.04)
        .contentShape(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
        )
        // P2.6D-FIX-1: 不可点击头像退出命中测试, 不拦截外层卡片手势
        .allowsHitTesting(tappable)
        .onTapGesture {
            // 防御性保护: tappable=false 时即使命中也不产生反馈/回调
            guard tappable else { return }
            WarmHaptics.action()
            if !revealed {
                requestedUnlock = true
                onTap?()
            }
        }
        .accessibilityIdentifier(revealed ? "avatar.revealed" : "avatar.locked")
        // P2.7A-FIX-1: 只有刚点击且可交互的本头像执行开锁替换；Reduce Motion 立即移除遮罩
        .onChange(of: revealed) { newValue in
            guard newValue, requestedUnlock, tappable else {
                if !newValue {
                    unlockTask?.cancel()
                    unlockTask = nil
                    requestedUnlock = false
                    unlockFlash = false
                }
                return
            }

            unlockTask?.cancel()
            unlockTask = nil

            if reduceMotion {
                unlockFlash = false
                requestedUnlock = false
                return
            }

            withAnimation(.easeOut(duration: 0.18)) {
                unlockFlash = true
            }
            unlockTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    unlockFlash = false
                    requestedUnlock = false
                }
                unlockTask = nil
            }
        }
        .onDisappear {
            unlockTask?.cancel()
            unlockTask = nil
            requestedUnlock = false
            unlockFlash = false
        }
    }

    // MARK: - Portrait 完整形象 (P2.7B)
    // 用新图 Character (1024×1536 透明 PNG), 2:3 比例自然展示.
    // 底部柔边渐变 mask 让肩部以下自然消散, 与下方 halo 光晕层融合,
    // 视觉目标: "人像自然融入光里", 不出现硬圆头像.
    private func portraitCharacter(revealed: Bool) -> some View {
        let width = size
        let height = size * 3.0 / 2.0
        let mystery = visualMode == .mystery

        return Image(companionType.portraitAssetName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
            .blur(radius: mystery ? (revealed ? 1.5 : 6) : (revealed ? 0 : 6))
            .saturation(mystery ? 0.62 : 1)
            .brightness(mystery ? -0.05 : 0)
            .opacity(mystery ? (revealed ? 0.88 : 0.70) : (revealed ? 1 : 0.92))
            // P2.7B-FINAL-VISUAL-FIX: 删除全尺寸人物叠光 (overlay + plus-lighter blend).
            // 该叠光覆盖完整人物容器, 是浅粉矩形边界的来源之一;
            // 父页面已有静态 halo 与 heroGlow 光效, 人物图内部无需整块叠光.
            // 保留: 底部渐隐 mask / reveal 动画 / 隐私模糊.
            // 底部柔边渐隐: 顶部清晰, 65% 处开始淡出, 100% 完全透明
            // 与外部 halo 光晕层(在父视图叠加)自然融合
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.55),
                        .init(color: .black.opacity(0.85), location: 0.75),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .animation(.easeInOut(duration: 0.35), value: revealed)
    }

    // MARK: - Thumbnail 方形小头像 (保留 v6.1 行为)
    // 适用于情绪气泡 / 陪伴记录入口 / 隐私确认浮层等小尺寸场景.
    private func thumbnailCharacter(revealed: Bool) -> some View {
        let mystery = visualMode == .mystery
        return Image(companionType.thumbnailAssetName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .blur(radius: mystery ? (revealed ? 1 : 5) : (revealed ? 0 : 6))
            .saturation(mystery ? 0.62 : 1)
            .brightness(mystery ? -0.05 : 0)
            .opacity(mystery ? (revealed ? 0.90 : 0.72) : (revealed ? 1 : 0.92))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            // P2.6J+: 径向柔边遮罩 — 只羽化外缘 (中心 82% 保持清晰, 外缘渐隐)
            .mask {
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            }
            .animation(.easeInOut(duration: 0.35), value: revealed)
    }

    /// 原创程序化占位形象 (渐变圆 + 白色符号, 非小猫角色)
    private func placeholderAvatar(symbol: String, gradient: LinearGradient, revealed: Bool) -> some View {
        ZStack {
            Circle()
                .fill(gradient)
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: size, height: size)
        .blur(radius: revealed ? 0 : 5)
        .opacity(revealed ? 1 : 0.92)
        .animation(.easeInOut(duration: 0.35), value: revealed)
    }
}

// MARK: - 隐私确认浮层 (AvatarPrivacyConfirmView)
// 「是否同意与该 AI 形象建立陪伴关系?」— 显式同意后才解锁显示真实形象

struct AvatarPrivacyConfirmView: View {
    var onAgree: () -> Void
    var onDecline: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bg.opacity(0.96)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 18) {
                // 头像 (保持模糊示意)
                PrivacyAvatar(size: 84, tappable: false)

                Text("是否同意与该 AI 形象建立陪伴关系？")
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("这是一段轻量的虚拟陪伴关系。该形象由授权素材或原创设计生成，仅在通话时使用，不会用于商业推广。")
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                // 条款
                VStack(alignment: .leading, spacing: 8) {
                    Text("查看形象即表示同意：")
                        .font(Theme.subheadFont)
                        .foregroundStyle(Theme.textPrimary)
                    Text("· 你看到的形象，来自授权素材或原创设计")
                    Text("· 通话中可能存在「被理解」的主观感受，但本质仍是 AI")
                    Text("· 你可以随时在「我的 - 隐私」关闭形象显示")
                }
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.surfaceWarm, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                HStack(spacing: 12) {
                    Button {
                        WarmHaptics.action()
                        dismiss()
                        onDecline()
                    } label: {
                        Text("暂不同意")
                            .font(Theme.headlineFont)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacy.confirm.decline")

                    Button {
                        WarmHaptics.success()
                        dismiss()
                        onAgree()
                    } label: {
                        Text("同意并查看")
                            .font(Theme.headlineFont)
                            .foregroundStyle(Theme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.primary, in: Capsule())
                            .shadow(color: Theme.ctaShadow, radius: 10, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacy.confirm.agree")
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.shadowOverlay, radius: 32, x: 0, y: 12)
            .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("privacy.confirm.overlay")
    }
}

// MARK: - 预览
#Preview {
    AvatarPrivacyConfirmView(onAgree: {}, onDecline: {})
}
