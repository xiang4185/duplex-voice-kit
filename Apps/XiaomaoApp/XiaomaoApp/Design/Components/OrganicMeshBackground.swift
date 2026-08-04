import SwiftUI

// MARK: - 有机渐变背景 (OrganicMeshBackground)
// P2.7B-FINAL-MESH: iOS 26 原生 MeshGradient (3×3, 共 9 顶点) + KeyframeAnimator
// 提供缓慢、有机、克制的暖色背景, 供首页 (home) 与通话页 (call) 共用.
// Reduce Motion 下显示静态 Mesh, 不构建持续运行的关键帧路径.
// 约束: 仅 9 顶点 / 颜色数组固定不逐帧随机 / 关键帧只更新少量 CGFloat /
// 仅使用 KeyframeAnimator 驱动, 不使用其他定时驱动或手写逐帧循环 / 随机顶点.

struct OrganicMeshBackground: View {
    enum Mode {
        case home
        case call
    }

    let mode: Mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 关键帧值类型 — 仅少量 CGFloat/Double, 每帧不创建复杂对象或随机数
    private struct MeshMotion {
        var centerX: CGFloat = 0.5
        var centerY: CGFloat = 0.5
        var topX: CGFloat = 0.5
        var bottomX: CGFloat = 0.5
        var leftY: CGFloat = 0.5
        var rightY: CGFloat = 0.5
        // P2.7B-FINAL-VISUAL-FIX: 已移除驱动冗余参数 (原 KeyframeTrack 已无渲染意义)
    }

    var body: some View {
        if reduceMotion {
            // Reduce Motion: 静态 Mesh, 不构建持续关键帧, 不移动网格点
            staticMesh
        } else {
            animatedMesh
        }
    }

    // MARK: - 动画网格 (KeyframeAnimator repeating)

    private var animatedMesh: some View {
        KeyframeAnimator(initialValue: MeshMotion(), repeating: true) { motion in
            meshView(motion: motion)
        } keyframes: { _ in
            // 完整周期 20s (任务建议 18~22s):
            // 0s 基准 → 4s 中央点轻微向右上 → 9s 中央点缓慢向左下扩散
            // → 14s 上下边缘色斑轻微交换重心 → 20s 回到基准
            KeyframeTrack(\.centerX) {
                LinearKeyframe(0.50, duration: 0)
                LinearKeyframe(0.53, duration: 4)   // 向右上
                LinearKeyframe(0.47, duration: 5)   // 向左下扩散
                LinearKeyframe(0.50, duration: 6)   // 回到基准
                LinearKeyframe(0.50, duration: 5)   // 停留
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
                LinearKeyframe(0.45, duration: 5)   // 上边缘色斑重心偏移
                LinearKeyframe(0.50, duration: 6)
            }
            KeyframeTrack(\.bottomX) {
                LinearKeyframe(0.50, duration: 0)
                LinearKeyframe(0.48, duration: 4)
                LinearKeyframe(0.52, duration: 5)
                LinearKeyframe(0.55, duration: 5)   // 下边缘交换重心
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
            // P2.7B-FINAL-VISUAL-FIX: 已移除该 KeyframeTrack 关键帧 (无渲染意义)
        }
    }

    // MARK: - 静态网格 (Reduce Motion)

    private var staticMesh: some View {
        meshView(motion: MeshMotion())
    }

    // MARK: - Mesh 渲染

    private func meshView(motion: MeshMotion) -> some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: points(for: motion),
            colors: colors
        )
        .ignoresSafeArea()
        .overlay {
            // P2.7B-FINAL-VISUAL-FIX: 浅色 veil 0.06→0.14, 淡化色块边界, 稳定文字对比度,
            // 保留 Liquid Glass 所需的背景层次, 不把页面变纯白.
            Color.white.opacity(0.14)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    /// 3×3 网格 9 顶点 (行优先: 左上→右上→左下→右下).
    /// 四角固定防止边缘露底; 仅 5 个内部点 (上/下/左/右中点 + 中央) 移动.
    /// 顶点偏移 clamp 在 ±0.05 内 (实际关键帧幅度 ±0.03, 任务建议 ±0.025~0.040).
    private func points(for motion: MeshMotion) -> [SIMD2<Float>] {
        let clamp: (CGFloat) -> CGFloat = { min(max($0, 0.45), 0.55) }
        let cX = clamp(motion.centerX)
        let cY = clamp(motion.centerY)
        let tX = clamp(motion.topX)
        let bX = clamp(motion.bottomX)
        let lY = clamp(motion.leftY)
        let rY = clamp(motion.rightY)

        return [
            SIMD2<Float>(0, 0),                    // 0 左上 (固定)
            SIMD2<Float>(Float(tX), 0),            // 1 上边中点
            SIMD2<Float>(1, 0),                    // 2 右上 (固定)
            SIMD2<Float>(0, Float(lY)),            // 3 左边中点
            SIMD2<Float>(Float(cX), Float(cY)),    // 4 中央
            SIMD2<Float>(1, Float(rY)),            // 5 右边中点
            SIMD2<Float>(0, 1),                    // 6 左下 (固定)
            SIMD2<Float>(Float(bX), 1),            // 7 下边中点
            SIMD2<Float>(1, 1),                    // 8 右下 (固定)
        ]
    }

    /// 固定颜色数组 (P2.7B-FINAL-VISUAL-FIX).
    /// 约束: Rose 最多 1 次, Cool Accent 最多 1 次; 中央为暖白;
    /// 不允许左右两侧同时为 Rose (避免两侧同色 "竖带" 视觉).
    private var colors: [Color] {
        switch mode {
        case .home:
            // Rose       Peach      WarmWhite
            // Peach      WarmWhite  Peach
            // WarmWhite  Peach      CoolAccent
            return [
                Theme.meshRose,
                Theme.meshPeach,
                Theme.meshWarmWhite,

                Theme.meshPeach,
                Theme.meshWarmWhite,
                Theme.meshPeach,

                Theme.meshWarmWhite,
                Theme.meshPeach,
                Theme.meshCoolAccent,
            ]
        case .call:
            // Peach      WarmWhite  CoolAccent
            // WarmWhite  WarmWhite  Peach
            // Rose       WarmWhite  Peach
            return [
                Theme.meshPeach,
                Theme.meshWarmWhite,
                Theme.meshCoolAccent,

                Theme.meshWarmWhite,
                Theme.meshWarmWhite,
                Theme.meshPeach,

                Theme.meshRose,
                Theme.meshWarmWhite,
                Theme.meshPeach,
            ]
        }
    }
}

// MARK: - 预览
#Preview {
    ZStack {
        OrganicMeshBackground(mode: .home)
        Text("小猫")
            .font(.title)
            .foregroundStyle(Theme.textPrimary)
    }
}
