import Combine
import Foundation

@MainActor
final class SmallThingsStore: ObservableObject {
    static let ledgerLimit = 52.0
    static let localBindingCode = "842971"
    static let successfulPartnerCode = "135246"
    static let occupiedPartnerCode = "246810"

    @Published private(set) var entries: [SmallThingEntry]
    @Published private(set) var bindingState: SmallThingBindingState
    @Published private(set) var bindingFeedback: SmallThingBindingFeedback = .idle
    @Published private(set) var lastUndo: SmallThingApprovalUndo?
    @Published var validationMessage: String?

    init(
        entries: [SmallThingEntry]? = nil,
        bindingState: SmallThingBindingState = .unbound
    ) {
        self.entries = entries ?? Self.mockEntries()
        self.bindingState = bindingState
    }

    var isDemoBound: Bool {
        bindingState == .bound
    }

    var approvedAmount: Double {
        entries
            .filter { $0.type == .expense && $0.expenseStatus == .approved }
            .reduce(0) { $0 + $1.amount }
    }

    var pendingAmount: Double {
        entries
            .filter { $0.type == .expense && $0.expenseStatus == .pending }
            .reduce(0) { $0 + $1.amount }
    }

    var remainingAmount: Double {
        max(0, Self.ledgerLimit - approvedAmount - pendingAmount)
    }

    var approvedRatio: Double {
        min(1, approvedAmount / Self.ledgerLimit)
    }

    var pendingApprovals: [SmallThingEntry] {
        entries
            .filter {
                $0.type == .expense
                    && $0.requester == .partner
                    && $0.expenseStatus == .pending
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var sortedEntries: [SmallThingEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    func entry(id: UUID) -> SmallThingEntry? {
        entries.first { $0.id == id }
    }

    func clearValidation() {
        validationMessage = nil
    }

    func resetBindingFeedback() {
        guard bindingState == .unbound else { return }
        bindingFeedback = .idle
        validationMessage = nil
    }

    @discardableResult
    func addNote(title: String, body: String, imageData: Data?) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty || !cleanBody.isEmpty else {
            validationMessage = "标题或正文至少填写一项"
            return false
        }

        entries.append(
            SmallThingEntry(
                type: .note,
                requester: .me,
                title: cleanTitle,
                body: cleanBody,
                imageData: imageData
            )
        )
        validationMessage = nil
        return true
    }

    @discardableResult
    func addExpense(purpose: String, amountText: String, note: String) -> Bool {
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPurpose.isEmpty else {
            validationMessage = "请填写用途"
            return false
        }
        guard let amount = Self.validAmount(from: amountText) else {
            validationMessage = "金额需大于 0，并最多保留两位小数"
            return false
        }
        guard amount <= remainingAmount else {
            validationMessage = "金额不能超过当前可用金额"
            return false
        }

        entries.append(
            SmallThingEntry(
                type: .expense,
                requester: .me,
                title: cleanPurpose,
                body: note.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount,
                expenseStatus: .pending
            )
        )
        validationMessage = nil
        return true
    }

    func toggleReaction(entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].reacted.toggle()
    }

    @discardableResult
    func addComment(entryID: UUID, text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return false
        }
        entries[index].comments.append(SmallThingComment(author: .me, text: clean))
        return true
    }

    @discardableResult
    func addReply(
        entryID: UUID,
        commentID: UUID,
        replyTo: SmallThingRequester,
        text: String
    ) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let commentIndex = entries[entryIndex].comments.firstIndex(where: { $0.id == commentID }) else {
            return false
        }

        entries[entryIndex].comments[commentIndex].replies.append(
            SmallThingReply(author: .me, text: clean, replyToAuthor: replyTo)
        )
        return true
    }

    @discardableResult
    func review(
        entryID: UUID,
        status: SmallThingExpenseStatus,
        message: String
    ) -> Bool {
        guard status != .pending,
              let index = entries.firstIndex(where: { $0.id == entryID }),
              entries[index].requester == .partner,
              entries[index].expenseStatus == .pending else {
            return false
        }

        lastUndo = SmallThingApprovalUndo(
            entryID: entryID,
            previousStatus: .pending,
            previousMessage: entries[index].approvalMessage
        )
        entries[index].expenseStatus = status
        entries[index].approvalMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    @discardableResult
    func undoLastReview() -> Bool {
        guard let undo = lastUndo,
              let index = entries.firstIndex(where: { $0.id == undo.entryID }) else {
            return false
        }
        entries[index].expenseStatus = undo.previousStatus
        entries[index].approvalMessage = undo.previousMessage
        lastUndo = nil
        return true
    }

    func discardUndo() {
        lastUndo = nil
    }

    @discardableResult
    func bindDemo(code: String) -> Bool {
        guard bindingState == .unbound else {
            bindingFeedback = .alreadyBound
            validationMessage = bindingFeedback.message
            return false
        }

        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            bindingFeedback = .invalidCode
            validationMessage = "请输入六位数字"
            return false
        }

        switch code {
        case Self.successfulPartnerCode:
            bindingState = .bound
            bindingFeedback = .success
            validationMessage = nil
            return true
        case Self.occupiedPartnerCode:
            bindingFeedback = .occupied
            validationMessage = bindingFeedback.message
            return false
        default:
            bindingFeedback = .invalidCode
            validationMessage = bindingFeedback.message
            return false
        }
    }

    func unbindDemo() {
        bindingState = .unbound
        bindingFeedback = .idle
        validationMessage = nil
    }

    static func validAmount(from text: String) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Double(clean),
              value > 0 else {
            return nil
        }
        return value
    }

    private static func mockEntries() -> [SmallThingEntry] {
        let now = Date()
        let orangeCatThread = SmallThingComment(
            author: .partner,
            text: "下次拍到发我！",
            replies: [
                SmallThingReply(
                    author: .me,
                    text: "好，第一时间发你。",
                    replyToAuthor: .partner
                )
            ]
        )
        let soupThread = SmallThingComment(
            author: .partner,
            text: "下次少放半勺盐。",
            replies: [
                SmallThingReply(
                    author: .me,
                    text: "你煮的我都喝。",
                    replyToAuthor: .partner
                ),
                SmallThingReply(
                    author: .partner,
                    text: "那明天还煮。",
                    replyToAuthor: .me
                )
            ]
        )

        return [
            SmallThingEntry(
                createdAt: now.addingTimeInterval(-60),
                type: .expense,
                requester: .partner,
                title: "奶茶",
                body: "同款第二杯半价",
                amount: 12,
                expenseStatus: .pending
            ),
            SmallThingEntry(
                createdAt: now.addingTimeInterval(-120),
                type: .note,
                requester: .me,
                body: "地铁站看到一只橘猫，蹲在闸机旁边，像在等谁。",
                reacted: true,
                comments: [orangeCatThread]
            ),
            SmallThingEntry(
                createdAt: now.addingTimeInterval(-180),
                type: .expense,
                requester: .me,
                title: "电影票",
                body: "想一起看的那场",
                amount: 20,
                expenseStatus: .approved,
                approvalMessage: "值得，看！"
            ),
            SmallThingEntry(
                createdAt: now.addingTimeInterval(-240),
                type: .note,
                requester: .partner,
                body: "第一次自己煮了汤，虽然有点咸。",
                comments: [soupThread]
            ),
            SmallThingEntry(
                createdAt: now.addingTimeInterval(-300),
                type: .expense,
                requester: .me,
                title: "明信片",
                body: "寄了一张，地址是你家",
                amount: 12,
                expenseStatus: .approved,
                approvalMessage: "收到了，很好看"
            ),
            SmallThingEntry(
                createdAt: now.addingTimeInterval(-360),
                type: .note,
                requester: .me,
                title: "今晚的晚霞",
                body: "想让你看到同一片。",
                imageData: Data([0x01])
            ),
            SmallThingEntry(
                createdAt: now.addingTimeInterval(-420),
                type: .expense,
                requester: .partner,
                title: "路边花束",
                body: "先把这次留到下回",
                amount: 9,
                expenseStatus: .rejected,
                approvalMessage: "这周先缓一缓"
            )
        ]
    }
}
