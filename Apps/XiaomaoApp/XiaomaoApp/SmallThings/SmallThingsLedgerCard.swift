import SwiftUI

struct SmallThingsLedgerCard: View {
    @ObservedObject var store: SmallThingsStore
    let addExpense: () -> Void
    let openApprovals: () -> Void
    let openBinding: () -> Void
    @Environment(\.appVisualMode) private var visualMode

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            header
            summary
            actions
            footer
        }
        .padding(18)
        .background(visual.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous)
                .stroke(visual.border.opacity(0.62), lineWidth: 0.8)
        }
        .shadow(color: visual.shadow.opacity(0.45), radius: 12, y: 5)
        .accessibilityIdentifier("smallThings.ledger")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                Text("52 元小本本")
                    .font(Theme.title3Font)
                    .foregroundStyle(visual.textPrimary)
                Text("一起记，也一起确认")
                    .font(Theme.captionFont)
                    .foregroundStyle(visual.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.small)
            if !store.pendingApprovals.isEmpty {
                Text("待确认 \(store.pendingApprovals.count)")
                    .font(Theme.captionFont.weight(.semibold))
                    .foregroundStyle(visual.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(visual.primarySoft, in: Capsule())
                    .accessibilityLabel("待审批 \(store.pendingApprovals.count) 笔")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还剩下")
                .font(Theme.captionFont)
                .foregroundStyle(visual.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(store.remainingAmount, format: .number.precision(.fractionLength(2)))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(visual.textPrimary)
                Text("元")
                    .font(Theme.subheadFont)
                    .foregroundStyle(visual.textSecondary)
            }
            Text("已确认 \(store.approvedAmount.formatted(.number.precision(.fractionLength(2)))) · 待确认 \(store.pendingAmount.formatted(.number.precision(.fractionLength(2))))")
                .font(Theme.captionFont)
                .foregroundStyle(visual.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("还剩下 \(store.remainingAmount.formatted(.number.precision(.fractionLength(2)))) 元，已确认 \(store.approvedAmount.formatted(.number.precision(.fractionLength(2)))) 元，待确认 \(store.pendingAmount.formatted(.number.precision(.fractionLength(2)))) 元")
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.small) {
                addExpenseButton
                approvalsButton
            }
            VStack(spacing: Theme.Spacing.xSmall) {
                addExpenseButton
                approvalsButton
            }
        }
    }

    private var addExpenseButton: some View {
        Button(action: addExpense) {
            Label("记一笔", systemImage: "square.and.pencil")
                .font(Theme.headlineFont)
                .frame(maxWidth: .infinity, minHeight: Theme.buttonMinimumHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(visual.primary)
        .accessibilityIdentifier("smallThings.ledger.addExpense")
        .accessibilityHint("进入记账模式")
    }

    private var approvalsButton: some View {
        Button(action: openApprovals) {
            Label("等你点头", systemImage: "checkmark.seal")
                .font(Theme.headlineFont)
                .frame(maxWidth: .infinity, minHeight: Theme.buttonMinimumHeight)
        }
        .buttonStyle(.bordered)
        .tint(visual.primary)
        .accessibilityIdentifier("smallThings.ledger.pendingApproval")
        .accessibilityValue("\(store.pendingApprovals.count) 笔待审批")
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.small) {
            bindingButton
            Spacer(minLength: Theme.Spacing.xSmall)
            explanation
        }
    }

    private var bindingButton: some View {
        Button(action: openBinding) {
            Label(
                store.isDemoBound
                    ? (store.isProduction ? "已绑定" : "已离线绑定")
                    : (store.isProduction ? "绑定关系" : "离线绑定"),
                systemImage: store.isDemoBound ? "link.circle.fill" : "link.circle"
            )
            .font(Theme.captionFont)
        }
        .buttonStyle(.plain)
        .foregroundStyle(visual.primary)
        .accessibilityIdentifier("smallThings.binding")
    }

    private var explanation: some View {
        Text("谁都能记，记了等对方点头")
            .font(.caption2)
            .foregroundStyle(visual.textTertiary)
    }
}
