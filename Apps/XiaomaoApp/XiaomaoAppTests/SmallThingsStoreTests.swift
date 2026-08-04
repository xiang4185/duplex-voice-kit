import XCTest
@testable import XiaomaoApp

@MainActor
final class SmallThingsStoreTests: XCTestCase {
    func testInitialLedgerAmountsAndRemainingIncludePending() {
        let store = SmallThingsStore()
        XCTAssertEqual(store.approvedAmount, 32, accuracy: 0.001)
        XCTAssertEqual(store.pendingAmount, 12, accuracy: 0.001)
        XCTAssertEqual(store.remainingAmount, 8, accuracy: 0.001)
    }

    func testEmptyNoteCannotSave() { XCTAssertFalse(SmallThingsStore(entries: []).addNote(title: " ", body: "", imageData: nil)) }

    func testInvalidAndOverBudgetExpensesCannotSave() {
        let store = SmallThingsStore(entries: [])
        XCTAssertFalse(store.addExpense(purpose: "测试", amountText: "1.234", note: ""))
        XCTAssertFalse(store.addExpense(purpose: "测试", amountText: "53", note: ""))
    }

    func testNewExpenseIsPending() {
        let store = SmallThingsStore(entries: [])
        XCTAssertTrue(store.addExpense(purpose: "纸笔", amountText: "2.50", note: ""))
        XCTAssertEqual(store.entries.first?.expenseStatus, .pending)
    }

    func testReactionToggles() {
        let entry = SmallThingEntry(type: .note, requester: .me, body: "a")
        let store = SmallThingsStore(entries: [entry])
        store.toggleReaction(entryID: entry.id)
        XCTAssertTrue(store.entries[0].reacted)
    }

    func testEmptyCommentCannotSendAndReplyUsesCommentID() {
        let first = SmallThingComment(author: .partner, text: "一")
        let second = SmallThingComment(author: .partner, text: "二")
        let entry = SmallThingEntry(type: .note, requester: .me, body: "a", comments: [first, second])
        let store = SmallThingsStore(entries: [entry])
        XCTAssertFalse(store.addComment(entryID: entry.id, text: " "))
        XCTAssertTrue(store.addReply(entryID: entry.id, commentID: second.id, replyTo: .partner, text: "准确回复"))
        XCTAssertTrue(store.entries[0].comments[0].replies.isEmpty)
        XCTAssertEqual(store.entries[0].comments[1].replies.first?.text, "准确回复")
    }

    func testApprovalMessagesPersistForBothOutcomes() {
        let approved = SmallThingEntry(type: .expense, requester: .partner, title: "A", amount: 1, expenseStatus: .pending)
        let rejected = SmallThingEntry(type: .expense, requester: .partner, title: "B", amount: 1, expenseStatus: .pending)
        let store = SmallThingsStore(entries: [approved, rejected])
        store.review(entryID: approved.id, status: .approved, message: "点头留言")
        store.review(entryID: rejected.id, status: .rejected, message: "再想想留言")
        XCTAssertEqual(store.entries.first(where: { $0.id == approved.id })?.approvalMessage, "点头留言")
        XCTAssertEqual(store.entries.first(where: { $0.id == rejected.id })?.approvalMessage, "再想想留言")
    }

    func testUndoRestoresStatusMessageQueueAndAmount() {
        let entry = SmallThingEntry(type: .expense, requester: .partner, title: "A", amount: 12, expenseStatus: .pending, approvalMessage: "原留言")
        let store = SmallThingsStore(entries: [entry])
        store.review(entryID: entry.id, status: .approved, message: "新留言")
        XCTAssertEqual(store.approvedAmount, 12)
        store.undoLastReview()
        XCTAssertEqual(store.entries[0].expenseStatus, .pending)
        XCTAssertEqual(store.entries[0].approvalMessage, "原留言")
        XCTAssertEqual(store.pendingApprovals.count, 1)
        XCTAssertEqual(store.approvedAmount, 0)
    }

    func testApprovalQueueOnlyContainsPartnerPendingExpenses() {
        let entries = [
            SmallThingEntry(type: .expense, requester: .partner, amount: 1, expenseStatus: .pending),
            SmallThingEntry(type: .expense, requester: .me, amount: 1, expenseStatus: .pending),
            SmallThingEntry(type: .expense, requester: .partner, amount: 1, expenseStatus: .approved),
            SmallThingEntry(type: .note, requester: .partner, body: "x")
        ]
        XCTAssertEqual(SmallThingsStore(entries: entries).pendingApprovals.count, 1)
    }
}
