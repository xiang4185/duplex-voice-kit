import SwiftUI

struct ChatTypingIndicator: View {
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xSmall) {
            Image(systemName: "cat.fill")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(Theme.primary)
                .background(Theme.primarySoft)
                .clipShape(Circle())
                .accessibilityHidden(true)

            HStack(spacing: Theme.Spacing.xSmall) {
                ProgressView()
                    .controlSize(.small)
                Text("小猫正在回复")
                    .font(Theme.footnoteFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 10)
            .background(Theme.assistantMessageSurface)
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
        .accessibilityLabel("小猫正在回复")
        .accessibilityIdentifier("chat.typing")
    }
}
