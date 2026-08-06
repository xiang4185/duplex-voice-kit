import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
            if message.participant == .user {
                Spacer(minLength: Theme.Spacing.xxxLarge)
            } else {
                avatar
            }

            VStack(
                alignment: message.participant == .user ? .trailing : .leading,
                spacing: Theme.Spacing.xxSmall
            ) {
                Text(message.senderName)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)

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

            if message.participant != .user {
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
        Image(systemName: message.participant == .xiaomao ? "cat.fill" : "heart.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 32, height: 32)
            .foregroundStyle(Theme.primary)
            .background(Theme.primarySoft)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var bubbleSurface: Color {
        message.participant == .user
            ? Theme.userMessageSurface
            : Theme.assistantMessageSurface
    }

    private var accessibilityText: String {
        "\(message.senderName)：\(message.content)"
    }
}
