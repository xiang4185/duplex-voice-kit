import SwiftUI

// MARK: - 屏 6 陪伴回顾 (ReviewView)
// P2.6I: 无真实历史数据源时显示诚实空状态, 不再展示假时间戳/假分钟数/假情绪结论/假语录.
// 保留程序化头像/图标/背景/卡片材质, 但不暗示已保存聊天/音频/情绪/统计.

struct ReviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部标题
                VStack(alignment: .leading, spacing: 6) {
                    Text("陪伴回顾")
                        .font(Theme.title1Font)
                        .foregroundStyle(Theme.textPrimary)
                    Text("每一次对话，都值得被记住。")
                        .font(Theme.subheadFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                Spacer(minLength: 24)

                // 诚实空状态 (常见 iPhone 尺寸上视觉居中)
                VStack(spacing: 16) {
                    // 程序化头像 (隐私模糊) — 仅作形象占位, 不暗示已保存内容
                    PrivacyAvatar(size: 96, tappable: false)

                    Text("陪伴记录尚未开放")
                        .font(Theme.title3Font)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("当前版本暂不展示聊天或录音历史。")
                        .font(Theme.subheadFont)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(.easeOut(duration: 0.45).delay(0.28), value: appeared)

                Spacer(minLength: 80)
            }
        }
        .accessibilityIdentifier("review.screen")
        .onAppear { appeared = true }
    }
}

// MARK: - 预览
#Preview {
    ReviewView()
}
