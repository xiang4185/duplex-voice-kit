import SwiftUI

// MARK: - 圆环光晕 (RingHaloView)
// 参考用户第一张参考图: 暖粉渐变多层圆环 + 弥散光晕 + 呼吸动效
// 状态通过缩放/节奏表达, 颜色保持暖粉 (不变色原则)

struct RingHaloView: View {
    /// 0...1 状态强度 (安静 0.5 / 说话 0.75)
    var intensity: Double = 0.5
    /// 圆环直径 (pt)
    var diameter: CGFloat = 240
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            // 1. 弥散光晕 (最外层)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.primary.opacity(0.32 * intensity),
                            Theme.primary.opacity(0.10 * intensity),
                            .clear
                        ],
                        center: .center,
                        startRadius: diameter * 0.25,
                        endRadius: diameter * 0.62
                    )
                )
                .frame(width: diameter * 1.25, height: diameter * 1.25)

            // 2. 外环 (渐变描边)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Theme.primaryLight, Theme.primary, Theme.primaryDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: Theme.orbShadow, radius: 12, x: 0, y: 0)

            // 3. 内环 (浅色细环)
            Circle()
                .stroke(
                    Theme.primaryLight.opacity(0.85),
                    lineWidth: 2
                )
                .frame(width: diameter - 22, height: diameter - 22)

            // 4. 核心背景 (极浅粉, 让人物更融合)
            Circle()
                .fill(Theme.primarySoft.opacity(0.55))
                .frame(width: diameter - 34, height: diameter - 34)
        }
        .scaleEffect(reduceMotion ? 1 : (breathing ? 1.02 : 0.98))
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
            value: breathing
        )
        .onAppear { breathing = true }
        .accessibilityHidden(true)
    }
}

// MARK: - 预览
#Preview {
    ZStack {
        Theme.homeBackground
        RingHaloView(intensity: 0.6)
    }
}
