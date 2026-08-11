import XCTest
@testable import XiaomaoApp

@MainActor
final class SmallThingsStoreTests: XCTestCase {
    func testInitialLedgerAmountsAndRemainingIncludePending() {
        let store = SmallThingsStore()

        XCTAssertEqual(store.approvedAmount, 32, accuracy: 0.001)
        XCTAssertEqual(store.pendingAmount, 12, accuracy: 0.001)
        XCTAssertEqual(store.remainingAmount, 8, accuracy: 0.001)
        XCTAssertEqual(store.approvedRatio, 32.0 / 52.0, accuracy: 0.001)
    }

    func testLedgerLimitCanBeAdjustedWithoutTouchingEntries() {
        let store = SmallThingsStore()
        let originalEntries = store.entries

        XCTAssertTrue(store.adjustLedgerLimit(to: 80))
        XCTAssertEqual(store.ledgerLimit, 80, accuracy: 0.001)
        XCTAssertEqual(store.remainingAmount, 36, accuracy: 0.001)
        XCTAssertEqual(store.entries, originalEntries)
    }

    func testLedgerLimitCannotDropBelowUsedAndPendingAmount() {
        let store = SmallThingsStore()

        XCTAssertFalse(store.adjustLedgerLimit(to: 40))
        XCTAssertEqual(store.ledgerLimit, 52, accuracy: 0.001)
        XCTAssertEqual(store.validationMessage, "额度不能低于已使用和待确认金额")
    }

    func testInitialMockContainsAllVisualStatesAndSortedTimeline() {
        let store = SmallThingsStore()

        XCTAssertTrue(store.entries.contains { $0.type == .note && $0.imageData != nil })
        XCTAssertTrue(store.entries.contains { $0.expenseStatus == .pending })
        XCTAssertTrue(store.entries.contains { $0.expenseStatus == .approved })
        XCTAssertTrue(store.entries.contains { $0.expenseStatus == .rejected })
        XCTAssertTrue(store.entries.contains { entry in
            entry.comments.contains { $0.replies.count >= 2 }
        })
        XCTAssertEqual(store.sortedEntries, store.sortedEntries.sorted { $0.createdAt > $1.createdAt })
    }

    func testNewNoteAppearsAndTrimsContent() {
        let store = SmallThingsStore(entries: [])

        XCTAssertTrue(store.addNote(title: "  晚风  ", body: "  很轻  ", imageData: nil))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].title, "晚风")
        XCTAssertEqual(store.entries[0].body, "很轻")
        XCTAssertEqual(store.entries[0].type, .note)
        XCTAssertEqual(store.entries[0].requester, .me)
    }

    func testEmptyNoteCannotSave() {
        let store = SmallThingsStore(entries: [])

        XCTAssertFalse(store.addNote(title: " ", body: "\n", imageData: nil))
        XCTAssertEqual(store.validationMessage, "标题或正文至少填写一项")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testImageDataEntersNewNote() {
        let store = SmallThingsStore(entries: [])
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        XCTAssertTrue(store.addNote(title: "图", body: "", imageData: imageData))
        XCTAssertEqual(store.entries.first?.imageData, imageData)
    }

    func testNewExpenseIsPendingAndUpdatesLedger() {
        let store = SmallThingsStore(entries: [])

        XCTAssertTrue(store.addExpense(purpose: " 纸笔 ", amountText: "2.50", note: "  写字  "))
        XCTAssertEqual(store.entries.first?.expenseStatus, .pending)
        XCTAssertEqual(store.entries.first?.reviewer, .partner)
        XCTAssertEqual(store.entries.first?.title, "纸笔")
        XCTAssertEqual(store.entries.first?.body, "写字")
        XCTAssertEqual(store.pendingAmount, 2.5, accuracy: 0.001)
        XCTAssertEqual(store.remainingAmount, 49.5, accuracy: 0.001)
    }

    func testMissingPurposeCannotSaveExpense() {
        let store = SmallThingsStore(entries: [])

        XCTAssertFalse(store.addExpense(purpose: " ", amountText: "2", note: ""))
        XCTAssertEqual(store.validationMessage, "请填写用途")
    }

    func testInvalidExpenseFormatsCannotSave() {
        let store = SmallThingsStore(entries: [])

        for amount in ["", "0", "-1", "1.234", ".5", "abc"] {
            XCTAssertFalse(store.addExpense(purpose: "测试", amountText: amount, note: ""), amount)
        }
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testOverBudgetExpenseCannotSave() {
        let store = SmallThingsStore(entries: [])

        XCTAssertFalse(store.addExpense(purpose: "测试", amountText: "52.01", note: ""))
        XCTAssertEqual(store.validationMessage, "金额不能超过当前可用金额")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testReactionTogglesOnAndOff() {
        let entry = SmallThingEntry(type: .note, requester: .me, body: "a")
        let store = SmallThingsStore(entries: [entry])

        store.toggleReaction(entryID: entry.id)
        XCTAssertTrue(store.entries[0].reacted)
        store.toggleReaction(entryID: entry.id)
        XCTAssertFalse(store.entries[0].reacted)
    }

    func testEmptyCommentCannotSend() {
        let entry = SmallThingEntry(type: .note, requester: .me, body: "a")
        let store = SmallThingsStore(entries: [entry])

        XCTAssertFalse(store.addComment(entryID: entry.id, text: " \n "))
        XCTAssertTrue(store.entries[0].comments.isEmpty)
    }

    func testNewCommentDisplaysImmediately() {
        let entry = SmallThingEntry(type: .note, requester: .me, body: "a")
        let store = SmallThingsStore(entries: [entry])

        XCTAssertTrue(store.addComment(entryID: entry.id, text: "  我也看到了  "))
        XCTAssertEqual(store.entries[0].comments.count, 1)
        XCTAssertEqual(store.entries[0].comments[0].text, "我也看到了")
        XCTAssertEqual(store.entries[0].comments[0].author, .me)
    }

    func testReplyUsesSpecifiedCommentAndAuthor() {
        let first = SmallThingComment(author: .partner, text: "一")
        let second = SmallThingComment(author: .partner, text: "二")
        let entry = SmallThingEntry(
            type: .note,
            requester: .me,
            body: "a",
            comments: [first, second]
        )
        let store = SmallThingsStore(entries: [entry])

        XCTAssertTrue(
            store.addReply(
                entryID: entry.id,
                commentID: second.id,
                replyTo: .partner,
                text: "准确回复"
            )
        )
        XCTAssertTrue(store.entries[0].comments[0].replies.isEmpty)
        XCTAssertEqual(store.entries[0].comments[1].replies.first?.text, "准确回复")
        XCTAssertEqual(store.entries[0].comments[1].replies.first?.replyToAuthor, .partner)
    }

    func testMultipleRepliesKeepFlatRelationshipMetadata() {
        let comment = SmallThingComment(author: .partner, text: "根评论")
        let entry = SmallThingEntry(
            type: .note,
            requester: .me,
            body: "a",
            comments: [comment]
        )
        let store = SmallThingsStore(entries: [entry])

        XCTAssertTrue(store.addReply(entryID: entry.id, commentID: comment.id, replyTo: .partner, text: "第一轮"))
        XCTAssertTrue(store.addReply(entryID: entry.id, commentID: comment.id, replyTo: .me, text: "第二轮"))
        XCTAssertEqual(store.entries[0].comments[0].replies.count, 2)
        XCTAssertEqual(store.entries[0].comments[0].replies[0].replyToAuthor, .partner)
        XCTAssertEqual(store.entries[0].comments[0].replies[1].replyToAuthor, .me)
        XCTAssertEqual(store.entries[0].commentAndReplyCount, 3)
    }

    func testMockBindingSucceedsWithUniversalSuccessCode() {
        let store = SmallThingsStore(entries: [])

        XCTAssertTrue(store.bindDemo(code: SmallThingsStore.successfulPartnerCode))
        XCTAssertEqual(store.bindingState, .bound)
        XCTAssertEqual(store.bindingFeedback, .success)
        XCTAssertTrue(store.isDemoBound)
    }

    func testInvalidBindingCodeIsRejected() {
        let store = SmallThingsStore(entries: [])

        XCTAssertFalse(store.bindDemo(code: "000000"))
        XCTAssertEqual(store.bindingState, .unbound)
        XCTAssertEqual(store.bindingFeedback, .invalidCode)
    }

    func testBindingCodeMustBeExactlySixDigits() {
        let store = SmallThingsStore(entries: [])

        XCTAssertFalse(store.bindDemo(code: "12345"))
        XCTAssertFalse(store.bindDemo(code: "A35246"))
        XCTAssertEqual(store.validationMessage, "请输入六位数字")
    }

    func testOccupiedBindingCodeHasDistinctState() {
        let store = SmallThingsStore(entries: [])

        XCTAssertFalse(store.bindDemo(code: SmallThingsStore.occupiedPartnerCode))
        XCTAssertEqual(store.bindingFeedback, .occupied)
        XCTAssertFalse(store.isDemoBound)
    }

    func testBindingAgainReportsAlreadyBound() {
        let store = SmallThingsStore(entries: [])

        XCTAssertTrue(store.bindDemo(code: SmallThingsStore.successfulPartnerCode))
        XCTAssertFalse(store.bindDemo(code: SmallThingsStore.successfulPartnerCode))
        XCTAssertEqual(store.bindingFeedback, .alreadyBound)
        XCTAssertTrue(store.isDemoBound)
    }

    func testDemoBindingCanBeRemoved() {
        let store = SmallThingsStore(entries: [])
        XCTAssertTrue(store.bindDemo(code: SmallThingsStore.successfulPartnerCode))

        store.unbindDemo()

        XCTAssertEqual(store.bindingState, .unbound)
        XCTAssertEqual(store.bindingFeedback, .idle)
        XCTAssertFalse(store.isDemoBound)
    }

    func testApprovalQueueOnlyContainsPartnerPendingExpenses() {
        let entries = [
            SmallThingEntry(type: .expense, requester: .partner, reviewer: .me, amount: 1, expenseStatus: .pending),
            SmallThingEntry(type: .expense, requester: .me, reviewer: .partner, amount: 1, expenseStatus: .pending),
            SmallThingEntry(type: .expense, requester: .partner, reviewer: .partner, amount: 1, expenseStatus: .pending),
            SmallThingEntry(type: .expense, requester: .partner, reviewer: .me, amount: 1, expenseStatus: .approved),
            SmallThingEntry(type: .note, requester: .partner, body: "x")
        ]

        XCTAssertEqual(SmallThingsStore(entries: entries).pendingApprovals.count, 1)
    }

    func testApproveUpdatesStatusQueueAndAmounts() {
        let entry = SmallThingEntry(
            type: .expense,
            requester: .partner,
            reviewer: .me,
            title: "A",
            amount: 12,
            expenseStatus: .pending
        )
        let store = SmallThingsStore(entries: [entry])

        XCTAssertTrue(store.review(entryID: entry.id, status: .approved, message: "点头"))
        XCTAssertEqual(store.entries[0].expenseStatus, .approved)
        XCTAssertEqual(store.entries[0].approvalMessage, "点头")
        XCTAssertEqual(store.pendingApprovals.count, 0)
        XCTAssertEqual(store.pendingAmount, 0, accuracy: 0.001)
        XCTAssertEqual(store.approvedAmount, 12, accuracy: 0.001)
        XCTAssertEqual(store.remainingAmount, 40, accuracy: 0.001)
    }

    func testRejectRestoresAvailableAmountAndPersistsMessage() {
        let entry = SmallThingEntry(
            type: .expense,
            requester: .partner,
            reviewer: .me,
            title: "A",
            amount: 12,
            expenseStatus: .pending
        )
        let store = SmallThingsStore(entries: [entry])

        XCTAssertTrue(store.review(entryID: entry.id, status: .rejected, message: "  下次吧  "))
        XCTAssertEqual(store.entries[0].expenseStatus, .rejected)
        XCTAssertEqual(store.entries[0].approvalMessage, "下次吧")
        XCTAssertEqual(store.pendingAmount, 0, accuracy: 0.001)
        XCTAssertEqual(store.remainingAmount, 52, accuracy: 0.001)
    }

    func testReviewRejectsSelfRequestedOrNonPendingEntries() {
        let mine = SmallThingEntry(type: .expense, requester: .me, reviewer: .partner, amount: 1, expenseStatus: .pending)
        let approved = SmallThingEntry(type: .expense, requester: .partner, reviewer: .me, amount: 1, expenseStatus: .approved)
        let store = SmallThingsStore(entries: [mine, approved])

        XCTAssertFalse(store.review(entryID: mine.id, status: .approved, message: ""))
        XCTAssertFalse(store.review(entryID: approved.id, status: .rejected, message: ""))
        XCTAssertNil(store.lastUndo)
    }

    func testUndoRestoresStatusMessageQueueAndAmount() {
        let entry = SmallThingEntry(
            type: .expense,
            requester: .partner,
            reviewer: .me,
            title: "A",
            amount: 12,
            expenseStatus: .pending,
            approvalMessage: "原留言"
        )
        let store = SmallThingsStore(entries: [entry])
        XCTAssertTrue(store.review(entryID: entry.id, status: .approved, message: "新留言"))
        XCTAssertEqual(store.approvedAmount, 12, accuracy: 0.001)

        XCTAssertTrue(store.undoLastReview())

        XCTAssertEqual(store.entries[0].expenseStatus, .pending)
        XCTAssertEqual(store.entries[0].approvalMessage, "原留言")
        XCTAssertEqual(store.pendingApprovals.count, 1)
        XCTAssertEqual(store.approvedAmount, 0, accuracy: 0.001)
        XCTAssertEqual(store.pendingAmount, 12, accuracy: 0.001)
        XCTAssertEqual(store.remainingAmount, 40, accuracy: 0.001)
        XCTAssertNil(store.lastUndo)
    }

    func testAllApprovalsCompleteAfterFinalDecision() {
        let entry = SmallThingEntry(
            type: .expense,
            requester: .partner,
            reviewer: .me,
            title: "A",
            amount: 1,
            expenseStatus: .pending
        )
        let store = SmallThingsStore(entries: [entry])

        XCTAssertEqual(store.pendingApprovals.count, 1)
        XCTAssertTrue(store.review(entryID: entry.id, status: .approved, message: ""))
        store.discardUndo()

        XCTAssertTrue(store.pendingApprovals.isEmpty)
        XCTAssertNil(store.lastUndo)
    }
}
