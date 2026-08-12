import SwiftUI

struct ChatTypingIndicator: View {
    @Environment(\.appVisualMode) private var visualMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            PrivacyAvatar(size: 32, tappable: false, style: .thumbnail)
                .frame(width: 32, height: 32)
                .background(Theme.v2PaperMuted, in: Circle())
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.v2Line, lineWidth: 0.7))
                .accessibilityHidden(true)

            HStack(spacing: Theme.Spacing.xSmall) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Theme.v2Coral)
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
                    .foregroundStyle(Theme.v2Ink.opacity(0.62))
            }
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 10)
            .background(Theme.v2Paper)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.v2Line.opacity(0.86), lineWidth: 0.7)
            }

            Spacer(minLength: Theme.Spacing.xxxLarge)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在等待回复")
        .accessibilityIdentifier("chat.typing")
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}
