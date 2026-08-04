import SwiftUI

// MARK: - 彩蛋卡片组件 (EasterEggCards)
// P2.6E: 本地 SwiftUI 彩蛋页 — Pro/帮助/隐私/关于 + 回听详情
// 全部固定内容/预设文案/模拟进度, 不接后台、不接真实音频、不接 StoreKit
// 隐私彩蛋文案采用「私人版本 · 仅供我们查看」, 避免被理解为真实技术保证

// MARK: 通用彩蛋卡 (Pro / 帮助 / 隐私 / 关于)
struct EasterEggCard: View {
    let icon: String
    let title: String
    let bodyText: String
    var footer: String = ""
    var onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bg.opacity(0.96)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                // 图标 (暖粉圆)
                ZStack {
                    Circle()
                        .fill(Theme.primary100)
                        .frame(width: 64, height: 64)
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Theme.primary600)
                }

                Text(title)
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(bodyText)
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                if !footer.isEmpty {
                    Text(footer)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    WarmHaptics.action()
                    dismiss()
                    onClose()
                } label: {
                    Text("好的")
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.primary, in: Capsule())
                        .shadow(color: Theme.ctaShadow, radius: 10, x: 0, y: 5)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("easteregg.ok")
            }
            .padding(24)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.shadowOverlay, radius: 32, x: 0, y: 12)
            .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("easteregg.card")
    }
}

// MARK: 回听详情卡 (固定语录 + 模拟播放进度)
struct ReplayDetailCard: View {
    let time: String
    let mood: String
    /// 固定预设语录 (由 ReplayRow 自带, 禁止 body 内 randomElement)
    let quote: String
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.bg.opacity(0.96)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                Text("回听 · \(time)")
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)

                Text("\(mood)")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.primary700)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.primary100, in: Capsule())

                // 固定回顾文字
                Text("这段陪伴被好好收着。当时的你，声音比想象中轻快。")
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // 私人语录 (固定, 衬线)
                Text("“\(quote)”")
                    .font(Theme.quoteFont)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)

                // 模拟播放进度
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.primary100)
                            Capsule()
                                .fill(Theme.primary)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("0:00")
                        Spacer()
                        Text("2:30")
                    }
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 4)

                Button {
                    WarmHaptics.action()
                    dismiss()
                    onClose()
                } label: {
                    Text("这段先留在我们之间")
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("replay.detail.done")
            }
            .padding(24)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.shadowOverlay, radius: 32, x: 0, y: 12)
            .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("replay.detail.card")
        .onAppear {
            // P2.6E: 模拟播放遵循 Reduce Motion
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.easeInOut(duration: 2.5)) { progress = 1 }
            }
        }
    }
}

// MARK: - 预览
#Preview {
    EasterEggCard(icon: "sparkles", title: "小猫 Pro", bodyText: "小猫 Pro 已永久为你解锁。", onClose: {})
}
