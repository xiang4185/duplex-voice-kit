import Foundation
import XCTest
@testable import XiaomaoApp

final class SmallThingsUIContractTests: XCTestCase {
    func testRootStartsWithLedgerAndHasNoPageTitleOrTrailingPlus() throws {
        let root = try source("XiaomaoApp/SmallThings/SmallThingsRootView.swift")

        XCTAssertFalse(root.contains(".navigationTitle(\"小事\")"))
        XCTAssertFalse(root.contains("systemName: \"plus\""))
        XCTAssertFalse(root.contains("private var header"))
        XCTAssertFalse(root.contains("和图图的小日子"))

        let ledger = try XCTUnwrap(root.range(of: "SmallThingsLedgerCard("))
        let flow = try XCTUnwrap(root.range(of: "flowHeader"))
        XCTAssertLessThan(ledger.lowerBound, flow.lowerBound, "账本卡必须早于时间流标题")
        XCTAssertTrue(root.contains(".padding(.top, Theme.Spacing.small)"))
    }

    func testLedgerHasOnlyFrozenEntryPointsAndExpenseDefault() throws {
        let root = try source("XiaomaoApp/SmallThings/SmallThingsRootView.swift")
        let ledger = try source("XiaomaoApp/SmallThings/SmallThingsLedgerCard.swift")

        XCTAssertTrue(root.contains("addExpense:"))
        XCTAssertTrue(root.contains("path.append(.composer(.expense))"))
        XCTAssertTrue(root.contains("path.append(.approval)"))
        XCTAssertTrue(root.contains("case .approval:"))
        XCTAssertFalse(root.contains(".sheet(isPresented:"), "记账与审批必须统一使用导航推进")
        XCTAssertTrue(ledger.contains("smallThings.ledger.addExpense"))
        XCTAssertTrue(ledger.contains("smallThings.ledger.pendingApproval"))
        XCTAssertTrue(ledger.contains("smallThings.binding"))
        XCTAssertFalse(ledger.contains("glassEffect"), "暖色账本卡不得使用玻璃")
    }

    func testComposerIsCustomWarmLayoutWithOneSaveAction() throws {
        let composer = try source("XiaomaoApp/SmallThings/SmallThingComposerView.swift")

        XCTAssertFalse(composer.contains("Form"))
        XCTAssertFalse(composer.contains("cancellationAction"))
        XCTAssertFalse(composer.contains("confirmationAction"))
        XCTAssertEqual(composer.components(separatedBy: "Text(\"保存\")").count - 1, 1)
        XCTAssertTrue(composer.contains("smallThings.form.type.note"))
        XCTAssertTrue(composer.contains("smallThings.form.type.expense"))
        XCTAssertTrue(composer.contains(".pickerStyle(.segmented)"))
        XCTAssertTrue(composer.contains(".frame(maxWidth: .infinity, minHeight: 56)"))
        XCTAssertTrue(composer.contains("smallThings.form.imagePicker"))
        XCTAssertTrue(composer.contains("smallThings.form.save"))
        XCTAssertTrue(composer.contains("PhotosPicker"))
        XCTAssertTrue(composer.contains("Theme.bg.ignoresSafeArea()"))
    }

    func testCommentsRepliesAndImagePreviewHaveBehavioralEntrypoints() throws {
        let entry = try source("XiaomaoApp/SmallThings/SmallThingEntryCard.swift")
        let image = try source("XiaomaoApp/SmallThings/SmallThingsImagePreview.swift")

        XCTAssertTrue(entry.contains("commentsOpen.toggle()"))
        XCTAssertTrue(entry.contains("store.addCommentPersisted"))
        XCTAssertTrue(entry.contains("store.addReplyPersisted"))
        XCTAssertTrue(entry.contains("reply.author.displayName) 回复 "))
        XCTAssertTrue(entry.contains("smallThings.entry.comments.toggle"))
        XCTAssertTrue(entry.contains("smallThings.comment.send"))
        XCTAssertTrue(entry.contains("fullScreenCover"))
        XCTAssertTrue(image.contains("LinearGradient"), "Mock 初始图必须由程序生成")
    }

    func testBindingProvidesCopyShareValidationAndOfflineOutcomes() throws {
        let binding = try source("XiaomaoApp/SmallThings/SmallThingsBindingView.swift")
        let store = try source("XiaomaoApp/SmallThings/SmallThingsStore.swift")

        XCTAssertTrue(binding.contains("UIPasteboard.general.string"))
        XCTAssertTrue(binding.contains("ShareLink"))
        XCTAssertTrue(binding.contains("prefix(6)"))
        XCTAssertTrue(binding.contains("smallThings.binding.codeInput"))
        XCTAssertTrue(binding.contains("smallThings.binding.submit"))
        XCTAssertTrue(binding.contains("smallThings.binding.unbind"))
        XCTAssertTrue(binding.contains("store.createBindingCodePersisted"))
        XCTAssertTrue(binding.contains("store.bindPersisted"))
        XCTAssertTrue(binding.contains("store.unbindPersisted"))
        XCTAssertTrue(binding.contains("store.isProduction"))
        XCTAssertTrue(store.contains("successfulPartnerCode"))
        XCTAssertTrue(store.contains("occupiedPartnerCode"))
        XCTAssertFalse(binding.contains("Backend Gateway"))
    }

    func testApprovalUsesFilteredQueueAndNonAlertUndoWindow() throws {
        let approval = try source("XiaomaoApp/SmallThings/SmallThingsApprovalView.swift")
        let store = try source("XiaomaoApp/SmallThings/SmallThingsStore.swift")

        XCTAssertTrue(store.contains("$0.requester == .partner"))
        XCTAssertTrue(store.contains("$0.expenseStatus == .pending"))
        XCTAssertTrue(approval.contains("Task.sleep(for: .milliseconds(1_800))"))
        XCTAssertTrue(approval.contains("smallThings.approval.approve"))
        XCTAssertTrue(approval.contains("smallThings.approval.reject"))
        XCTAssertTrue(approval.contains("smallThings.approval.undo"))
        XCTAssertTrue(approval.contains("store.reviewPersisted"))
        XCTAssertTrue(approval.contains("store.undoLastReviewPersisted()"))
        XCTAssertFalse(approval.contains("Alert("))
        XCTAssertFalse(approval.contains("alert("))
    }

    func testCoreAccessibilityIdentifiersRemainStable() throws {
        let files = try [
            "XiaomaoApp/SmallThings/SmallThingsRootView.swift",
            "XiaomaoApp/SmallThings/SmallThingsLedgerCard.swift",
            "XiaomaoApp/SmallThings/SmallThingComposerView.swift",
            "XiaomaoApp/SmallThings/SmallThingsBindingView.swift",
            "XiaomaoApp/SmallThings/SmallThingsApprovalView.swift"
        ].map(source).joined(separator: "\n")

        for identifier in [
            "smallThings.root",
            "smallThings.ledger",
            "smallThings.ledger.addExpense",
            "smallThings.ledger.pendingApproval",
            "smallThings.form.type.note",
            "smallThings.form.type.expense",
            "smallThings.form.save",
            "smallThings.binding",
            "smallThings.approval.approve",
            "smallThings.approval.reject",
            "smallThings.approval.undo"
        ] {
            XCTAssertTrue(files.contains(identifier), "缺少无障碍入口：\(identifier)")
        }
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
