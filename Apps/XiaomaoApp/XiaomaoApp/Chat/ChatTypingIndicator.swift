import SwiftUI

struct ChatTypingIndicator: View {
    @Environment(\.appVisualMode) private var visualMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xSmall) {
            Image(systemName: "ellipsis.message.fill")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(visual.primary)
                .background(visual.primarySoft)
                .clipShape(Circle())
                .accessibilityHidden(true)

            HStack(spacing: Theme.Spacing.xSmall) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(visual.primary)
                            .frame(width: 5, height: 5)
                            .scaleEffect(animating ? 1 : 0.52)
                            .opacity(animating ? 1 : 0.38)
                            .animation(
                                reduceMotion
                                    ? nil
                                    : .easeInOut(duration: 0.55)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.12),
                                value: animating
                            )
                    }
                }
                .frame(width: 24)
                Text("正在等待回复")
                    .font(Theme.footnoteFont)
                    .foregroundStyle(visual.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 10)
            .background(visual.surfaceSoft)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Theme.Radius.medium,
                    style: .continuous
                )
            )

            Spacer(minLength: Theme.Spacing.xxxLarge)
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在等待回复")
        .accessibilityIdentifier("chat.typing")
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}
