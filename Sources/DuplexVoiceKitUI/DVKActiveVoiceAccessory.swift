#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

public struct DVKActiveVoiceAccessoryPresentation: Equatable, Sendable {
    public let isVisible: Bool
    public let profileName: String
    public let statusText: String
    public let accessibilityLabel: String

    public init(hasActiveSession: Bool, voiceState: DVKCompanionVoiceState, profileName: String?) {
        isVisible = hasActiveSession
        self.profileName = profileName ?? "Current cat"
        switch voiceState {
        case .connecting: statusText = "Connecting"
        case .listening: statusText = "Listening"
        case .processing: statusText = "Thinking"
        case .speaking: statusText = "Speaking"
        case .ended: statusText = "Session ending"
        case .idle: statusText = "Voice session"
        }
        accessibilityLabel = "\(self.profileName), \(statusText), Return to voice session"
    }
}

@available(iOS 17.0, *)
public struct DVKActiveVoiceAccessoryModifier: ViewModifier {
    let presentation: DVKActiveVoiceAccessoryPresentation
    let theme: DVKCompanionTheme
    let onReturn: () -> Void

    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.tabViewBottomAccessory {
                if presentation.isVisible {
                    DVKActiveVoiceAccessoryView(presentation: presentation, theme: theme, onReturn: onReturn)
                }
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 8) {
                if presentation.isVisible {
                    DVKActiveVoiceAccessoryView(presentation: presentation, theme: theme, onReturn: onReturn)
                        .padding(.horizontal, 12)
                }
            }
        }
        #else
        content.safeAreaInset(edge: .bottom, spacing: 8) {
            if presentation.isVisible {
                DVKActiveVoiceAccessoryView(presentation: presentation, theme: theme, onReturn: onReturn)
                    .padding(.horizontal, 12)
            }
        }
        #endif
    }
}

@available(iOS 17.0, *)
public struct DVKActiveVoiceAccessoryView: View {
    public let presentation: DVKActiveVoiceAccessoryPresentation
    public let theme: DVKCompanionTheme
    private let onReturn: () -> Void

    public init(presentation: DVKActiveVoiceAccessoryPresentation, theme: DVKCompanionTheme, onReturn: @escaping () -> Void) {
        self.presentation = presentation
        self.theme = theme
        self.onReturn = onReturn
    }

    public var body: some View {
        if presentation.isVisible {
            Button(action: onReturn) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .imageScale(.medium)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.profileName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(presentation.statusText)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textPrimary)
            #if compiler(>=6.2)
            .modifier(DVKActiveVoiceAccessorySurfaceModifier(theme: theme))
            #else
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.elevatedSurface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.border, lineWidth: 1))
            #endif
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityHint("Opens the current voice conversation")
            .accessibilityIdentifier("companion.activeVoiceAccessory")
        }
    }
}

private struct DVKActiveVoiceAccessorySurfaceModifier: ViewModifier {
    let theme: DVKCompanionTheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.elevatedSurface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.border, lineWidth: 1))
        }
    }
}

@available(iOS 17.0, *)
public extension View {
    func dvkActiveVoiceAccessory(
        presentation: DVKActiveVoiceAccessoryPresentation,
        theme: DVKCompanionTheme,
        onReturn: @escaping () -> Void
    ) -> some View {
        modifier(DVKActiveVoiceAccessoryModifier(presentation: presentation, theme: theme, onReturn: onReturn))
    }
}
#endif
