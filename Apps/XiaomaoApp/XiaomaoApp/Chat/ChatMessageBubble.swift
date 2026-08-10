import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    var groupedWithPrevious: Bool = false
    var groupedWithNext: Bool = false
    @Environment(\.appVisualMode) private var visualMode

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
            if message.participant == .user {
                Spacer(minLength: 56)
                bubble
            } else {
                if groupedWithPrevious {
                    Color.clear.frame(width: 34, height: 1)
                } else {
                    avatar
                }
                bubble
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.participant.displayName)：\(message.content)")
        .accessibilityIdentifier("chat.message.\(message.id)")
    }

    private var bubble: some View {
        VStack(
            alignment: message.participant == .user ? .trailing : .leading,
            spacing: 5
        ) {
            if message.participant != .user && !groupedWithPrevious {
                Text(message.participant.displayName)
                    .font(Theme.captionFont)
                    .foregroundStyle(visual.textSecondary)
                    .padding(.horizontal, 3)
            }

            Text(message.content)
                .font(Theme.bodyFont)
                .foregroundStyle(visual.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bubbleSurface)
                .clipShape(
                    RoundedRectangle(cornerRadius: groupedWithPrevious || groupedWithNext ? 14 : 20, style: .continuous)
                )
                .shadow(color: visual.shadow.opacity(0.55), radius: 7, x: 0, y: 3)

            if !groupedWithNext {
                Text(message.createdAt, style: .time)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(visual.textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        switch message.participant {
        case .developer:
            Text("开")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(visual.primary)
                .clipShape(Circle())
                .accessibilityHidden(true)
        case .xiaomao:
            PrivacyAvatar(
                size: 34,
                tappable: false,
                style: .thumbnail
            )
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
        case .user:
            EmptyView()
        }
    }

    private var bubbleSurface: Color {
        switch message.participant {
        case .user:
            visualMode == .mystery ? visual.primarySoft.opacity(0.92) : Color(hex: 0xF4D9DF).opacity(0.82)
        case .developer:
            visual.surface.opacity(0.78)
        case .xiaomao:
            visual.surfaceSoft.opacity(0.82)
        }
    }
}
