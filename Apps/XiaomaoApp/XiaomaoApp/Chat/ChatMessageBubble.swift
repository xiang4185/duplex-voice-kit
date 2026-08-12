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
        HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
            if isLocalMessage {
                Spacer(minLength: 44)
                bubble
                avatar
            } else {
                // 微信式布局：每条消息都保留头像，连续消息仅收紧气泡间距。
                avatar
                bubble
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(participantDisplayName)：\(message.content)")
        .accessibilityIdentifier("chat.message.\(message.id)")
    }

    private var bubble: some View {
        VStack(
            alignment: isLocalMessage ? .trailing : .leading,
            spacing: 5
        ) {
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
            Text("客")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(visual.textPrimary)
                .frame(width: 34, height: 34)
                .background(visual.primarySoft)
                .clipShape(Circle())
                .accessibilityHidden(true)
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
