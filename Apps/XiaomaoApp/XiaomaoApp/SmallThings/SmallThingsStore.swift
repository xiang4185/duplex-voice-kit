import Combine
import Foundation

@MainActor
final class SmallThingsStore: ObservableObject {
    static let ledgerLimit = 52.0

    @Published private(set) var entries: [SmallThingEntry]
    @Published private(set) var isDemoBound = false
    @Published private(set) var lastUndo: SmallThingApprovalUndo?
    @Published var validationMessage: String?

    init(entries: [SmallThingEntry]? = nil) {
        self.entries = entries ?? Self.mockEntries()
    }

    var approvedAmount: Double {
        entries.filter { $0.type == .expense && $0.expenseStatus == .approved }.reduce(0) { $0 + $1.amount }
    }

    var pendingAmount: Double {
        entries.filter { $0.type == .expense && $0.expenseStatus == .pending }.reduce(0) { $0 + $1.amount }
    }

    var remainingAmount: Double {
        max(0, Self.ledgerLimit - approvedAmount - pendingAmount)
    }

    var approvedRatio: Double {
        min(1, approvedAmount / Self.ledgerLimit)
    }

    var pendingApprovals: [SmallThingEntry] {
        entries
            .filter { $0.type == .expense && $0.requester == .partner && $0.expenseStatus == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var sortedEntries: [SmallThingEntry] {
        entries.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func addNote(title: String, body: String, imageData: Data?) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty || !cleanBody.isEmpty else {
            validationMessage = "标题或正文至少填写一项"
            return false
        }
        entries.append(SmallThingEntry(type: .note, requester: .me, title: cleanTitle, body: cleanBody, imageData: imageData))
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
        guard let amount = Self.validAmount(from: amountText), amount <= remainingAmount else {
            validationMessage = "金额需大于 0、不超过当前可用金额，并最多保留两位小数"
            return false
        }
        entries.append(SmallThingEntry(
            type: .expense,
            requester: .me,
            title: cleanPurpose,
            body: note.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            expenseStatus: .pending
        ))
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
        guard !clean.isEmpty, let index = entries.firstIndex(where: { $0.id == entryID }) else { return false }
        entries[index].comments.append(SmallThingComment(author: .me, text: clean))
        return true
    }

    @discardableResult
    func addReply(entryID: UUID, commentID: UUID, replyTo: SmallThingRequester, text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let commentIndex = entries[entryIndex].comments.firstIndex(where: { $0.id == commentID }) else { return false }
        entries[entryIndex].comments[commentIndex].replies.append(
            SmallThingReply(author: .me, text: clean, replyToAuthor: replyTo)
        )
        return true
    }

    func review(entryID: UUID, status: SmallThingExpenseStatus, message: String) {
        guard status != .pending, let index = entries.firstIndex(where: { $0.id == entryID }),
              entries[index].requester == .partner, entries[index].expenseStatus == .pending else { return }
        lastUndo = SmallThingApprovalUndo(
            entryID: entryID,
            previousStatus: .pending,
            previousMessage: entries[index].approvalMessage
        )
        entries[index].expenseStatus = status
        entries[index].approvalMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func undoLastReview() {
        guard let undo = lastUndo, let index = entries.firstIndex(where: { $0.id == undo.entryID }) else { return }
        entries[index].expenseStatus = undo.previousStatus
        entries[index].approvalMessage = undo.previousMessage
        lastUndo = nil
    }

    @discardableResult
    func bindDemo(code: String) -> Bool {
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else {
            validationMessage = "请输入六位数字"
            return false
        }
        isDemoBound = true
        validationMessage = nil
        return true
    }

    static func validAmount(from text: String) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Double(clean), value > 0 else { return nil }
        return value
    }

    private static func mockEntries() -> [SmallThingEntry] {
        let now = Date()
        let thread = SmallThingComment(
            author: .partner,
            text: "下次也记得告诉我",
            replies: [SmallThingReply(author: .me, text: "好，第一时间分享", replyToAuthor: .partner)]
        )
        return [
            SmallThingEntry(createdAt: now.addingTimeInterval(-60), type: .expense, requester: .partner, title: "奶茶", body: "同款第二杯半价", amount: 12, expenseStatus: .pending),
            SmallThingEntry(createdAt: now.addingTimeInterval(-120), type: .note, requester: .me, body: "地铁站看到一只橘猫，像在等谁。", reacted: true, comments: [thread]),
            SmallThingEntry(createdAt: now.addingTimeInterval(-180), type: .expense, requester: .me, title: "电影票", body: "想一起看的那场", amount: 20, expenseStatus: .approved, approvalMessage: "值得，看！"),
            SmallThingEntry(createdAt: now.addingTimeInterval(-240), type: .note, requester: .partner, body: "第一次自己煮了汤，虽然有点咸。"),
            SmallThingEntry(createdAt: now.addingTimeInterval(-300), type: .expense, requester: .me, title: "明信片", body: "寄了一张", amount: 12, expenseStatus: .approved, approvalMessage: "收到了"),
            SmallThingEntry(createdAt: now.addingTimeInterval(-360), type: .note, requester: .me, title: "今晚的晚霞", body: "想让你看到同一片。", imageData: Data([0x01]))
        ]
    }
}
