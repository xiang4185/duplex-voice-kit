import SwiftUI

// MARK: - 角色头像 (CharacterView) — v3.1 原图头像 + 圆环
// 人物 = 用户原图裁剪的头+肩圆形头像 (Assets.xcassets/CharacterAvatar)
// 外层 = RingHaloView 多���渐变圆环 (参考用户第一张参考图)
// 动效: 呼吸缩放 (永远运行) + 说话时轻微放大

struct CharacterView: View {
    /// 0 = 安静, >0 = 说话 (轻微放大 + 亮度提升)
    var speakingAmount: Double = 0
    /// 头像直径 (pt)
    var diameter: CGFloat = 200
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // 呼吸: 3.5s 周期, 幅度 ±1.5%
            let breath = reduceMotion ? 0 : sin(t * 2 * .pi / 3.5) * 0.015
            // 说话时轻微放大
            let speak = CGFloat(min(max(speakingAmount, 0), 1)) * 0.02

            ZStack {
                RingHaloView(intensity: 0.5 + speakingAmount * 0.25, diameter: diameter + 44)

                // 人物头像 (原图圆形, 居中)
                // V3: 图片自带软羽化透明边 (去白边 + 外圈径向淡出),
                // 不再用 clipShape 硬切, 保留软边与圆环自然融合
                Image("CharacterAvatar")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: diameter)
            }
            .scaleEffect(1 + breath + speak)
            .animation(.easeInOut(duration: 0.08), value: speakingAmount)
        }
        .frame(width: diameter + 44, height: diameter + 44)
        .accessibilityLabel("小猫")
    }
}

// MARK: - 预览
#Preview {
    ZStack {
        Theme.homeBackground
        CharacterView(speakingAmount: 0.1, diameter: 200)
    }
}
