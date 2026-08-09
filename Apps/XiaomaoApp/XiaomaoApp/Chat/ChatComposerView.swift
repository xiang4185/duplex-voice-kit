import SwiftUI

struct ChatComposerView: View {
    @Binding var draft: String
    let canSend: Bool
    let isBusy: Bool
    let isSending: Bool
    let characterLimit: Int
    let send: () -> Void

    @FocusState.Binding var inputFocused: Bool
    @Environment(\.appVisualMode) private var visualMode

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    var body: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
                TextField("说点什么", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .font(Theme.bodyFont)
                    .padding(.horizontal, Theme.Spacing.small)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: Theme.controlMinimumSize)
                    .background(visual.surface.opacity(0.72))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.medium,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.medium,
                            style: .continuous
                        )
                        .stroke(visual.border.opacity(0.5), lineWidth: 0.7)
                    }
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.medium,
                            style: .continuous
                        )
                    )
                    .onTapGesture {
                        guard !isBusy else { return }
                        inputFocused = true
                    }
                    .disabled(isBusy)
                    .accessibilityLabel("聊天输入框")
                    .accessibilityIdentifier("chat.input")

                Button(action: send) {
                    Group {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 17, weight: .bold))
                        }
                    }
                    .frame(
                        minWidth: Theme.controlMinimumSize,
                        minHeight: Theme.controlMinimumSize
                    )
                    .foregroundStyle(canSend ? visual.onPrimary : visual.textTertiary)
                    .background(canSend ? visual.primary : visual.primarySoft)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(isSending ? "正在发送" : "发送")
                .accessibilityIdentifier("chat.send")
            }

            if shouldShowCharacterCount {
                HStack {
                    Text(isOverLimit ? "已超过 \(characterLimit) 字符" : "接近字数上限")
                    Spacer()
                    Text("\(draft.count)/\(characterLimit)")
                }
                .font(Theme.captionFont)
                .foregroundStyle(isOverLimit ? Theme.danger : visual.textSecondary)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.top, 10)
        .padding(.bottom, Theme.Spacing.small)
        .background(.ultraThinMaterial)
        .background(visual.glassTint)
        .overlay(alignment: .top) { Divider().overlay(visual.border.opacity(0.35)) }
    }

    private var shouldShowCharacterCount: Bool {
        draft.count >= characterLimit - 40
    }

    private var isOverLimit: Bool {
        draft.count > characterLimit
    }
}
