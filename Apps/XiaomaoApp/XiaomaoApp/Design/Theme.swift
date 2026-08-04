import SwiftUI
import UIKit

// MARK: - v6.1 设计令牌系统 (西柚玫瑰活力版)
// v6.1 设计令牌: 主色 #D9486B 西柚玫瑰, 桃粉白底 #FDF5F1,
// 深莓果文字 #432B33, 标题宋体衬线. 保留 v3 兼容成员名 (primary100/primary500/...)
// 使已有页面引用自动跟随换色, 无需逐个改动.

enum Theme {
    // MARK: 布局
    static let spacing: CGFloat = Spacing.medium
    static let cornerRadius: CGFloat = Radius.medium

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
        static let small: CGFloat = 12     // v6.1 --radius-sm
        static let medium: CGFloat = 16    // --radius-md
        static let large: CGFloat = 22     // --radius-lg
        static let xLarge: CGFloat = 28    // --radius-xl
        static let card: CGFloat = 22
        static let characterCard: CGFloat = 28
        static let pill: CGFloat = 999
    }

    // MARK: 主色 — 西柚玫瑰 (v6.1)
    static let primary = Color(hex: 0xD9486B)          // --color-primary 西柚玫瑰
    static let primaryHover = Color(hex: 0xC2405F)     // --color-primary-hover
    static let primaryPressed = Color(hex: 0xA83852)   // --color-primary-pressed
    static let primarySoft = Color(hex: 0xFBE0E6)      // --color-primary-soft 软衬底/chip
    static let onPrimary = Color(hex: 0xFFFFFF)        // --color-on-primary

    // MARK: 主色层次 (兼容 v3 命名)
    static let primary100 = primarySoft
    static let primary300 = Color(hex: 0xE88BA0)       // 中浅玫瑰 (渐变端点)
    static let primary500 = primary
    static let primary600 = primaryHover
    static let primary700 = primaryPressed
    static let primary800 = Color(hex: 0x8E2F45)       // 更深强调
    static let primaryLight = primary100
    static let primaryDeep = primary600
    static let primaryDeep2 = primary700

    // MARK: 底色 — 桃粉白 (v6.1)
    static let bg = Color(hex: 0xFDF5F1)               // --color-bg 桃粉白底
    static let bgElevated = Color(hex: 0xFFF9F6)       // --color-bg-elevated
    static let halo = Color(hex: 0xF7DDD6)             // --color-halo
    static let haloGlow = Color(hex: 0xF0BCB0)         // --color-halo-glow
    static let surface = Color(hex: 0xFFFFFF)          // 卡片表面
    static let surfaceWarm = Color(hex: 0xFBEBE2)      // 暖色卡片底 (--color-role-soft)
    static let border = Color(hex: 0xF7DDD6)           // 分隔线 (halo)

    // MARK: 文字 — 深莓果 (v6.1)
    static let textPrimary = Color(hex: 0x432B33)      // --color-text-primary 深莓果
    static let textSecondary = Color(hex: 0x8A6B72)    // --color-text-secondary
    static let textTertiary = Color(hex: 0xB99CA2)     // --color-text-tertiary
    static let textLink = Color(hex: 0xC24467)         // --color-text-link
    static let textOnHalo = Color(hex: 0xFFF9F6)       // --color-text-on-halo

    // MARK: 角色三色 (v6.1)
    static let roleGold = Color(hex: 0xD9486B)         // 西柚玫瑰 (v6.1 定稿 --color-role-gold: #D9486B, warm 角色主色)
    static let roleBlush = Color(hex: 0xF4A7B8)        // 樱 (治愈少女 halo)
    static let roleCaramel = Color(hex: 0xA26A48)      // 可可 (沉稳大叔 halo)
    static let roleSoft = Color(hex: 0xFBEBE2)

    // MARK: 语义色 (v6.1)
    static let success = Color(hex: 0x71A36B)
    static let warning = Color(hex: 0xD9486B)
    static let danger = Color(hex: 0xD5563C)           // 结束通话/解除关系
    static let info = Color(hex: 0x93A9BC)
    static let online = Color(hex: 0x8FBC86)           // 在线绿点
    static let offline = Color(hex: 0xCDB6B0)
    static let recording = Color(hex: 0xD5563C)
    static let voiceActive = Color(hex: 0xE88BA0)      // 语音波形活跃柱

    // MARK: 角色冷调 — 灵猫少年 (保留, 用于角色装饰)
    static let characterHair = Color(hex: 0x2B2320)
    static let characterHairHighlight = Color(hex: 0x4A3E38)
    static let characterRobe = Color(hex: 0x4A5568)
    static let characterRobeLight = Color(hex: 0x5D6B7E)
    static let characterRobeDark = Color(hex: 0x39424F)
    static let characterSkin = Color(hex: 0xF5CFB0)
    static let characterSkinShadow = Color(hex: 0xE8B694)
    static let characterEarInner = Color(hex: 0xF4A8B8)

    // MARK: 兼容辅助色 (v3 旧引用)
    static let accentSuccess = success
    static let accentWarning = warning
    static let accentError = danger
    static let accentInfo = info

    // MARK: 兼容成员 (旧代码引用)
    static let pageBackground = bg
    static let primarySurface = surface
    static let secondarySurface = surfaceWarm
    static let primaryAction = primary500
    static let neutral = info
    static let userMessageSurface = primary500.opacity(0.14)
    static let assistantMessageSurface = surfaceWarm
    static let bgPrimary = bg
    static let bgSurface = surface
    static let bgSubtle = surfaceWarm
    static let borderSubtle = border
    static let error = danger
    static let charWarm = roleGold
    static let charWarmBg = roleSoft
    static let charSakura = roleBlush
    static let charCaramel = roleCaramel

    // MARK: 角色变体渐变 (v6.1)
    static let charWarmGradient = LinearGradient(
        colors: [Color(hex: 0xE46A83), Color(hex: 0xC2405F)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let charSakuraGradient = LinearGradient(
        colors: [Color(hex: 0xF6BECB), Color(hex: 0xE28CA1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let charCaramelGradient = LinearGradient(
        colors: [Color(hex: 0xC08A60), Color(hex: 0xA26A48)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: 背景渐变 (v6.1 桃粉白)
    static let callBackground = LinearGradient(
        colors: [bg, Color(hex: 0xF9E0E2), bgElevated],
        startPoint: .top,
        endPoint: .bottom
    )

    static let homeBackground = LinearGradient(
        colors: [bg, Color(hex: 0xFDF2F0), bgElevated],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: 阴影体系 (v6.1 玫瑰色)
    static let shadowRaised = Color(hex: 0xD9486B).opacity(0.08)
    static let shadowFloating = Color(hex: 0xD9486B).opacity(0.12)
    static let shadowOverlay = Color(hex: 0x432B33).opacity(0.16)
    static let shadowGlow = Color(hex: 0xFAC8D2).opacity(0.50)

    // MARK: 主视觉光晕 (P2.7B)
    // 首页/通话页中央完整形象底部光斑, 与 portrait 渐隐融合 (“人像融入光里”)
    static let heroGlow = Color(hex: 0xFAC8D2).opacity(0.55)


    // MARK: 机物渐变背景色 (P2.7B-FINAL-VISUAL-FIX)
    // 降低 Mesh 纵向色带, 中心暖白 + 边缘暖色, 灰蓝作为单一呼应点.
    static let meshWarmWhite   = Color(hex: 0xFFFAF6)  // 暖白 (Central)
    static let meshPeach       = Color(hex: 0xFCE8EC)  // 桃粉白
    static let meshRose        = Color(hex: 0xF6C3CF)  // 樱粉/西暘玫瑰
    static let meshCoolAccent  = Color(hex: 0xE7E9ED)  // 低饱和灰蓝 (呼应衣袆)
    // MARK: 兼容阴影 (v3 旧引用)
    static let softShadow = shadowRaised
    static let ctaShadow = primary600.opacity(0.30)
    static let orbShadow = primary500.opacity(0.25)

    // MARK: 字体 (v6.1: 标题宋体衬线, 正文 SF Pro Rounded)
    static func roundedFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static let displayFont = Font.system(size: 34, weight: .semibold, design: .serif)     // 页面大标题 (宋体)
    static let title1Font = Font.system(size: 28, weight: .semibold, design: .serif)      // 角色页标题
    static let title2Font = Font.system(size: 22, weight: .semibold, design: .serif)      // 卡片标题
    static let title3Font = Font.system(size: 20, weight: .semibold, design: .serif)      // 区块标题
    static let headlineFont = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let bodyFont = Font.system(size: 17, weight: .regular, design: .rounded)
    static let subheadFont = Font.system(size: 15, weight: .regular, design: .rounded)
    static let footnoteFont = Font.system(size: 13, weight: .regular, design: .rounded)
    static let captionFont = Font.system(size: 12, weight: .medium, design: .rounded)
    static let quoteFont = Font.system(size: 19, weight: .regular, design: .serif)        // 治愈语录衬线

    // MARK: 动效常量 (v6.1)
    static let entranceDuration: Double = 0.5           // 屏内入场仪式
    static let ctaPulseDuration: Double = 4.2           // CTA 待机呼吸脉冲
    static let avatarBreathDuration: Double = 4.2       // 头像呼吸
    static let sonarDuration: Double = 4.0              // 状态点声呐
    static let haloBreathDuration: Double = 5.0         // haloBreathe halo opacity/scale breath
    static let haloSweepDuration: Double = 14.0         // haloSweep single faint conic sweep
    static let bgLightDuration: Double = 14.0           // bgLight background glow breath
    static let pulseDotDuration: Double = 2.4           // pulseDot online dot blink
    static let buttonSpring = Animation.spring(response: 0.35, dampingFraction: 0.64)

    // MARK: 可访问性
    static let buttonMinimumHeight: CGFloat = 44
    static let controlMinimumSize: CGFloat = 44
}

// MARK: - Hex 扩展
extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - 通用修饰符
extension View {
    func warmCard(cornerRadius: CGFloat = Theme.Radius.large) -> some View {
        self
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.shadowRaised, radius: 12, x: 0, y: 2)
    }

    func warmCardFloating(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.shadowFloating, radius: 20, x: 0, y: 8)
    }

    func warmBackground(_ gradient: LinearGradient = Theme.homeBackground) -> some View {
        self.background(gradient.ignoresSafeArea())
    }

    /// v6.1 card material: 1px white top highlight (HTML .card inset 0 1px rgba(255,255,255,.55))
    func cardTopHighlight(height: CGFloat = 1.2) -> some View {
        self.overlay(alignment: .top) {
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

// MARK: - 触觉反馈 (设计 §9.1)
enum WarmHaptics {
    static func comfort() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    static func action() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func lowMood() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
