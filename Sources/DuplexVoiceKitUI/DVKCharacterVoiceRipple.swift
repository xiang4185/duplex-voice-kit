#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

public enum DVKCharacterVoiceRippleAnimationMode: String, Equatable, Sendable {
    case none
    case breathing
    case outwardRipple
    case gentlePulse
}

public struct DVKCharacterVoiceRipplePresentation: Equatable, Sendable {
    public let normalizedAmplitude: Float
    public let rippleScale: CGFloat
    public let rippleOpacity: Double
    public let rippleStrokeWidth: CGFloat
    public let showsPrimaryRipple: Bool
    public let showsSecondaryRipple: Bool
    public let animationMode: DVKCharacterVoiceRippleAnimationMode
    public let statusText: String
    public let usesPlaybackAmplitude: Bool

    public init(
        amplitude: Float,
        voiceState: DVKCompanionVoiceState,
        reduceMotion: Bool,
        staticMode: Bool,
        hasError: Bool
    ) {
        let clamped = min(1, max(0, amplitude))
        let playbackDriven: Bool
        switch voiceState {
        case .speaking:
            playbackDriven = !hasError
        default:
            playbackDriven = false
        }
        normalizedAmplitude = playbackDriven ? clamped : 0
        usesPlaybackAmplitude = playbackDriven

        switch voiceState {
        case .connecting:
            rippleScale = 1.015
            rippleOpacity = hasError ? 0.06 : 0.12
            rippleStrokeWidth = 1.1
            showsPrimaryRipple = !hasError
            showsSecondaryRipple = false
            statusText = hasError ? "Error" : "Connecting"
        case .listening:
            rippleScale = 1.025
            rippleOpacity = hasError ? 0.06 : 0.18
            rippleStrokeWidth = 1.3
            showsPrimaryRipple = !hasError
            showsSecondaryRipple = !hasError
            statusText = hasError ? "Error" : "Listening"
        case .processing:
            rippleScale = 1.02
            rippleOpacity = hasError ? 0.06 : 0.16
            rippleStrokeWidth = 1.2
            showsPrimaryRipple = !hasError
            showsSecondaryRipple = !hasError
            statusText = hasError ? "Error" : "Thinking"
        case .speaking:
            rippleScale = 1 + CGFloat(normalizedAmplitude) * 0.045
            rippleOpacity = 0.06 + Double(normalizedAmplitude) * 0.22
            rippleStrokeWidth = 0.8 + CGFloat(normalizedAmplitude)
            showsPrimaryRipple = !hasError && normalizedAmplitude > 0.01
            showsSecondaryRipple = !hasError && normalizedAmplitude > 0.35
            statusText = hasError ? "Error" : "Speaking"
        case .ended:
            rippleScale = 1
            rippleOpacity = 0.06
            rippleStrokeWidth = 0.8
            showsPrimaryRipple = false
            showsSecondaryRipple = false
            statusText = hasError ? "Error" : "Session ending"
        case .idle:
            rippleScale = 1
            rippleOpacity = 0.04
            rippleStrokeWidth = 0.8
            showsPrimaryRipple = false
            showsSecondaryRipple = false
            statusText = hasError ? "Error" : "Voice ready"
        }

        let canAnimate = !reduceMotion && !staticMode && !hasError
        switch voiceState {
        case .connecting:
            animationMode = canAnimate && showsPrimaryRipple ? .breathing : .none
        case .listening, .speaking:
            animationMode = canAnimate && showsPrimaryRipple ? .outwardRipple : .none
        case .processing:
            animationMode = canAnimate && showsPrimaryRipple ? .gentlePulse : .none
        case .idle, .ended:
            animationMode = .none
        }
    }
}

@available(iOS 17.0, *)
@MainActor
public struct DVKCharacterVoiceRipple: View {
    public let presentation: DVKCharacterVoiceRipplePresentation
    public let theme: DVKCompanionTheme
    @State private var phase = false

    public init(
        presentation: DVKCharacterVoiceRipplePresentation,
        theme: DVKCompanionTheme
    ) {
        self.presentation = presentation
        self.theme = theme
    }

    private var loopingAnimation: Animation? {
        switch presentation.animationMode {
        case .none:
            return nil
        case .outwardRipple:
            return .easeOut(duration: 2.8).repeatForever(autoreverses: false)
        case .breathing:
            return .easeInOut(duration: 4.5).repeatForever(autoreverses: true)
        case .gentlePulse:
            return .easeInOut(duration: 5.0).repeatForever(autoreverses: true)
        }
    }

    public var body: some View {
        ZStack {
            if presentation.showsPrimaryRipple {
                Ellipse()
                    .stroke(
                        theme.primaryAction.opacity(presentation.rippleOpacity),
                        lineWidth: presentation.rippleStrokeWidth
                    )
                    .frame(width: 268, height: 238)
                    .scaleEffect(min(1.045, presentation.rippleScale + (phase ? 0.01 : 0)))
                    .opacity(phase ? 0.35 : 1)
                    .blur(radius: phase ? 6 : 2)
            }

            if presentation.showsSecondaryRipple {
                Ellipse()
                    .stroke(
                        theme.halo.opacity(presentation.rippleOpacity * 0.55),
                        lineWidth: min(1.2, presentation.rippleStrokeWidth)
                    )
                    .frame(width: 272, height: 248)
                    .scaleEffect(min(1.045, presentation.rippleScale + (phase ? 0.012 : 0)))
                    .opacity(phase ? 0.18 : 0.48)
                    .blur(radius: phase ? 7 : 4)
            }
        }
        .frame(width: 286, height: 286)
        .animation(loopingAnimation, value: phase)
        .task(id: presentation.animationMode) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                phase = false
            }

            guard presentation.animationMode != .none else {
                return
            }

            await Task.yield()
            guard !Task.isCancelled else {
                return
            }
            phase = true
        }
        .accessibilityHidden(true)
    }
}
#endif
