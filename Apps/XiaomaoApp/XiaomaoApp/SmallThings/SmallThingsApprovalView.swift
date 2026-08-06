import SwiftUI

struct SmallThingsApprovalView: View {
    @ObservedObject var store: SmallThingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var queueIDs: [UUID] = []
    @State private var currentIndex = 0
    @State private var approvalMessage = ""
    @State private var decision: ApprovalDecision?
    @State private var undoTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            if let entry = currentEntry {
                progressHeader
                approvalCard(entry)
                Spacer(minLength: 0)
                approvalActions(entry)
            } else {
                completedState
            }
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("等你点头")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let decision {
                undoToast(decision)
                    .padding(.bottom, Theme.Spacing.large)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            if queueIDs.isEmpty {
                queueIDs = store.pendingApprovals.map(\.id)
            }
        }
        .onDisappear {
            undoTask?.cancel()
            undoTask = nil
            store.discardUndo()
        }
    }

    private var currentEntry: SmallThingEntry? {
        guard queueIDs.indices.contains(currentIndex) else { return nil }
        return store.entry(id: queueIDs[currentIndex])
    }

    private var progressHeader: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            HStack {
                Text("第 \(currentIndex + 1) 笔，共 \(queueIDs.count) 笔")
                    .font(Theme.captionFont.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("还剩 \(max(0, queueIDs.count - currentIndex)) 笔")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 7) {
                ForEach(queueIDs.indices, id: \.self) { index in
                    Capsule()
                        .fill(dotColor(at: index))
                        .frame(width: index == currentIndex ? 24 : 8, height: 8)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentIndex)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("审批进度，第 \(currentIndex + 1) 笔，共 \(queueIDs.count) 笔")
    }

    private func approvalCard(_ entry: SmallThingEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .top, spacing: Theme.Spacing.small) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                    Text(entry.title)
                        .font(Theme.title2Font)
                        .foregroundStyle(Theme.textPrimary)
                    Label(
                        "\(entry.requester.displayName) 发起 · \(entry.expenseStatusDisplayName)",
                        systemImage: "clock.fill"
                    )
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.primary)
                }
                Spacer(minLength: Theme.Spacing.small)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.amount, format: .number.precision(.fractionLength(2)))
                        .font(Theme.title1Font)
                        .foregroundStyle(Theme.primary)
                    Text("元")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "金额 \(entry.amount.formatted(.number.precision(.fractionLength(2)))) 元"
                )
            }

            if !entry.body.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text("备注")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                    Text(entry.body)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                Text("审批留言")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                TextField("你有话说（可不填）", text: $approvalMessage, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(Theme.Spacing.small)
                    .background(Theme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    }
                    .disabled(decision != nil)
            }

            if let decision {
                Label(decision.statusText, systemImage: decision.systemImage)
                    .font(Theme.headlineFont)
                    .foregroundStyle(decision.tint)
                    .smallThingsSymbolTransition(reduceMotion: reduceMotion)
                    .padding(Theme.Spacing.small)
                    .frame(maxWidth: .infinity)
                    .background(decision.tint.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .accessibilityLabel("审批结果：\(decision.statusText)，可在一秒八内撤销")
            }
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        }
        .shadow(color: Theme.shadowRaised, radius: 14, y: 7)
    }

    private func approvalActions(_ entry: SmallThingEntry) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.small) {
                rejectButton(entry)
                approveButton(entry)
            }
            VStack(spacing: Theme.Spacing.xSmall) {
                approveButton(entry)
                rejectButton(entry)
            }
        }
        .padding(.bottom, decision == nil ? 0 : 82)
    }

    private func rejectButton(_ entry: SmallThingEntry) -> some View {
        Button {
            Task { await review(entry, status: .rejected) }
        } label: {
            Label("再想想", systemImage: "arrow.uturn.backward")
                .font(Theme.headlineFont)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered)
        .tint(Theme.danger)
        .disabled(decision != nil || store.isLoading)
        .accessibilityIdentifier("smallThings.approval.reject")
    }

    private func approveButton(_ entry: SmallThingEntry) -> some View {
        Button {
            Task { await review(entry, status: .approved) }
        } label: {
            Label("点头", systemImage: "checkmark")
                .font(Theme.headlineFont)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.primary)
        .disabled(decision != nil || store.isLoading)
        .accessibilityIdentifier("smallThings.approval.approve")
    }

    private var completedState: some View {
        VStack(spacing: Theme.Spacing.large) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Theme.success)
            VStack(spacing: Theme.Spacing.xSmall) {
                Text("都看完了")
                    .font(Theme.title2Font)
                    .foregroundStyle(Theme.textPrimary)
                Text("每一笔都被认真回应，小本本又往前走了一点。")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("返回小事") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)
            .frame(maxWidth: 240)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("全部审批完成")
    }

    private func undoToast(_ decision: ApprovalDecision) -> some View {
        HStack(spacing: Theme.Spacing.medium) {
            Label(decision.toastText, systemImage: decision.systemImage)
                .font(Theme.subheadFont.weight(.semibold))
            Button("撤销") {
                Task { await undoReview() }
            }
            .font(Theme.subheadFont.weight(.bold))
            .foregroundStyle(Theme.primarySoft)
            .accessibilityIdentifier("smallThings.approval.undo")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .shadow(color: Theme.shadowOverlay, radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func review(
        _ entry: SmallThingEntry,
        status: SmallThingExpenseStatus
    ) async {
        let previousMessage = entry.approvalMessage
        guard await store.reviewPersisted(
            entryID: entry.id,
            status: status,
            message: approvalMessage
        ) else { return }

        decision = ApprovalDecision(
            entryID: entry.id,
            status: status,
            previousMessage: previousMessage
        )
        if status == .approved {
            WarmHaptics.success()
        } else {
            WarmHaptics.lowMood()
        }

        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .milliseconds(1_800))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                finalizeDecision()
            }
        }
    }

    private func undoReview() async {
        guard let decision else { return }
        undoTask?.cancel()
        undoTask = nil
        guard await store.undoLastReviewPersisted() else { return }
        approvalMessage = decision.previousMessage
        self.decision = nil
        WarmHaptics.action()
    }

    private func finalizeDecision() {
        store.discardUndo()
        approvalMessage = ""
        decision = nil
        currentIndex += 1
        undoTask = nil
    }

    private func dotColor(at index: Int) -> Color {
        if index < currentIndex { return Theme.success }
        if index == currentIndex { return Theme.primary }
        return Theme.border
    }
}

private struct ApprovalDecision: Equatable {
    let entryID: UUID
    let status: SmallThingExpenseStatus
    let previousMessage: String

    var statusText: String {
        status == .approved ? "已经点头" : "先再想想"
    }

    var toastText: String {
        status == .approved ? "已点头" : "已打回"
    }

    var systemImage: String {
        status == .approved ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill"
    }

    var tint: Color {
        status == .approved ? Theme.success : Theme.danger
    }
}
