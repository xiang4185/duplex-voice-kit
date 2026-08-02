#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

public struct DVKCompanionTheme {
    public let pageBackground: Color
    public let backgroundGradient: LinearGradient
    public let surface: Color
    public let elevatedSurface: Color
    public let navigationSurface: Color
    public let tabSurface: Color
    public let border: Color
    public let primaryAction: Color
    public let secondaryAction: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textOnAction: Color
    public let userMessageSurface: Color
    public let assistantMessageSurface: Color
    public let halo: Color
    public let selectedState: Color
    public let shadow: Color
    public let activeStatus: Color
    public let isDark: Bool

    public init(pageBackground: Color, backgroundGradient: LinearGradient, surface: Color, elevatedSurface: Color, navigationSurface: Color, tabSurface: Color, border: Color, primaryAction: Color, secondaryAction: Color, textPrimary: Color, textSecondary: Color, textOnAction: Color, userMessageSurface: Color, assistantMessageSurface: Color, halo: Color, selectedState: Color, shadow: Color, activeStatus: Color, isDark: Bool) {
        self.pageBackground=pageBackground; self.backgroundGradient=backgroundGradient; self.surface=surface; self.elevatedSurface=elevatedSurface; self.navigationSurface=navigationSurface; self.tabSurface=tabSurface; self.border=border; self.primaryAction=primaryAction; self.secondaryAction=secondaryAction; self.textPrimary=textPrimary; self.textSecondary=textSecondary; self.textOnAction=textOnAction; self.userMessageSurface=userMessageSurface; self.assistantMessageSurface=assistantMessageSurface; self.halo=halo; self.selectedState=selectedState; self.shadow=shadow; self.activeStatus=activeStatus; self.isDark=isDark
    }
}

public enum DVKCompanionThemeResolver {
    public static func resolve(themeKey: DVKCompanionProfileThemeKey?, appearance: DVKCompanionAppearance) -> DVKCompanionTheme {
        let key = themeKey ?? .warmCreamRose
        let profile = DVKCompanionProfileCatalog().profiles.first { $0.themeKey == key }
        return resolve(profile: profile, appearance: appearance)
    }

    public static func resolve(profile: DVKCompanionProfile?, appearance: DVKCompanionAppearance) -> DVKCompanionTheme {
        let key = profile?.themeKey ?? .warmCreamRose
        let dark = appearance == .dark || (appearance == .followProfile && key == .lavenderNight)
        switch key {
        case .warmCreamRose: return make(accent: Color(hex:0xD9486B), soft: Color(hex:0xFBE0E6), lightPage: Color(hex:0xFDF5F1), darkPage: Color(hex:0x24171D), dark: dark)
        case .coralGold: return make(accent: Color(hex:0xD95F3F), soft: Color(hex:0xFFE4D5), lightPage: Color(hex:0xFFF5EC), darkPage: Color(hex:0x281A16), dark: dark)
        case .mistBlue: return make(accent: Color(hex:0x557E99), soft: Color(hex:0xDDECF3), lightPage: Color(hex:0xF1F7FA), darkPage: Color(hex:0x17232B), dark: dark)
        case .lavenderNight: return make(accent: Color(hex:0xA58BC4), soft: Color(hex:0xE8DDF4), lightPage: Color(hex:0xF7F1FC), darkPage: Color(hex:0x171323), dark: dark)
        }
    }

    private static func make(accent: Color, soft: Color, lightPage: Color, darkPage: Color, dark: Bool) -> DVKCompanionTheme {
        let page = dark ? darkPage : lightPage
        let surface = dark ? Color(hex:0x29212D) : Color.white
        let elevated = dark ? Color(hex:0x33283A) : Color(hex:0xFFF9F6)
        let nav = dark ? Color(hex:0x211A28) : Color.white.opacity(0.92)
        let tab = dark ? Color(hex:0x1C1722) : Color.white.opacity(0.96)
        let text = dark ? Color(hex:0xFFF7FC) : Color(hex:0x432B33)
        let secondary = dark ? Color(hex:0xC9B9CC) : Color(hex:0x806A73)
        let border = dark ? accent.opacity(0.5) : accent.opacity(0.18)
        let gradient = LinearGradient(colors: [page, dark ? accent.opacity(0.16) : soft.opacity(0.52), page], startPoint: .topLeading, endPoint: .bottomTrailing)
        return DVKCompanionTheme(pageBackground: page, backgroundGradient: gradient, surface: surface, elevatedSurface: elevated, navigationSurface: nav, tabSurface: tab, border: border, primaryAction: accent, secondaryAction: soft, textPrimary: text, textSecondary: secondary, textOnAction: dark ? Color.black : Color.white, userMessageSurface: dark ? accent.opacity(0.42) : soft, assistantMessageSurface: surface, halo: accent.opacity(dark ? 0.42 : 0.22), selectedState: accent, shadow: accent.opacity(dark ? 0.28 : 0.16), activeStatus: dark ? Color(hex:0x8EE0B5) : Color(hex:0x2D9B68), isDark: dark)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
#endif
