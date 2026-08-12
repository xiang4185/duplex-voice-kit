import SwiftUI

struct SmallThingsLedgerCard: View {
    @ObservedObject var store: SmallThingsStore
    let addExpense: () -> Void
    let openApprovals: () -> Void
    let openBinding: () -> Void

    @State private var showLimitEditor = false
    @State private var limitDraft = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            header
            summary
            actions
            footer
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Theme.surface, Theme.surfaceWarm.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous)
                .stroke(Theme.border.opacity(0.8), lineWidth: 1)
        }
        .cardTopHighlight()
        .shadow(color: Theme.shadowRaised, radius: 18, y: 8)
        .accessibilityIdentifier("smallThings.ledger")
        .sheet(isPresented: $showLimitEditor) {
            limitEditor
                .presentationDetents([.height(250)])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            VStack(alignment: .leading, spacing: 5) {
                Text("两个人的小本本")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("总额度 ¥\(store.ledgerLimit.formatted(.number.precision(.fractionLength(0...2))))")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.small)
            VStack(alignment: .trailing, spacing: 6) {
                Label("待确认 \(store.pendingApprovals.count)", systemImage: "clock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.primarySoft, in: Capsule())
                    .accessibilityLabel("待审批 \(store.pendingApprovals.count) 笔")

                Button {
                    limitDraft = store.ledgerLimit.formatted(.number.precision(.fractionLength(0...2)))
                    store.clearValidation()
                    showLimitEditor = true
                } label: {
                    Label("调额", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textLink)
                .accessibilityIdentifier("smallThings.ledger.adjustLimit")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("还可以一起记")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(Theme.title3Font)
                    .foregroundStyle(Theme.primary)
                Text(store.remainingAmount, format: .number.precision(.fractionLength(2)))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Spacer(minLength: Theme.Spacing.small)
                progressRing
            }

            amounts
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.bgElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(Theme.border.opacity(0.75), lineWidth: 1)
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
        .frame(width: 62, height: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已点头进度 \(Int((store.approvedRatio * 100).rounded())) 百分比")
    }

    private var amounts: some View {
        HStack(spacing: Theme.Spacing.small) {
            amountRow("已点头", value: store.approvedAmount, symbol: "checkmark.circle.fill")
            Divider()
                .overlay(Theme.border)
                .frame(height: 34)
            amountRow("等待确认", value: store.pendingAmount, symbol: "clock.fill")
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
            Label("待确认", systemImage: "checkmark.seal")
                .font(Theme.subheadFont.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Theme.buttonMinimumHeight)
        }
        .buttonStyle(.bordered)
        .tint(Theme.primary)
        .accessibilityIdentifier("smallThings.ledger.pendingApproval")
        .accessibilityValue("\(store.pendingApprovals.count) 笔待审批")
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.small) {
            Divider().overlay(Theme.border)
            HStack(spacing: Theme.Spacing.small) {
                bindingButton
                Spacer(minLength: Theme.Spacing.xSmall)
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

    private var limitEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("调整额度")
                .font(Theme.title3Font)
                .foregroundStyle(Theme.textPrimary)

            Text("当前已使用和待确认共 \((store.approvedAmount + store.pendingAmount).formatted(.number.precision(.fractionLength(2)))) 元")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                Text("¥")
                    .foregroundStyle(Theme.textSecondary)
                TextField("52", text: $limitDraft)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

            if let message = store.validationMessage {
                Text(message)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.danger)
            }

            Button("保存") {
                let normalized = limitDraft.replacingOccurrences(of: ",", with: "")
                guard let value = Double(normalized) else {
                    store.validationMessage = "请输入有效额度"
                    return
                }
                if store.adjustLedgerLimit(to: value) {
                    showLimitEditor = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("smallThings.ledger.adjustLimit.save")
        }
        .padding(20)
        .background(Theme.bg.ignoresSafeArea())
    }

    private func amountRow(_ title: String, value: Double, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.primary)
                    .font(.caption)
                Text(title)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value, format: .number.precision(.fractionLength(2)))
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(Theme.captionFont)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value.formatted(.number.precision(.fractionLength(2)))) 元")
    }
}
