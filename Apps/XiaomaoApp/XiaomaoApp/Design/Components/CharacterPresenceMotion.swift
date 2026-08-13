import SwiftUI

// MARK: - Character presence

/// A UI-only projection of the real voice session. It deliberately collapses
/// protocol detail into the six states a person can recognise at a glance.
enum CharacterPresencePhase: Equatable {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    case reconnecting

    init(voiceState: VoiceSessionState, callIsActive: Bool = true) {
        guard callIsActive else {
            self = .idle
            return
        }

        switch voiceState {
        case .idle, .connecting:
            self = .connecting
        case .ready, .listening, .endpointing:
            self = .listening
        case .processing:
            self = .thinking
        case .speaking, .interrupting:
            self = .speaking
        case .reconnecting, .degraded:
            self = .reconnecting
        case .closing, .closed, .failed:
            self = .idle
        }
    }

    var eyebrow: String {
        switch self {
        case .idle: return "AVAILABLE NOW"
        case .connecting: return "COMING CLOSER"
        case .listening: return "LISTENING"
        case .thinking: return "THINKING"
        case .speaking: return "SPEAKING"
        case .reconnecting: return "FINDING THE WAY BACK"
        }
    }

    fileprivate var symbolName: String {
        switch self {
        case .idle: return "circle.fill"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .listening: return "ear.fill"
        case .thinking: return "ellipsis"
        case .speaking: return "waveform"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        }
    }

    fileprivate var cycleDuration: Double {
        switch self {
        case .idle: return 7.6
        case .connecting: return 2.4
        case .listening: return 3.6
        case .thinking: return 2.8
        case .speaking: return 0.82
        case .reconnecting: return 1.9
        }
    }

    fileprivate var scaleRange: ClosedRange<CGFloat> {
        switch self {
        case .idle: return 0.997...1.006
        case .connecting: return 0.995...1.008
        case .listening: return 1.002...1.012
        case .thinking: return 0.998...1.008
        case .speaking: return 0.996...1.014
        case .reconnecting: return 0.994...1.004
        }
    }

    fileprivate var verticalTravel: CGFloat {
        switch self {
        case .idle: return -1.6
        case .connecting: return -1.0
        case .listening: return -2.0
        case .thinking: return -1.4
        case .speaking: return -1.2
        case .reconnecting: return -0.7
        }
    }

    fileprivate var auraOpacity: Double {
        switch self {
        case .idle: return 0.18
        case .connecting: return 0.24
        case .listening: return 0.32
        case .thinking: return 0.27
        case .speaking: return 0.38
        case .reconnecting: return 0.22
        }
    }
}

enum CharacterPresenceStyle: Equatable {
    case hero
    case compact
}

enum CharacterTransitionID {
    static let call = "xiaomao.character.call"
}

private struct CharacterAliveModifier: ViewModifier {
    let phase: CharacterPresencePhase
    let style: CharacterPresenceStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode
    @State private var cycle = false

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    func body(content: Content) -> some View {
        content
            .scaleEffect(currentScale)
            .offset(y: currentOffset)
            .brightness(currentBrightness)
            .background {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                visual.primary.opacity(phase.auraOpacity),
                                visual.halo.opacity(phase.auraOpacity * 0.48),
                                .clear
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: style == .hero ? 165 : 28
                        )
                    )
                    .scaleEffect(reduceMotion ? 1 : (cycle ? 1.06 : 0.96))
                    .opacity(reduceMotion ? 0.72 : (cycle ? 0.92 : 0.62))
                    .blur(radius: style == .hero ? 18 : 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomTrailing) {
                if style == .hero, phase != .idle {
                    CharacterStateGlyph(phase: phase)
                        .offset(x: -4, y: -16)
                        .transition(.scale(scale: 0.84).combined(with: .opacity))
                }
            }
            .animation(cycleAnimation, value: cycle)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.24),
                value: phase
            )
            .onAppear { cycle = !reduceMotion }
            .onChange(of: reduceMotion) { _, isReduced in
                cycle = !isReduced
            }
            .onChange(of: phase) { _, _ in
                guard !reduceMotion else { return }
                cycle = false
                DispatchQueue.main.async { cycle = true }
            }
    }

    private var currentScale: CGFloat {
        guard !reduceMotion else { return 1 }
        let range = phase.scaleRange
        let value = cycle ? range.upperBound : range.lowerBound
        return style == .hero ? value : 1 + (value - 1) * 0.55
    }

    private var currentOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        let value = cycle ? phase.verticalTravel : 0
        return style == .hero ? value : value * 0.35
    }

    private var currentBrightness: Double {
        guard !reduceMotion else { return 0 }
        if phase == .listening { return cycle ? 0.018 : 0 }
        if phase == .speaking { return cycle ? 0.025 : 0.005 }
        return 0
    }

    private var cycleAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: phase.cycleDuration)
            .repeatForever(autoreverses: true)
    }
}

private struct CharacterStateGlyph: View {
    let phase: CharacterPresencePhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    var body: some View {
        Image(systemName: phase.symbolName)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(visual.primary)
            .frame(width: 34, height: 34)
            .background(.ultraThinMaterial, in: Circle())
            .background(visual.surface.opacity(0.78), in: Circle())
            .overlay(Circle().stroke(visual.border.opacity(0.72), lineWidth: 0.7))
            .shadow(color: visual.shadow, radius: 10, y: 4)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(
                .pulse,
                options: .repeating,
                isActive: phase == .speaking && !reduceMotion
            )
            .accessibilityHidden(true)
    }
}

extension View {
    func characterAlive(
        phase: CharacterPresencePhase,
        style: CharacterPresenceStyle
    ) -> some View {
        modifier(CharacterAliveModifier(phase: phase, style: style))
    }

    @ViewBuilder
    func characterCallTransitionSource(
        namespace: Namespace.ID,
        reduceMotion: Bool
    ) -> some View {
        if reduceMotion {
            self
        } else {
            matchedTransitionSource(id: CharacterTransitionID.call, in: namespace)
        }
    }
}
