import SwiftUI

struct ChatComposerView: View {
    @Binding var draft: String
    let canSend: Bool
    let isBusy: Bool
    let isSending: Bool
    let characterLimit: Int
    let send: () -> Void

    @FocusState.Binding var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    var body: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("说点什么", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .font(Theme.bodyFont)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, minHeight: Theme.controlMinimumSize)
                    .foregroundStyle(Theme.v2Ink)
                    .background(Theme.v2Paper.opacity(0.86))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                        .stroke(
                            inputFocused ? Theme.v2Coral.opacity(0.72) : Theme.v2Line.opacity(0.8),
                            lineWidth: inputFocused ? 1.2 : 0.7
                        )
                    }
                    .shadow(
                        color: inputFocused ? Theme.v2Coral.opacity(0.12) : .clear,
                        radius: 10,
                        y: 3
                    )
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: Theme.Motion.quick),
                        value: inputFocused
                    )
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: 20,
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

                Button {
                    WarmHaptics.action()
                    send()
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 17, weight: .bold))
                                .symbolEffect(.bounce, value: canSend)
                        }
                    }
                    .frame(
                        minWidth: Theme.controlMinimumSize,
                        minHeight: Theme.controlMinimumSize
                    )
                    .foregroundStyle(canSend ? Color.white : visual.textSecondary.opacity(0.78))
                    .background(canSend ? Theme.v2Coral : visual.textSecondary.opacity(0.13))
                    .clipShape(Circle())
                    .scaleEffect(canSend && !reduceMotion ? 1 : 0.92)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.68),
                        value: canSend
                    )
                }
                .buttonStyle(V2ComposerSendButtonStyle())
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
                .foregroundStyle(isOverLimit ? Theme.v2Coral : visual.textSecondary)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(8)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var shouldShowCharacterCount: Bool {
        draft.count >= characterLimit - 40
    }

    private var isOverLimit: Bool {
        draft.count > characterLimit
    }
}

private struct V2ComposerSendButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.88)
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.62),
                value: configuration.isPressed
            )
    }
}
