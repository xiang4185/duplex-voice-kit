import SwiftUI
import Foundation

struct SmallThingEntryCard: View {
    @ObservedObject var store: SmallThingsStore
    let entry: SmallThingEntry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode
    @State private var commentsOpen = false
    @State private var commentDraft = ""
    @State private var replyTarget: SmallThingReplyTarget?
    @State private var showingImagePreview = false
    @State private var showsDeleteConfirmation = false
    @State private var hapticTrigger = 0
    @State private var hasAppeared = false
    @FocusState private var commentFocused: Bool

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            entryHeader

            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.v2Ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let imageData = entry.imageData {
                Button {
                    showingImagePreview = true
                } label: {
                    SmallThingsImageContent(imageData: imageData, height: 190)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: Theme.Radius.medium,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: Theme.Radius.medium,
                        style: .continuous
                    )
                )
                .accessibilityLabel("查看小事大图")
                .accessibilityHint("打开全屏图片预览")
                .accessibilityIdentifier("smallThings.entry.image.preview")
            }

            if !entry.approvalMessage.isEmpty {
                Label {
                    Text("审批留言：\(entry.approvalMessage)")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "quote.bubble.fill")
                }
                .font(Theme.footnoteFont)
                .foregroundStyle(Theme.v2Ink.opacity(0.62))
                .padding(Theme.Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.v2CoralSoft.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            }

            actionRow

            if commentsOpen {
                commentsSection
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 16)
        .padding(.trailing, Theme.Spacing.medium)
        .padding(.leading, Theme.Spacing.xLarge)
        .background(Theme.v2Paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.v2Line.opacity(0.88), lineWidth: 0.8)
        }
        .overlay(alignment: .leading) {
            VStack(spacing: 4) {
                Circle()
                    .fill(entry.type == .expense ? Theme.v2Coral : Theme.v2Lavender)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(Theme.v2Line)
                    .frame(width: 1)
            }
            .padding(.leading, 13)
            .padding(.vertical, 18)
        }
        .opacity(reduceMotion || hasAppeared ? 1 : 0)
        .offset(y: reduceMotion || hasAppeared ? 0 : 14)
        .scaleEffect(reduceMotion || hasAppeared ? 1 : 0.985)
        .animation(
            reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.84),
            value: hasAppeared
        )
        .onAppear { hasAppeared = true }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: commentsOpen)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .fullScreenCover(isPresented: $showingImagePreview) {
            SmallThingsImagePreview(imageData: entry.imageData)
        }
        .confirmationDialog(
            "删除这件小事？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await store.deleteEntryPersisted(entryID: entry.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，这件小事及其评论、回应会从双方时间流中移除，且无法撤销。")
        }
    }

    private var entryHeader: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                Text(entryTitle)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.v2Ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Spacing.xxSmall) {
                    Text(entry.requester.displayName)
                    Text("·")
                    Text(entry.type == .expense ? "记了一笔账" : "记了一件事")
                    Text("·")
                    Text(Self.numericDateFormatter.string(from: entry.createdAt))
                }
                .font(Theme.captionFont)
                .foregroundStyle(Theme.v2Ink.opacity(0.52))
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: Theme.Spacing.small)

            if entry.type == .expense {
                VStack(alignment: .trailing, spacing: Theme.Spacing.xSmall) {
                    Text(entry.amount, format: .number.precision(.fractionLength(2)))
                        .font(Theme.title3Font)
                        .foregroundStyle(Theme.v2Coral)
                    Text("元")
                        .font(.caption2)
                        .foregroundStyle(Theme.v2Ink.opacity(0.52))
                    if let status = entry.expenseStatus {
                        SmallThingStatusBadge(
                            status: status,
                            displayName: entry.expenseStatusDisplayName
                        )
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "金额 \(entry.amount.formatted(.number.precision(.fractionLength(2)))) 元，状态 \(entry.expenseStatusDisplayName)"
                )
            }

            Menu {
                Button("删除这件小事", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.v2Ink.opacity(0.48))
                    .frame(width: Theme.controlMinimumSize, height: Theme.controlMinimumSize)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("小事选项")
            .accessibilityIdentifier("smallThings.entry.menu")
        }
    }

    private static let numericDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    private var entryTitle: String {
        if entry.type == .expense {
            return entry.title
        }
        return entry.title.isEmpty ? entry.requester.displayName : entry.title
    }

    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.medium) {
                reactionButton
                commentsButton
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                reactionButton
                commentsButton
            }
        }
        .font(Theme.captionFont)
    }

    private var reactionButton: some View {
        Button {
            Task { await store.toggleReactionPersisted(entryID: entry.id) }
            hapticTrigger += 1
        } label: {
            Label(
                entry.reacted ? "已回应" : "回应",
                systemImage: entry.reacted ? "heart.fill" : "heart"
            )
            .smallThingsReactionTransition(
                reduceMotion: reduceMotion,
                value: entry.reacted
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(entry.reacted ? visual.primary : visual.textSecondary)
        .accessibilityValue(entry.reacted ? "已回应，再次点击可取消" : "未回应")
    }

    private var commentsButton: some View {
        Button {
            commentsOpen.toggle()
            if commentsOpen {
                replyTarget = nil
            } else {
                commentFocused = false
            }
            hapticTrigger += 1
        } label: {
            Label(
                commentsOpen ? "收起评论" : "评论 \(entry.commentAndReplyCount)",
                systemImage: commentsOpen ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"
            )
            .smallThingsSymbolTransition(reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityIdentifier("smallThings.entry.comments.toggle")
        .accessibilityValue(commentsOpen ? "已展开" : "已收起")
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            if entry.comments.isEmpty {
                Label("还没有评论，留下一句吧", systemImage: "text.bubble")
                    .font(Theme.footnoteFont)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(entry.comments) { comment in
                    commentThread(comment)
                }
            }

            if let replyTarget {
                HStack(spacing: Theme.Spacing.xSmall) {
                    Text("正在回复 \(replyTarget.author.displayName)")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("取消回复") {
                        self.replyTarget = nil
                    }
                    .font(Theme.captionFont)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textLink)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
                TextField(
                    replyTarget == nil ? "说点什么" : "回复 \(replyTarget!.author.displayName)",
                    text: $commentDraft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .focused($commentFocused)
                .padding(.horizontal, Theme.Spacing.small)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                }
                .accessibilityLabel(replyTarget == nil ? "评论内容" : "回复内容")

                Button("发送") {
                    Task { await sendComment() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .disabled(trimmedDraft.isEmpty)
                .accessibilityIdentifier("smallThings.comment.send")
            }
        }
        .padding(Theme.Spacing.small)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border.opacity(0.75), lineWidth: 1)
        }
    }

    private func commentThread(_ comment: SmallThingComment) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Button {
                selectReplyTarget(
                    commentID: comment.id,
                    targetID: comment.id,
                    author: comment.author
                )
            } label: {
                (Text(comment.author.displayName + "：")
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.primaryPressed)
                 + Text(comment.text)
                    .foregroundColor(Theme.textPrimary))
                    .font(Theme.footnoteFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(comment.author.displayName) 评论：\(comment.text)，点击回复")

            ForEach(comment.replies) { reply in
                Button {
                    selectReplyTarget(
                        commentID: comment.id,
                        targetID: reply.id,
                        author: reply.author
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(reply.author.displayName) 回复 \(reply.replyToAuthor.displayName)")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.textSecondary)
                        Text(reply.text)
                            .font(Theme.footnoteFont)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, Theme.Spacing.small)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.primarySoft)
                            .frame(width: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(reply.author.displayName) 回复 \(reply.replyToAuthor.displayName)：\(reply.text)，点击回复"
                )
            }
        }
    }

    private var trimmedDraft: String {
        commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectReplyTarget(
        commentID: UUID,
        targetID: UUID,
        author: SmallThingRequester
    ) {
        replyTarget = SmallThingReplyTarget(
            commentID: commentID,
            targetID: targetID,
            author: author
        )
        commentFocused = true
        hapticTrigger += 1
    }

    private func sendComment() async {
        let sent: Bool
        if let replyTarget {
            sent = await store.addReplyPersisted(
                entryID: entry.id,
                commentID: replyTarget.commentID,
                replyToID: replyTarget.targetID,
                replyTo: replyTarget.author,
                text: commentDraft
            )
        } else {
            sent = await store.addCommentPersisted(
                entryID: entry.id,
                text: commentDraft
            )
        }

        guard sent else { return }
        commentDraft = ""
        replyTarget = nil
        commentsOpen = true
        commentFocused = false
        hapticTrigger += 1
    }
}

private struct SmallThingStatusBadge: View {
    let status: SmallThingExpenseStatus
    let displayName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label(displayName, systemImage: status.systemImage)
            .font(.caption2.bold())
            .foregroundStyle(statusColor)
            .smallThingsSymbolTransition(reduceMotion: reduceMotion)
            .animation(
                reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.76),
                value: status
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.11), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("审批状态：\(displayName)")
    }

    private var statusColor: Color {
        switch status {
        case .pending: return Theme.primary
        case .approved: return Theme.success
        case .rejected: return Theme.danger
        }
    }
}
