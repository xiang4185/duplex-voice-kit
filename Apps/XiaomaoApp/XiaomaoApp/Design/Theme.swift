import SwiftUI
import UIKit

// MARK: - v6.2 设计令牌系统 (西柚玫瑰清晰版)
// v6.2 设计令牌: 主色 #C83B5D 西柚玫瑰, 桃粉白底 #FDF5F1,
// 深莓果文字 #432B33, 标题宋体衬线. 保留 v3 兼容成员名 (primary100/primary500/...)
// 在保留陪伴感的同时提升小字号文字和主操作对比度.

enum Theme {
    private static func adaptive(light: UInt32, dark: UInt32, opacity: Double = 1) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return UIColor(red: r, green: g, blue: b, alpha: opacity)
        })
    }

    struct VisualTokens {
        let background: Color
        let backgroundElevated: Color
        let surface: Color
        let surfaceSoft: Color
        let glassTint: Color
        let primary: Color
        let primarySoft: Color
        let danger: Color
        let dangerSoft: Color
        let onPrimary: Color
        let textPrimary: Color
        let textSecondary: Color
        let textTertiary: Color
        let border: Color
        let shadow: Color
        let halo: Color
        let heroGlow: Color
        let meshWarmWhite: Color
        let meshPeach: Color
        let meshRose: Color
        let meshCoolAccent: Color
    }

    static func visual(_ mode: AppVisualMode) -> VisualTokens {
        switch mode {
        case .warm:
            return VisualTokens(
                background: bg,
                backgroundElevated: bgElevated,
                surface: surface,
                surfaceSoft: surfaceWarm,
                glassTint: Color.white.opacity(0.34),
                primary: primary,
                primarySoft: primarySoft,
                danger: danger,
                dangerSoft: Color(hex: 0xFCE6E0),
                onPrimary: onPrimary,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                textTertiary: textTertiary,
                border: border,
                shadow: shadowRaised,
                halo: halo,
                heroGlow: heroGlow,
                meshWarmWhite: meshWarmWhite,
                meshPeach: meshPeach,
                meshRose: meshRose,
                meshCoolAccent: meshCoolAccent
            )
        case .mystery:
            return VisualTokens(
                background: Color(hex: 0x0D0F16),
                backgroundElevated: Color(hex: 0x121520),
                surface: Color(hex: 0x171923),
                surfaceSoft: Color(hex: 0x1C1E2A),
                glassTint: Color(hex: 0x181A25).opacity(0.88),
                primary: Color(hex: 0xC9C5DE),
                primarySoft: Color(hex: 0x292738),
                danger: Color(hex: 0xC78395),
                dangerSoft: Color(hex: 0x3A242D),
                onPrimary: Color(hex: 0x11121A),
                textPrimary: Color(hex: 0xF1EFF7),
                textSecondary: Color(hex: 0xADA8BA),
                textTertiary: Color(hex: 0x777482),
                border: Color(hex: 0x343140),
                shadow: Color.black.opacity(0.36),
                halo: Color(hex: 0x4A465F),
                heroGlow: Color(hex: 0x746D91).opacity(0.18),
                meshWarmWhite: Color(hex: 0x0E1018),
                meshPeach: Color(hex: 0x141622),
                meshRose: Color(hex: 0x1B1B2A),
                meshCoolAccent: Color(hex: 0x111827)
            )
        }
    }

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

    enum Motion {
        static let quick: Double = 0.20
        static let standard: Double = 0.35
        static let slow: Double = 0.60
        static let ambientWarm: Double = 20
        static let ambientMystery: Double = 28
    }

    // MARK: 主色 — 西柚玫瑰 (v6.2 AA 对比度)
    static let primary = adaptive(light: 0xC83B5D, dark: 0xC9C5DE)          // 白字对比度 4.95:1
    static let primaryHover = adaptive(light: 0xB93453, dark: 0xB8B3D2)
    static let primaryPressed = adaptive(light: 0x9F2E48, dark: 0xE2DEEF)
    static let primarySoft = adaptive(light: 0xF8E4E9, dark: 0x292738)
    static let onPrimary = adaptive(light: 0xFFFFFF, dark: 0x11121A)        // --color-on-primary

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
    static let bg = adaptive(light: 0xFDF5F1, dark: 0x0D0F16)
    static let bgElevated = adaptive(light: 0xFFF9F6, dark: 0x121520)
    static let halo = adaptive(light: 0xF7DDD6, dark: 0x4A465F)
    static let haloGlow = adaptive(light: 0xF0BCB0, dark: 0x5E5877)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x171923)
    static let surfaceWarm = adaptive(light: 0xFBEBE2, dark: 0x1C1E2A)
    static let border = adaptive(light: 0xF7DDD6, dark: 0x343140)

    // MARK: 文字 — 深莓果 (v6.1)
    static let textPrimary = adaptive(light: 0x432B33, dark: 0xF1EFF7)
    static let textSecondary = adaptive(light: 0x765A62, dark: 0xBEB9C9)
    static let textTertiary = adaptive(light: 0x82636B, dark: 0x9692A1)
    static let textLink = adaptive(light: 0xB93453, dark: 0xD6D2E5)
    static let textOnHalo = adaptive(light: 0xFFF9F6, dark: 0xF1EFF7)

    // MARK: 角色三色 (v6.1)
    static let roleGold = Color(hex: 0xC83B5D)         // 西柚玫瑰 (warm 角色主色)
    static let roleBlush = Color(hex: 0xF4A7B8)        // 樱 (治愈少女 halo)
    static let roleCaramel = Color(hex: 0xA26A48)      // 可可 (沉稳大叔 halo)
    static let roleSoft = Color(hex: 0xFBEBE2)

    // MARK: 语义色 (v6.1)
    static let success = Color(hex: 0x71A36B)
    static let warning = adaptive(light: 0xB45B30, dark: 0xC99A76)
    static let danger = adaptive(light: 0xD5563C, dark: 0xC78395)           // 结束通话/解除关系
    static let info = adaptive(light: 0x5D7184, dark: 0xA9B8C7)
    static let online = adaptive(light: 0x557F50, dark: 0x9AC695)           // 在线绿点
    static let offline = Color(hex: 0xCDB6B0)
    static let recording = adaptive(light: 0xD5563C, dark: 0xC78395)
    static let voiceActive = adaptive(light: 0xE88BA0, dark: 0xA49EC0)      // 语音波形活跃柱

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
    static let shadowRaised = adaptive(light: 0xD9486B, dark: 0x000000, opacity: 0.08)
    static let shadowFloating = adaptive(light: 0xD9486B, dark: 0x000000, opacity: 0.12)
    static let shadowOverlay = adaptive(light: 0x432B33, dark: 0x000000, opacity: 0.18)
    static let shadowGlow = adaptive(light: 0xFAC8D2, dark: 0x8C84A8, opacity: 0.32)

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
