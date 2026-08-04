#if canImport(SwiftUI)
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import DuplexVoiceKitCompanion

// MARK: - Hex 颜色扩展（文件级私有，与仓库既有 UI 文件模式一致）
private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

// MARK: - 原版壳视觉令牌（DVKCatStyle）
// 将公共 DVKCompanionTheme 映射为参考壳的设计令牌（颜色 / 圆角 / 字体 / 动效 / 阴影），
// 让移植页面保留参考壳的布局与节奏，同时跟随公共主题与角色主题联动。
// 颜色值来自参考壳的公开设计令牌（西柚玫瑰 #D9486B / 桃粉白 #FDF5F1 / 深莓果 #432B33 等）。

struct DVKCatStyle {
    let theme: DVKCompanionTheme

    init(theme: DVKCompanionTheme) { self.theme = theme }

    enum Spacing {
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let xxLarge: CGFloat = 40
        static let xxxLarge: CGFloat = 48
    }

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 22
        static let xLarge: CGFloat = 28
        static let card: CGFloat = 22
        static let characterCard: CGFloat = 28
        static let pill: CGFloat = 999
    }

    var cornerRadius: CGFloat { 16 }

    // MARK: 主色（跟随公共主题 accent）
    var primary: Color { theme.primaryAction }
    var primaryHover: Color { theme.primaryAction.opacity(0.9) }
    var primaryPressed: Color { theme.primaryAction.opacity(0.85) }
    var primarySoft: Color { theme.secondaryAction }
    var onPrimary: Color { theme.textOnAction }
    var primary100: Color { theme.secondaryAction }
    var primary300: Color { theme.primaryAction.opacity(0.72) }
    var primary500: Color { theme.primaryAction }
    var primary600: Color { theme.primaryAction.opacity(0.9) }
    var primary700: Color { theme.primaryAction.opacity(0.85) }
    var primary800: Color { theme.primaryAction.opacity(0.75) }

    // MARK: 底色与表面
    var bg: Color { theme.pageBackground }
    var bgElevated: Color { theme.elevatedSurface }
    var halo: Color { theme.halo }
    var haloGlow: Color { theme.halo.opacity(0.8) }
    var surface: Color { theme.surface }
    var surfaceWarm: Color { theme.assistantMessageSurface }
    var border: Color { theme.border }

    // MARK: 文字
    var textPrimary: Color { theme.textPrimary }
    var textSecondary: Color { theme.textSecondary }
    var textTertiary: Color { theme.textSecondary.opacity(0.8) }
    var textLink: Color { theme.primaryAction }
    var textOnHalo: Color { theme.textOnAction }

    // MARK: 角色三色
    var roleGold: Color { theme.primaryAction }
    var roleBlush: Color { Color(hex: 0xF4A7B8) }
    var roleCaramel: Color { Color(hex: 0xA26A48) }
    var roleSoft: Color { theme.assistantMessageSurface }

    // MARK: 语义色
    var success: Color { Color(hex: 0x71A36B) }
    var warning: Color { theme.primaryAction }
    var danger: Color { Color(hex: 0xD5563C) }
    var info: Color { Color(hex: 0x93A9BC) }
    var online: Color { theme.activeStatus }
    var offline: Color { Color(hex: 0xCDB6B0) }
    var recording: Color { Color(hex: 0xD5563C) }
    var voiceActive: Color { Color(hex: 0xE88BA0) }

    // MARK: 机物渐变背景色
    var meshWarmWhite: Color { Color(hex: 0xFFFAF6) }
    var meshPeach: Color { Color(hex: 0xFCE8EC) }
    var meshRose: Color { Color(hex: 0xF6C3CF) }
    var meshCoolAccent: Color { Color(hex: 0xE7E9ED) }

    // MARK: 消息表面
    var userMessageSurface: Color { theme.userMessageSurface }
    var assistantMessageSurface: Color { theme.assistantMessageSurface }

    // MARK: 阴影体系
    var shadowRaised: Color { theme.shadow.opacity(0.5) }
    var shadowFloating: Color { theme.shadow }
    var shadowOverlay: Color { Color.black.opacity(0.16) }
    var shadowGlow: Color { Color(hex: 0xFAC8D2).opacity(0.50) }
    var heroGlow: Color { Color(hex: 0xFAC8D2).opacity(0.55) }
    var ctaShadow: Color { theme.primaryAction.opacity(0.30) }
    var orbShadow: Color { theme.primaryAction.opacity(0.25) }

    // MARK: 角色变体渐变
    var charWarmGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xE46A83), Color(hex: 0xC2405F)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var charSakuraGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xF6BECB), Color(hex: 0xE28CA1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var charCaramelGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xC08A60), Color(hex: 0xA26A48)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: 背景渐变
    var callBackground: LinearGradient {
        LinearGradient(colors: [bg, Color(hex: 0xF9E0E2), bgElevated], startPoint: .top, endPoint: .bottom)
    }
    var homeBackground: LinearGradient {
        LinearGradient(colors: [bg, Color(hex: 0xFDF2F0), bgElevated], startPoint: .top, endPoint: .bottom)
    }

    // MARK: 字体（标题宋体衬线 / 正文圆体）
    static func roundedFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    var displayFont: Font { .system(size: 34, weight: .semibold, design: .serif) }
    var title1Font: Font { .system(size: 28, weight: .semibold, design: .serif) }
    var title2Font: Font { .system(size: 22, weight: .semibold, design: .serif) }
    var title3Font: Font { .system(size: 20, weight: .semibold, design: .serif) }
    var headlineFont: Font { .system(size: 17, weight: .semibold, design: .rounded) }
    var bodyFont: Font { .system(size: 17, weight: .regular, design: .rounded) }
    var subheadFont: Font { .system(size: 15, weight: .regular, design: .rounded) }
    var footnoteFont: Font { .system(size: 13, weight: .regular, design: .rounded) }
    var captionFont: Font { .system(size: 12, weight: .medium, design: .rounded) }
    var quoteFont: Font { .system(size: 19, weight: .regular, design: .serif) }

    // MARK: 动效常量
    static let entranceDuration: Double = 0.5
    static let ctaPulseDuration: Double = 4.2
    static let avatarBreathDuration: Double = 4.2
    static let sonarDuration: Double = 4.0
    static let haloBreathDuration: Double = 5.0
    static let buttonSpring = Animation.spring(response: 0.35, dampingFraction: 0.64)
    static let buttonMinimumHeight: CGFloat = 44

    // MARK: 展示名映射（默认角色保留参考壳的"小猫"公开名称，其他角色用公共名称）
    static func displayName(for profile: DVKCompanionProfile) -> String {
        profile.id == "mock.gentle-cat" ? "小猫" : profile.displayName
    }
    static func introCopy(for profile: DVKCompanionProfile) -> String {
        profile.id == "mock.gentle-cat" ? "和小猫说说话" : "和\(profile.displayName)说说话"
    }
    static func chatTitle(for profile: DVKCompanionProfile) -> String {
        profile.id == "mock.gentle-cat" ? "小猫" : profile.displayName
    }
}

// MARK: - 触摸反馈（参考壳触觉，UIKit 条件编译；Linux 测试目标下为空实现）
@MainActor
enum DVKCatHaptics {
    static func comfort() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
    static func action() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

// MARK: - 卡片顶部高光（参考壳 1px 白色顶部高光）
extension View {
    func dvkCatCardTopHighlight(height: CGFloat = 1.2) -> some View {
        overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 按压弹簧按钮样式（参考壳 cubic-bezier(.34,1.56,.64,1)）
struct DVKCatPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.64),
                value: configuration.isPressed
            )
    }
}

// MARK: - 可点击卡片按压样式
struct DVKCatPressableCardStyle: ButtonStyle {
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

// MARK: - 头像角色风格
enum DVKCatAvatarStyle {
    case auto
    case portrait
    case thumbnail
}

// MARK: - 隐私头像 / 人物容器（参考壳 PrivacyAvatar 移植）
// 默认角色使用已获授权的 AI 人物图（portrait 2:3 完整形象 / thumbnail 方形缩略图），
// 其他公共角色使用程序化人物作为 fallback；隐私受限时保持模糊并锁定。
struct DVKCatAvatarView: View {
    let profile: DVKCompanionProfile
    var size: CGFloat = 96
    var style: DVKCatAvatarStyle = .auto
    var revealed: Bool = true
    var onTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var requestedUnlock = false
    @State private var unlockFlash = false
    @State private var unlockTask: Task<Void, Never>?

    private var isPortraitCat: Bool { profile.id == "mock.gentle-cat" }
    private let portraitThreshold: CGFloat = 100

    private var resolvedStyle: DVKCatAvatarStyle {
        switch style {
        case .auto:
            return isPortraitCat && size >= portraitThreshold ? .portrait : .thumbnail
        case .portrait:
            return isPortraitCat ? .portrait : .thumbnail
        case .thumbnail:
            return .thumbnail
        }
    }

    var body: some View {
        ZStack {
            if isPortraitCat {
                switch resolvedStyle {
                case .portrait:
                    portraitCharacter(revealed: revealed)
                case .thumbnail, .auto:
                    thumbnailCharacter(revealed: revealed)
                }
            } else {
                programmaticCharacter(revealed: revealed)
            }

            if !revealed || requestedUnlock || unlockFlash {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xF7DDD6).opacity(unlockFlash ? 0.20 : 0.35))
                    Image(systemName: revealed && (requestedUnlock || unlockFlash) ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: resolvedStyle == .portrait ? size * 0.16 : size * 0.22, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFFF9F6))
                        .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 2)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(
                    width: size,
                    height: resolvedStyle == .portrait ? size * 3.0 / 2.0 : size
                )
                .clipShape(RoundedRectangle(cornerRadius: DVKCatStyle.Radius.large, style: .continuous))
                .transition(.opacity)
                .accessibilityLabel("头像已模糊保护，轻触解锁")
                .accessibilityHidden(revealed)
            }
        }
        .shadow(
            color: Color(hex: 0xD9486B).opacity(0.08),
            radius: resolvedStyle == .portrait ? size * 0.06 : size * 0.08,
            x: 0,
            y: size * 0.04
        )
        .contentShape(RoundedRectangle(cornerRadius: DVKCatStyle.Radius.large, style: .continuous))
        .allowsHitTesting(onTap != nil)
        .onTapGesture {
            guard let onTap else { return }
            DVKCatHaptics.action()
            if !revealed {
                requestedUnlock = true
                onTap()
            }
        }
        .onChange(of: revealed) { _, newValue in
            guard newValue, requestedUnlock, onTap != nil else {
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
            withAnimation(.easeOut(duration: 0.18)) { unlockFlash = true }
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

    /// Portrait 完整形象：2:3 自然比例 + 底部柔边渐隐，与 halo 融合
    private func portraitCharacter(revealed: Bool) -> some View {
        let width = size
        let height = size * 3.0 / 2.0
        return Image("DVKCatPortrait", bundle: .module)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
            .blur(radius: revealed ? 0 : 6)
            .opacity(revealed ? 1 : 0.92)
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

    /// Thumbnail 方形小头像：径向柔边遮罩
    private func thumbnailCharacter(revealed: Bool) -> some View {
        Image("DVKCatAvatar", bundle: .module)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .blur(radius: revealed ? 0 : 6)
            .opacity(revealed ? 1 : 0.92)
            .clipShape(RoundedRectangle(cornerRadius: DVKCatStyle.Radius.large, style: .continuous))
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

    /// 程序化 Mock 猫 fallback（非默认角色）
    private func programmaticCharacter(revealed: Bool) -> some View {
        DVKCharacterPresentationView(
            profile: profile,
            state: .idle,
            reduceMotion: true,
            staticMode: true,
            host: nil
        )
        .frame(width: size, height: size)
        .blur(radius: revealed ? 0 : 5)
        .opacity(revealed ? 1 : 0.92)
        .animation(.easeInOut(duration: 0.35), value: revealed)
    }
}

// MARK: - 隐私确认浮层（参考壳 AvatarPrivacyConfirmView 移植，接公共隐私状态）
struct DVKCatPrivacyConfirmView: View {
    var onAgree: () -> Void
    var onDecline: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: 0xFDF5F1).opacity(0.96)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 18) {
                Text("是否同意与该 AI 形象建立陪伴关系？")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(hex: 0x432B33))
                    .multilineTextAlignment(.center)

                Text("这是一段轻量的虚拟陪伴关系。该形象由授权素材或原创设计生成，仅在通话时使用，不会用于商业推广。")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Color(hex: 0x8A6B72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                VStack(alignment: .leading, spacing: 8) {
                    Text("查看形象即表示同意：")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Color(hex: 0x432B33))
                    Text("· 你看到的形象，来自授权素材或原创设计")
                    Text("· 通话中可能存在「被理解」的主观感受，但本质仍是 AI")
                    Text("· 你可以随时在「我的 - 隐私」关闭形象显示")
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: 0x8A6B72))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(hex: 0xFBEBE2), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                HStack(spacing: 12) {
                    Button {
                        DVKCatHaptics.action()
                        dismiss()
                        onDecline()
                    } label: {
                        Text("暂不同意")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x432B33))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white, in: Capsule())
                            .overlay(Capsule().stroke(Color(hex: 0xF7DDD6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacy.confirm.decline")

                    Button {
                        DVKCatHaptics.success()
                        dismiss()
                        onAgree()
                    } label: {
                        Text("同意并查看")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(hex: 0xD9486B), in: Capsule())
                            .shadow(color: Color(hex: 0xD9486B).opacity(0.30), radius: 10, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacy.confirm.agree")
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(hex: 0x432B33).opacity(0.16), radius: 32, x: 0, y: 12)
            .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("privacy.confirm.overlay")
    }
}

// MARK: - 圆环光晕（参考壳 RingHaloView 移植）
struct DVKCatRingHalo: View {
    var intensity: Double = 0.5
    var diameter: CGFloat = 240
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        let style = DVKCatStyle(theme: DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile))
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            style.primary.opacity(0.32 * intensity),
                            style.primary.opacity(0.10 * intensity),
                            .clear
                        ],
                        center: .center,
                        startRadius: diameter * 0.25,
                        endRadius: diameter * 0.62
                    )
                )
                .frame(width: diameter * 1.25, height: diameter * 1.25)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [style.primary100, style.primary, style.primary600],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: style.orbShadow, radius: 12, x: 0, y: 0)

            Circle()
                .stroke(style.primary100.opacity(0.85), lineWidth: 2)
                .frame(width: diameter - 22, height: diameter - 22)

            Circle()
                .fill(style.primarySoft.opacity(0.55))
                .frame(width: diameter - 34, height: diameter - 34)
        }
        .scaleEffect(reduceMotion ? 1 : (breathing ? 1.02 : 0.98))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
            value: breathing
        )
        .onAppear { breathing = true }
        .accessibilityHidden(true)
    }
}

// MARK: - 语音波形（参考壳 VoiceWaveform 移植，真实 playbackAmplitude 驱动）
struct DVKCatVoiceWaveform: View {
    let active: Bool
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 24
    private let minBarHeight: CGFloat = 4
    private let maxBarHeightRatio: CGFloat = 0.92

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width / CGFloat(barCount) * 0.4
            let spacing = (geo.size.width - barWidth * CGFloat(barCount)) / CGFloat(barCount - 1)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(barColor(i))
                        .frame(width: barWidth, height: barHeight(i, geo: geo))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ i: Int, geo: GeometryProxy) -> CGFloat {
        let maxH = geo.size.height
        guard active else { return minBarHeight }
        let clamped = min(max(level, 0.0), 1.0)
        let variation = 0.72 + 0.28 * sin(Double(i) * 1.7)
        let target = maxH * CGFloat(clamped) * CGFloat(variation) * maxBarHeightRatio
        return min(max(target, minBarHeight), maxH)
    }

    private func barColor(_ i: Int) -> Color {
        let style = DVKCatStyle(theme: DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile))
        guard active else { return style.textTertiary.opacity(0.30) }
        let depth = Double(i % 5) / 5.0
        return Color(
            red: 0.85 + depth * 0.05,
            green: 0.45 - depth * 0.08,
            blue: 0.55 - depth * 0.10
        )
    }
}

// MARK: - 微型动态波形（参考壳 MiniVoiceWave 移植，装饰用途）
struct DVKCatMiniWave: View {
    let active: Bool
    let color: Color
    let reduceMotion: Bool
    var barCount: Int = 5
    @State private var phase = false

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width / CGFloat(barCount) * 0.42
            let spacing = (geo.size.width - barWidth * CGFloat(barCount)) / CGFloat(barCount - 1)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(color.opacity(active ? 0.85 : 0.30))
                        .frame(width: barWidth, height: barHeight(i, geo: geo))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: phase)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            guard active && !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.12)) { phase = true }
            let timer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { _ in
                withAnimation(.easeOut(duration: 0.12)) { phase.toggle() }
            }
            RunLoop.main.add(timer, forMode: .common)
            miniWaveTimer = timer
        }
        .onDisappear {
            miniWaveTimer?.invalidate()
            miniWaveTimer = nil
        }
    }

    @State private var miniWaveTimer: Timer?

    private func barHeight(_ i: Int, geo: GeometryProxy) -> CGFloat {
        guard active else { return geo.size.height * 0.3 }
        let maxH = geo.size.height
        let amplitudes: [CGFloat] = [0.55, 0.95, 0.4, 1.0, 0.7, 0.85, 0.5, 0.9, 0.62, 0.78]
        let base = amplitudes[i % amplitudes.count]
        let pulse = phase ? 1.0 : 0.65
        return maxH * base * pulse
    }
}
#endif
