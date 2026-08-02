#if canImport(SwiftUI)
import SwiftUI

public enum DVKIOS26GlassStyle: Sendable {
    case regular
    case prominent
}

public struct DVKIOS26GlassAccessibilityPolicy: Equatable, Sendable {
    public let usesOpaqueFallback: Bool
    public let allowsInteractiveGlass: Bool

    public init(reduceTransparency: Bool, reduceMotion: Bool) {
        usesOpaqueFallback = reduceTransparency
        allowsInteractiveGlass = !reduceTransparency && !reduceMotion
    }
}

@available(iOS 17.0, *)
public struct DVKIOS26GlassControlModifier: ViewModifier {
    let theme: DVKCompanionTheme
    let style: DVKIOS26GlassStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func body(content: Content) -> some View {
        let policy = DVKIOS26GlassAccessibilityPolicy(reduceTransparency: reduceTransparency, reduceMotion: reduceMotion)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !policy.usesOpaqueFallback {
            if style == .prominent {
                content.buttonStyle(.glassProminent)
            } else if policy.allowsInteractiveGlass {
                content.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                content.glassEffect(.regular, in: .capsule)
            }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        if style == .prominent {
            content
                .buttonStyle(.borderedProminent)
                .foregroundStyle(theme.textOnAction)
                .background(theme.primaryAction, in: Capsule())
        } else {
            content
                .buttonStyle(.bordered)
                .foregroundStyle(theme.textPrimary)
                .background(theme.surface, in: Capsule())
        }
    }
}

@available(iOS 17.0, *)
public struct DVKIOS26GlassSurfaceModifier: ViewModifier {
    let theme: DVKCompanionTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func body(content: Content) -> some View {
        let policy = DVKIOS26GlassAccessibilityPolicy(reduceTransparency: reduceTransparency, reduceMotion: false)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !policy.usesOpaqueFallback {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            content.background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        #else
        content.background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        #endif
    }
}

@available(iOS 17.0, *)
public struct DVKIOS26GlassEffectContainer<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

@available(iOS 17.0, *)
public struct DVKIOS26NavigationChromeModifier: ViewModifier {
    let theme: DVKCompanionTheme

    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
        } else {
            content.toolbarBackground(theme.navigationSurface, for: .navigationBar)
        }
        #else
        content.toolbarBackground(theme.navigationSurface, for: .navigationBar)
        #endif
    }
}

@available(iOS 17.0, *)
public struct DVKIOS26TabBarModifier: ViewModifier {
    let theme: DVKCompanionTheme

    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content.toolbarBackground(theme.tabSurface, for: .tabBar)
        }
        #else
        content.toolbarBackground(theme.tabSurface, for: .tabBar)
        #endif
    }
}

@available(iOS 17.0, *)
public extension View {
    func dvkGlassControl(theme: DVKCompanionTheme, prominent: Bool = false) -> some View {
        modifier(DVKIOS26GlassControlModifier(theme: theme, style: prominent ? .prominent : .regular))
    }

    func dvkGlassSurface(theme: DVKCompanionTheme) -> some View {
        modifier(DVKIOS26GlassSurfaceModifier(theme: theme))
    }

    func dvkIOS26NavigationChrome(theme: DVKCompanionTheme) -> some View {
        modifier(DVKIOS26NavigationChromeModifier(theme: theme))
    }

    func dvkIOS26TabBar(theme: DVKCompanionTheme) -> some View {
        modifier(DVKIOS26TabBarModifier(theme: theme))
    }
}
#endif
