import SwiftUI

// MARK: - 吃醋彩蛋弹层 (JealousOverlay)
// P2.6D: 点击非小猫角色 → 小猫"吃醋"
// 文案递增: 第 1-2 次「你还想选别人？」→ 第 3 次「你今天真的很想换人？」→ 继续「不给换。」
// 「只是看看」= 切换视觉预览角色 (不改变生产语音); 「还是小猫」= 保持小猫

struct JealousTarget: Identifiable {
    let id = UUID()
    let role: CompanionPreviewRole
    let tapCount: Int
}

struct JealousOverlay: View {
    let role: CompanionPreviewRole
    let tapCount: Int
    var onJustLook: () -> Void
    var onStayXiaomao: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// 第 3 次起换严厉标题
    private var title: String {
        tapCount >= 3 ? "你今天真的很想换人？" : "你还想选别人？"
    }

    /// 第 4 次起「不给换。」
    private var bodyText: String {
        tapCount >= 4 ? "不给换。" : "小猫刚刚好像看见了。"
    }

    /// 「不给换。」阶段只保留一个出口按钮
    private var isFinalRejection: Bool { tapCount >= 4 }

    var body: some View {
        ZStack {
            Theme.bg.opacity(0.96)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                // 角色头像 (预览形象)
                PrivacyAvatar(
                    size: 84,
                    tappable: false,
                    variant: role.avatarVariant
                )

                Text(title)
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(bodyText)
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                if isFinalRejection {
                    // 第 4 次起: 单出口 (小猫弹回)
                    Button {
                        WarmHaptics.action()
                        dismiss()
                        onStayXiaomao()
                    } label: {
                        Text("回到小猫身边")
                            .font(Theme.headlineFont)
                            .foregroundStyle(Theme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.primary, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("jealous.backToXiaomao")
                } else {
                    HStack(spacing: 12) {
                        Button {
                            WarmHaptics.action()
                            dismiss()
                            onStayXiaomao()
                        } label: {
                            Text("还是小猫")
                                .font(Theme.headlineFont)
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("jealous.stayXiaomao")

                        Button {
                            WarmHaptics.action()
                            dismiss()
                            onJustLook()
                        } label: {
                            Text("只是看看")
                                .font(Theme.headlineFont)
                                .foregroundStyle(Theme.onPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Theme.primary, in: Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("jealous.justLook")
                    }
                }

                Text("小猫的悄悄话")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(24)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.shadowOverlay, radius: 32, x: 0, y: 12)
            .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("jealous.overlay")
    }
}

// MARK: - 角色头像变体映射
extension CompanionPreviewRole {
    /// 对应 PrivacyAvatar 变体 (小猫=真实原图, 其他=程序化占位)
    var avatarVariant: AvatarVariant {
        switch self {
        case .xiaomao: return .xiaomao
        case .healingGirl: return .healingGirl
        case .calmUncle: return .calmUncle
        }
    }
}

// MARK: - 预览
#Preview {
    JealousOverlay(role: .healingGirl, tapCount: 1, onJustLook: {}, onStayXiaomao: {})
}
