import SwiftUI

struct SmallThingsLedgerCard: View {
    @ObservedObject var store: SmallThingsStore
    let addExpense: () -> Void
    let openApprovals: () -> Void
    let openBinding: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            header
            summary
            actions
            footer
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous)
                .stroke(Theme.border.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: Theme.shadowRaised, radius: 16, y: 8)
        .accessibilityIdentifier("smallThings.ledger")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                Text("52 元小本本")
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.textPrimary)
                Text("我和对方一起记的账")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.small)
            Label("等我看 \(store.pendingApprovals.count)", systemImage: "clock.fill")
                .font(.caption.bold())
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.primarySoft, in: Capsule())
                .accessibilityLabel("待审批 \(store.pendingApprovals.count) 笔")
        }
    }

    private var summary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.large) {
                progressRing
                amounts
            }
            VStack(spacing: Theme.Spacing.medium) {
                progressRing
                amounts
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Theme.border.opacity(0.85), lineWidth: 8)
            Circle()
                .trim(from: 0, to: store.approvedRatio)
                .stroke(
                    Theme.primary,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int((store.approvedRatio * 100).rounded()))%")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("已点头")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 78, height: 78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已点头进度 \(Int((store.approvedRatio * 100).rounded())) 百分比")
    }

    private var amounts: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            amountRow("已点头", value: store.approvedAmount, symbol: "checkmark.circle.fill")
            amountRow("等看看", value: store.pendingAmount, symbol: "clock.fill")
            amountRow("还剩下", value: store.remainingAmount, symbol: "wallet.bifold.fill")
        }
        .frame(maxWidth: .infinity)
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
        .tint(Theme.primary)
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
        .tint(Theme.primary)
        .accessibilityIdentifier("smallThings.ledger.pendingApproval")
        .accessibilityValue("\(store.pendingApprovals.count) 笔待审批")
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.small) {
                bindingButton
                Spacer(minLength: Theme.Spacing.xSmall)
                explanation
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                bindingButton
                explanation
            }
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
        .foregroundStyle(Theme.textLink)
        .accessibilityIdentifier("smallThings.binding")
    }

    private var explanation: some View {
        Text("谁都能记，记了等对方点头")
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
    }

    private func amountRow(_ title: String, value: Double, symbol: String) -> some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.primary)
                .frame(width: 18)
            Text(title)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Theme.Spacing.small)
            Text(value, format: .number.precision(.fractionLength(2)))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
            Text("元")
                .foregroundStyle(Theme.textSecondary)
        }
        .font(Theme.subheadFont)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value.formatted(.number.precision(.fractionLength(2)))) 元")
    }
}
