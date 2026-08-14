import SwiftUI

private struct AppVisualModeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppVisualMode = .warm
}

private struct CompanionTypeEnvironmentKey: EnvironmentKey {
    static let defaultValue: CompanionType = .warm
}

extension EnvironmentValues {
    var appVisualMode: AppVisualMode {
        get { self[AppVisualModeEnvironmentKey.self] }
        set { self[AppVisualModeEnvironmentKey.self] = newValue }
    }

    var companionType: CompanionType {
        get { self[CompanionTypeEnvironmentKey.self] }
        set { self[CompanionTypeEnvironmentKey.self] = newValue }
    }
}

struct SurfaceCard<Content: View>: View {
    @Environment(\.appVisualMode) private var visualMode
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let tokens = Theme.visual(visualMode)
        content
            .background(
                tokens.surface.opacity(visualMode == .mystery ? 0.96 : 1),
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(tokens.border.opacity(visualMode == .mystery ? 0.82 : 0.62), lineWidth: 0.7)
            }
            .shadow(color: tokens.shadow, radius: visualMode == .mystery ? 18 : 14, x: 0, y: 5)
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.appVisualMode) private var visualMode
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let tokens = Theme.visual(visualMode)
        content
            .background(tokens.glassTint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(tokens.border.opacity(visualMode == .mystery ? 0.88 : 0.48), lineWidth: 0.7)
            }
            .shadow(color: tokens.shadow, radius: visualMode == .mystery ? 20 : 16, x: 0, y: 6)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String?
    var avatarSize: CGFloat = 42

    @Environment(\.appVisualMode) private var visualMode

    init(_ title: String, subtitle: String? = nil, avatarSize: CGFloat = 42) {
        self.title = title
        self.subtitle = subtitle
        self.avatarSize = avatarSize
    }

    var body: some View {
        let tokens = Theme.visual(visualMode)
        HStack(spacing: 12) {
            PrivacyAvatar(size: avatarSize, tappable: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.headlineFont)
                    .foregroundStyle(tokens.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.captionFont)
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String?

    @Environment(\.appVisualMode) private var visualMode

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        let tokens = Theme.visual(visualMode)
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.headlineFont)
                .foregroundStyle(tokens.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.captionFont)
                    .foregroundStyle(tokens.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.appVisualMode) private var visualMode

    var body: some View {
        let tokens = Theme.visual(visualMode)
        Button {
            WarmHaptics.action()
            action()
        } label: {
            HStack(spacing: 9) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(Theme.headlineFont)
            .foregroundStyle(
                isEnabled
                    ? (visualMode == .mystery ? tokens.textPrimary : tokens.onPrimary)
                    : tokens.textTertiary
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                isEnabled
                    ? (visualMode == .mystery ? tokens.primarySoft : tokens.primary)
                    : tokens.primarySoft,
                in: Capsule()
            )
            .overlay {
                if visualMode == .mystery {
                    Capsule()
                        .stroke(tokens.border.opacity(isEnabled ? 0.95 : 0.55), lineWidth: 0.8)
                }
            }
            .shadow(color: isEnabled ? tokens.shadow.opacity(0.7) : .clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
    }
}

struct StatusPill: View {
    let text: String
    var systemImage: String? = nil

    @Environment(\.appVisualMode) private var visualMode

    var body: some View {
        let tokens = Theme.visual(visualMode)
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(Theme.captionFont)
        .foregroundStyle(tokens.textSecondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            visualMode == .mystery ? tokens.surfaceSoft.opacity(0.92) : tokens.glassTint,
            in: Capsule()
        )
        .overlay(Capsule().stroke(tokens.border.opacity(visualMode == .mystery ? 0.9 : 0.5), lineWidth: 0.6))
    }
}

struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.appVisualMode) private var visualMode

    var body: some View {
        let tokens = Theme.visual(visualMode)
        Button {
            WarmHaptics.action()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tokens.textPrimary)
                .frame(width: 42, height: 42)
                .background(tokens.glassTint, in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(tokens.border.opacity(visualMode == .mystery ? 0.9 : 0.48), lineWidth: 0.6))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    var systemImage: String = "sparkles"

    @Environment(\.appVisualMode) private var visualMode

    var body: some View {
        let tokens = Theme.visual(visualMode)
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(tokens.primary)
            Text(title)
                .font(Theme.headlineFont)
                .foregroundStyle(tokens.textPrimary)
            Text(detail)
                .font(Theme.subheadFont)
                .foregroundStyle(tokens.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}
