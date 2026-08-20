import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    var localParticipant: ChatParticipant = .user
    @ObservedObject var avatarStore: ChatAvatarStore
    var groupedWithPrevious: Bool = false
    var groupedWithNext: Bool = false
    @Environment(\.appVisualMode) private var visualMode

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }
    private var isLocalMessage: Bool { message.participant == localParticipant }
    private var participantDisplayName: String {
        if isLocalMessage { return "你" }
        switch message.participant {
        case .user: return "客户"
        case .developer: return "开发者"
        case .xiaomao: return "小猫"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isLocalMessage {
                Spacer(minLength: 48)
                bubble
                avatar
            } else {
                // 微信式身份识别：每条远端消息都保留头像。
                // 头像固定在同一轨道，换人时由列表层级拉开段落。
                avatar
                bubble
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(participantDisplayName)：\(message.content)")
        .accessibilityIdentifier("chat.message.\(message.id)")
    }

    private var bubble: some View {
        VStack(alignment: isLocalMessage ? .trailing : .leading, spacing: 5) {
            Text(message.content)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .lineSpacing(3)
                .foregroundStyle(bubbleTextColor)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleSurface)
                .clipShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(bubbleBorder, lineWidth: 0.7)
                }
                .frame(maxWidth: 278, alignment: isLocalMessage ? .trailing : .leading)

            if message.status == .sending {
                ProgressView()
                    .controlSize(.mini)
                    .tint(visual.textTertiary)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("正在发送")
            } else if !groupedWithNext {
                Text(message.createdAt, style: .time)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(visual.textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        ChatParticipantAvatar(
            participant: message.participant,
            imageData: avatarStore.imageData(for: message.participant),
            size: 32
        )
    }

    private var bubbleSurface: Color {
        if isLocalMessage { return Theme.v2InkSurface }
        return switch message.participant {
        case .user:
            Theme.v2CoralSoft
        case .developer:
            Theme.v2Lavender.opacity(0.55)
        case .xiaomao:
            Theme.v2Paper
        }
    }

    private var bubbleTextColor: Color {
        isLocalMessage ? Color.white : Theme.v2Ink
    }

    private var bubbleBorder: Color {
        isLocalMessage ? .clear : Theme.v2Line.opacity(0.86)
    }
}
