import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    var localParticipant: ChatParticipant = .user
    var groupedWithPrevious: Bool = false
    var groupedWithNext: Bool = false
    @Environment(\.appVisualMode) private var visualMode
    @State private var showsTimestamp = false

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
            } else if !groupedWithNext && showsTimestamp {
                Text(message.createdAt, style: .time)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(visual.textTertiary)
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !groupedWithNext else { return }
            withAnimation(.easeOut(duration: Theme.Motion.quick)) {
                showsTimestamp.toggle()
            }
        }
        .accessibilityHint(groupedWithNext ? "" : "轻点显示或隐藏发送时间")
    }

    @ViewBuilder
    private var avatar: some View {
        switch message.participant {
        case .developer:
            humanAvatar(
                foreground: Theme.v2InkSurface,
                background: Theme.v2Lavender.opacity(0.72)
            )
        case .xiaomao:
            PrivacyAvatar(
                size: 32,
                tappable: false,
                style: .thumbnail
            )
                .frame(width: 32, height: 32)
                .background(Theme.v2PaperMuted, in: Circle())
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.v2Line, lineWidth: 0.7))
                .accessibilityHidden(true)
        case .user:
            humanAvatar(
                foreground: Theme.v2Ink.opacity(0.66),
                background: Theme.v2CoralSoft
            )
        }
    }

    private func humanAvatar(foreground: Color, background: Color) -> some View {
        Image(systemName: "person.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 32, height: 32)
            .background(background)
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.v2Line, lineWidth: 0.7))
            .accessibilityHidden(true)
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
