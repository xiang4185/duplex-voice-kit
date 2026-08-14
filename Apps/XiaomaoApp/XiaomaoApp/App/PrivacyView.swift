import SwiftUI

// MARK: - 屏 1 隐私授权引导 (PrivacyView)
// 设计 §4.5: 盾牌图标 + 编辑式短句说明 ×3 + 显式同意 + 可关闭 + 脚注
// 结果持久化到 UserDefaults (privacy.agreed), 同意后进入主流程

struct PrivacyView: View {
    var agreed: () -> Void
    var declined: () -> Void

    @State private var appeared = false

    private struct PrivacyRow: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let rows: [PrivacyRow] = [
        PrivacyRow(
            icon: "lock.shield.fill",
            title: "语音加密上传云端处理",
            detail: "只用于本次对话理解，不留在你的手机里"
        ),
        PrivacyRow(
            icon: "mic.slash.fill",
            title: "只在通话时收音",
            detail: "挂断后立刻停止，不会有任何后台录音"
        ),
        PrivacyRow(
            icon: "togglepower",
            title: "每一个开关，都由你决定",
            detail: "录音历史、个性化推荐，随时可关"
        )
    ]

    var body: some View {
        ZStack {
            Theme.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                // 盾牌图标
                ZStack {
                    Circle()
                        .fill(Theme.primary100)
                        .frame(width: 96, height: 96)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(Theme.primary600)
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.9)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: appeared)

                Text("让陪伴，从信任开始")
                    .font(Theme.title1Font)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)

                Text("使用前，想把几件重要的事说给你听。")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                // 编辑式说明卡
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 16) {
                            Image(systemName: row.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.info)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                    .font(Theme.bodyFont)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(row.detail)
                                    .font(Theme.footnoteFont)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineSpacing(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        if row.id != rows.last?.id {
                            Divider().overlay(Theme.border)
                                .padding(.leading, 72)
                        }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .cardTopHighlight()
                .shadow(color: Theme.shadowRaised, radius: 16, x: 0, y: 4)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(.easeOut(duration: 0.45).delay(0.4), value: appeared)

                // 同意并继续
                Button(action: {
                    WarmHaptics.success()
                    agreed()
                }) {
                    Text("同意并继续")
                        .font(Theme.headlineFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(colors: [Theme.primary500, Theme.primary600], startPoint: .top, endPoint: .bottom),
                            in: Capsule()
                        )
                        .shadow(color: Theme.ctaShadow, radius: 14, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("privacy.agree")
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.55), value: appeared)

                // 暂不同意
                Button {
                    WarmHaptics.action()
                    declined()
                } label: {
                    Text("暂不同意")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("privacy.decline")
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.6), value: appeared)

                // 脚注
                Text("语音将加密上传云端处理，可在「我的 - 隐私」随时关闭。")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.65), value: appeared)

                Spacer(minLength: 30)
            }
        }
        .accessibilityIdentifier("privacy.screen")
        .onAppear { appeared = true }
    }
}

// MARK: - 预览
#Preview {
    PrivacyView(agreed: {}, declined: {})
}
