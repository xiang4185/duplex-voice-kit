#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

/// Programmatic organic continuous background used by the Home, Cats and
/// Conversation pages. iOS 26 MeshGradient (fixed 3x3 theme colors, only a few
/// keyframe-driven point offsets) with a LinearGradient fallback. No images,
/// no downloads: purely SwiftUI and existing DVK theme colors.
@MainActor
public struct DVKBackgroundMeshView: View {
    public enum Mode: Sendable {
        case home
        case call
    }

    public let mode: Mode
    public let theme: DVKCompanionTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(mode: Mode, theme: DVKCompanionTheme) {
        self.mode = mode
        self.theme = theme
    }

    public var body: some View {
        if #available(iOS 18.0, *) {
            if reduceMotion {
                staticMesh
            } else {
                animatedMesh
            }
        } else {
            theme.backgroundGradient.ignoresSafeArea()
        }
    }

    /// Keyframe value type — only a handful of CGFloat offsets per frame.
    private struct MeshMotion {
        var centerX: CGFloat = 0.5
        var centerY: CGFloat = 0.5
        var topX: CGFloat = 0.5
        var bottomX: CGFloat = 0.5
        var leftY: CGFloat = 0.5
        var rightY: CGFloat = 0.5
    }

    @available(iOS 18.0, *)
    private var animatedMesh: some View {
        KeyframeAnimator(initialValue: MeshMotion(), repeating: true) { motion in
            meshView(motion: motion)
        } keyframes: { _ in
            KeyframeTrack(\.centerX) {
                LinearKeyframe(0.50, duration: 0)
                LinearKeyframe(0.53, duration: 4)
                LinearKeyframe(0.47, duration: 5)
                LinearKeyframe(0.50, duration: 6)
                LinearKeyframe(0.50, duration: 5)
            }
            KeyframeTrack(\.centerY) {
                LinearKeyframe(0.50, duration: 0)
                LinearKeyframe(0.47, duration: 4)
                LinearKeyframe(0.55, duration: 5)
                LinearKeyframe(0.50, duration: 6)
                LinearKeyframe(0.50, duration: 5)
            }
            KeyframeTrack(\.topX) {
                LinearKeyframe(0.50, duration: 0)
                LinearKeyframe(0.52, duration: 4)
                LinearKeyframe(0.48, duration: 5)
                LinearKeyframe(0.45, duration: 5)
                LinearKeyframe(0.50, duration: 6)
            }
            KeyframeTrack(\.bottomX) {
                LinearKeyframe(0.50, duration: 0)
                LinearKeyframe(0.48, duration: 4)
                LinearKeyframe(0.52, duration: 5)
                LinearKeyframe(0.55, duration: 5)
                LinearKeyframe(0.50, duration: 6)
            }
            KeyframeTrack(\.leftY) {
                LinearKeyframe(0.50, duration: 0)
                LinearKeyframe(0.48, duration: 4)
                LinearKeyframe(0.52, duration: 5)
                LinearKeyframe(0.50, duration: 6)
                LinearKeyframe(0.50, duration: 5)
            }
            KeyframeTrack(\.rightY) {
                LinearKeyframe(0.50, duration: 0)
                LinearKeyframe(0.52, duration: 4)
                LinearKeyframe(0.48, duration: 5)
                LinearKeyframe(0.50, duration: 6)
                LinearKeyframe(0.50, duration: 5)
            }
        }
    }

    @available(iOS 18.0, *)
    private var staticMesh: some View {
        meshView(motion: MeshMotion())
    }

    @available(iOS 18.0, *)
    private func meshView(motion: MeshMotion) -> some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: points(for: motion),
            colors: colors
        )
        .ignoresSafeArea()
        .overlay {
            theme.pageBackground.opacity(0.14)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    /// 3x3 grid, 9 vertices, row-major. Corners are fixed; only the five
    /// interior points drift, clamped to a narrow band around the center.
    private func points(for motion: MeshMotion) -> [SIMD2<Float>] {
        let clamp: (CGFloat) -> CGFloat = { min(max($0, 0.45), 0.55) }
        let cX = clamp(motion.centerX)
        let cY = clamp(motion.centerY)
        let tX = clamp(motion.topX)
        let bX = clamp(motion.bottomX)
        let lY = clamp(motion.leftY)
        let rY = clamp(motion.rightY)
        return [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(Float(tX), 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(0, Float(lY)),
            SIMD2<Float>(Float(cX), Float(cY)),
            SIMD2<Float>(1, Float(rY)),
            SIMD2<Float>(0, 1),
            SIMD2<Float>(Float(bX), 1),
            SIMD2<Float>(1, 1)
        ]
    }

    /// Fixed theme-derived color array — no randomness, no per-frame colors.
    private var colors: [Color] {
        let warm = theme.pageBackground
        let soft = theme.halo.opacity(0.55)
        let rose = theme.primaryAction.opacity(0.5)
        let cool = theme.textSecondary.opacity(0.28)
        switch mode {
        case .home:
            return [rose, soft, warm, soft, warm, soft, warm, soft, cool]
        case .call:
            return [soft, warm, cool, warm, warm, soft, rose, warm, soft]
        }
    }
}
#endif
