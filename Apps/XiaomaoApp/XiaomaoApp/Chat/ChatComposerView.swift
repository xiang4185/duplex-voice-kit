import SwiftUI

struct ChatComposerView: View {
    @Binding var draft: String
    let canSend: Bool
    let isBusy: Bool
    let isSending: Bool
    let characterLimit: Int
    let send: () -> Void

    @FocusState.Binding var inputFocused: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            Divider()
                .overlay(Theme.border)

            HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
                TextField("说点什么", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .font(Theme.bodyFont)
                    .padding(.horizontal, Theme.Spacing.small)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: Theme.controlMinimumSize)
                    .background(Theme.surface)
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
                        .stroke(Theme.border, lineWidth: 1)
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
                    .foregroundStyle(canSend ? Theme.onPrimary : Theme.textTertiary)
                    .background(canSend ? Theme.primary : Theme.primarySoft)
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
                .foregroundStyle(isOverLimit ? Theme.danger : Theme.textSecondary)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.top, Theme.Spacing.xSmall)
        .padding(.bottom, Theme.Spacing.small)
        .background(Theme.bgElevated)
    }

    private var shouldShowCharacterCount: Bool {
        draft.count >= characterLimit - 40
    }

    private var isOverLimit: Bool {
        draft.count > characterLimit
    }
}
