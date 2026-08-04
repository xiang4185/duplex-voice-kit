#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

// MARK: - Reusable programmatic visual language
//
// Sanitized, provider-neutral building blocks migrated from the reference
// app shell: serif display type, halo glow, sonar status dot, mini waveform,
// card top highlight and spring press feedback. Everything is drawn with
// existing DVK theme colors — no images, no fonts, no private assets.

@MainActor
public enum DVKCompanionTypography {
    public static func serifDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    public static func serifName(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

/// Breathing halo glow behind the central character. Static radial layers
/// with a gentle scale/translate breath; honors Reduce Motion.
@MainActor
public struct DVKCompanionHeroHalo: View {
    public let color: Color
    public let diameter: CGFloat
    public let reduceMotion: Bool
    @State private var breathe = false

    public init(color: Color, diameter: CGFloat = 220, reduceMotion: Bool = false) {
        self.color = color
        self.diameter = diameter
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.30), color.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 200
                    )
                )
                .frame(width: 380, height: 380)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.55), color.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 140
                    )
                )
                .frame(width: 300, height: 60)
                .offset(y: diameter * 0.55)
                .blur(radius: 24)
                .opacity(0.85)
        }
        .scaleEffect(reduceMotion ? 1 : (breathe ? 1.02 : 0.985))
        .offset(y: reduceMotion ? 0 : (breathe ? -3 : 2))
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 4.2).repeatForever(autoreverses: true),
            value: breathe
        )
        .onAppear { if !reduceMotion { breathe = true } }
        .accessibilityHidden(true)
    }
}

/// Sonar status dot: an expanding ring around a filled center, echoing the
/// reference shell's presence pulse. Deterministic, no randomness.
@MainActor
public struct DVKCompanionSonarDot: View {
    public let color: Color
    public let diameter: CGFloat
    public let reduceMotion: Bool
    @State private var pulse = false

    public init(color: Color, diameter: CGFloat = 20, reduceMotion: Bool = false) {
        self.color = color
        self.diameter = diameter
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.5), lineWidth: 1.5)
                .frame(width: diameter * 0.9, height: diameter * 0.9)
                .scaleEffect(pulse ? 2.2 : 0.8)
                .opacity(pulse ? 0 : 0.7)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeOut(duration: 4.0).repeatForever(autoreverses: false),
                    value: pulse
                )
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { if !reduceMotion { pulse = true } }
        .accessibilityHidden(true)
    }
}

/// Mini waveform: a small set of capsule bars with a fixed deterministic
/// amplitude profile, animated through a repeating phase. No timer.
@MainActor
public struct DVKCompanionMiniWave: View {
    public let active: Bool
    public let color: Color
    public let reduceMotion: Bool
    public var barCount: Int
    @State private var phase: CGFloat = 0

    public init(
        active: Bool,
        color: Color,
        reduceMotion: Bool = false,
        barCount: Int = 5
    ) {
        self.active = active
        self.color = color
        self.reduceMotion = reduceMotion
        self.barCount = barCount
    }

    public var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width / CGFloat(barCount) * 0.42
            let spacing = (geo.size.width - barWidth * CGFloat(barCount)) / CGFloat(barCount - 1)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(color.opacity(active ? 0.85 : 0.30))
                        .frame(width: barWidth, height: barHeight(i, geo: geo))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            guard active && !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ i: Int, geo: GeometryProxy) -> CGFloat {
        guard active else { return geo.size.height * 0.3 }
        let amplitudes: [CGFloat] = [0.55, 0.95, 0.4, 1.0, 0.7, 0.85, 0.5, 0.9, 0.62, 0.78]
        let base = amplitudes[i % amplitudes.count]
        let pulse = 0.65 + 0.35 * phase
        return geo.size.height * base * pulse
    }
}

/// 1px white top highlight used by reference-shell cards.
public extension View {
    @ViewBuilder
    func dvkCardTopHighlight(height: CGFloat = 1.2) -> some View {
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

/// Spring press feedback shared by reference-shell buttons.
public struct DVKPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.35, dampingFraction: 0.64),
                value: configuration.isPressed
            )
    }
}

/// Compact programmatic cat avatar for small fixed containers (e.g. 52pt
/// role action bar). Draws the face, ears, eyes and mouth inside the given
/// container so the result is a real avatar, not a clipped full canvas.
@MainActor
public struct DVKCompanionCompactAvatar: View {
    public let profile: DVKCompanionProfile
    public let size: CGFloat

    public init(profile: DVKCompanionProfile, size: CGFloat = 52) {
        self.profile = profile
        self.size = size
    }

    private var accent: Color {
        switch profile.themeKey {
        case .warmCreamRose: return Color(hex: 0xD9486B)
        case .coralGold: return Color(hex: 0xE36C4D)
        case .mistBlue: return Color(hex: 0x7897AC)
        case .lavenderNight: return Color(hex: 0xA58BC4)
        }
    }
    private var fur: Color {
        switch profile.characterVisualKey {
        case "coral-gold": return Color(hex: 0xF2B58D)
        case "silver-mist": return Color(hex: 0xBCC8D0)
        case "lavender-night": return Color(hex: 0xC8B4D7)
        default: return Color(hex: 0xF6E4D7)
        }
    }
    private var earMark: Color {
        switch profile.characterVisualKey {
        case "coral-gold": return Color(hex: 0xC65A42)
        case "silver-mist": return Color(hex: 0x6C8EA4)
        case "lavender-night": return Color(hex: 0x6E568E)
        default: return Color(hex: 0xC87886)
        }
    }

    public var body: some View {
        ZStack {
            // 圆脸
            Circle()
                .fill(fur)
                .frame(width: size * 0.82, height: size * 0.82)
            // 耳朵
            HStack(spacing: size * 0.62) {
                CompactEar()
                    .fill(earMark)
                    .frame(width: size * 0.20, height: size * 0.26)
                CompactEar()
                    .fill(earMark)
                    .frame(width: size * 0.20, height: size * 0.26)
            }
            .offset(y: -size * 0.30)
            // 眼睛
            HStack(spacing: size * 0.26) {
                Circle().fill(Color.black.opacity(0.72)).frame(width: size * 0.07, height: size * 0.10)
                Circle().fill(Color.black.opacity(0.72)).frame(width: size * 0.07, height: size * 0.10)
            }
            .offset(y: -size * 0.02)
            // 嘴
            Capsule()
                .fill(earMark)
                .frame(width: size * 0.16, height: size * 0.05)
                .offset(y: size * 0.24)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct CompactEar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
#endif
