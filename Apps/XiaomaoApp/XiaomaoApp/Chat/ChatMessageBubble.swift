import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
            if message.participant == .user {
                Spacer(minLength: 56)
                bubble
            } else {
                avatar
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
            if message.participant != .user {
                Text(message.participant.displayName)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 3)
            }

            Text(message.content)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bubbleSurface)
                .clipShape(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(bubbleBorder, lineWidth: 1)
                }
                .shadow(color: Theme.shadowRaised, radius: 5, x: 0, y: 2)

            Text(message.createdAt, style: .time)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        switch message.participant {
        case .companion:
            Text("我")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.primary)
                .clipShape(Circle())
                .accessibilityHidden(true)
        case .xiaomao:
            Text("🐱")
                .font(.system(size: 20))
                .frame(width: 34, height: 34)
                .background(Color(hex: 0xFFF0E7))
                .clipShape(Circle())
                .overlay { Circle().stroke(Theme.border, lineWidth: 1) }
                .accessibilityHidden(true)
        case .user:
            EmptyView()
        }
    }

    private var bubbleSurface: Color {
        switch message.participant {
        case .user: Color(hex: 0xF9DCE3)
        case .companion: Theme.surface
        case .xiaomao: Color(hex: 0xFBEADF)
        }
    }

    private var bubbleBorder: Color {
        switch message.participant {
        case .user: Theme.primary.opacity(0.14)
        case .companion: Theme.border.opacity(0.85)
        case .xiaomao: Color(hex: 0xF3D8C8)
        }
    }
}
