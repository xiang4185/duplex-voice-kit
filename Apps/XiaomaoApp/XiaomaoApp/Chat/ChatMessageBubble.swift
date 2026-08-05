import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
            if message.role == .user {
                Spacer(minLength: Theme.Spacing.xxxLarge)
            } else {
                avatar
            }

            VStack(
                alignment: message.role == .user ? .trailing : .leading,
                spacing: Theme.Spacing.xxSmall
            ) {
                Text(message.content)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.small)
                    .padding(.vertical, 10)
                    .background(bubbleSurface)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.medium,
                            style: .continuous
                        )
                    )

                Text(message.createdAt, style: .time)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Theme.Spacing.xxSmall)
            }

            if message.role == .assistant {
                Spacer(minLength: Theme.Spacing.xxxLarge)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("chat.message.\(message.id)")
    }

    private var avatar: some View {
        Image(systemName: "cat.fill")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 32, height: 32)
            .foregroundStyle(Theme.primary)
            .background(Theme.primarySoft)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var bubbleSurface: Color {
        message.role == .user
            ? Theme.userMessageSurface
            : Theme.assistantMessageSurface
    }

    private var accessibilityText: String {
        message.role == .user
            ? "你：\(message.content)"
            : "小猫：\(message.content)"
    }
}
