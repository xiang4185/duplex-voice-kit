import Foundation
import XCTest
@testable import XiaomaoApp

final class SmallThingsUIContractTests: XCTestCase {
    func testRootUsesCompactNativeNavigationAndStartsWithLedger() throws {
        let root = try source("XiaomaoApp/SmallThings/SmallThingsRootView.swift")

        XCTAssertTrue(root.contains(".navigationTitle(\"小事本\")"))
        XCTAssertTrue(root.contains(".navigationBarTitleDisplayMode(.inline)"))
        XCTAssertFalse(root.contains("systemName: \"plus\""))
        XCTAssertFalse(root.contains("private var header"))
        XCTAssertFalse(root.contains("和图图的小日子"))
        XCTAssertFalse(root.contains("SHARED ARCHIVE"), "高频工具页不得再用无信息的大型编辑式 masthead")
        XCTAssertFalse(root.contains("v2Masthead"), "小事页首屏应直接进入账本内容")

        let ledger = try XCTUnwrap(root.range(of: "SmallThingsLedgerCard("))
        let flow = try XCTUnwrap(root.range(of: "flowHeader"))
        XCTAssertLessThan(ledger.lowerBound, flow.lowerBound, "账本卡必须早于时间流标题")
        XCTAssertTrue(root.contains(".padding(.top, 10)"))
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
        XCTAssertTrue(ledger.contains("smallThings.ledger.adjustLimit"), "账本卡必须提供轻量调额入口")
        XCTAssertTrue(ledger.contains("Label(\"调额\", systemImage: \"slider.horizontal.3\")"))
        XCTAssertTrue(ledger.contains("store.adjustLedgerLimit(to: value)"))
        XCTAssertTrue(ledger.contains("smallThings.binding"))
        XCTAssertFalse(ledger.contains("glassEffect"), "暖色账本卡不得使用玻璃")
        XCTAssertTrue(ledger.contains("progressRing"), "小事页必须恢复原有环形进度结构")
        XCTAssertTrue(ledger.contains("amountRow(\"已点头\""), "小事页必须恢复原有金额明细")
    }

    func testComposerUsesNativeTaskLayoutWithOneSaveAction() throws {
        let composer = try source("XiaomaoApp/SmallThings/SmallThingComposerView.swift")

        XCTAssertFalse(composer.contains("Form"))
        XCTAssertFalse(composer.contains("cancellationAction"))
        XCTAssertFalse(composer.contains("confirmationAction"))
        XCTAssertEqual(composer.components(separatedBy: "Text(\"记下来\")").count - 1, 1)
        XCTAssertTrue(composer.contains("smallThings.form.type.note"))
        XCTAssertTrue(composer.contains("smallThings.form.type.expense"))
        XCTAssertTrue(composer.contains(".pickerStyle(.segmented)"),
                      "记录类型应优先使用 iOS 原生 segmented control")
        XCTAssertFalse(composer.contains("typeSelectorButton("), "不得再维护第二套自绘分段按钮")
        XCTAssertTrue(composer.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(composer.contains(".buttonStyle(.bordered)"))
        XCTAssertTrue(composer.contains(".buttonBorderShape(.capsule)"))
        XCTAssertTrue(composer.contains(".toolbar(.hidden, for: .tabBar)"), "二级记录页必须隐藏主 Tab Bar")
        XCTAssertTrue(composer.contains(".safeAreaInset(edge: .bottom"), "保存操作必须独占底部安全区")
        XCTAssertTrue(composer.contains("showsDetails"), "补充说明应按需展开，避免表单化占位")
        XCTAssertTrue(composer.contains("font(.system(size: 46"), "账目页必须把金额提升为视觉主体")
        XCTAssertTrue(composer.contains("smallThings.form.imagePicker"))
        XCTAssertTrue(composer.contains("smallThings.form.save"))
        XCTAssertTrue(composer.contains("PhotosPicker"))
        XCTAssertTrue(composer.contains("Theme.bg.ignoresSafeArea()"))
    }

    func testEntryTimestampUsesStableNumericDateToMinute() throws {
        let entry = try source("XiaomaoApp/SmallThings/SmallThingEntryCard.swift")

        XCTAssertTrue(entry.contains("dateFormat = \"yyyy/MM/dd HH:mm\""))
        XCTAssertTrue(entry.contains("Locale(identifier: \"en_US_POSIX\")"))
        XCTAssertFalse(entry.contains(".dateTime.month().day().hour().minute()"))
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
        XCTAssertTrue(entry.contains("smallThings.entry.image.preview"))
        XCTAssertTrue(entry.contains(".contentShape("))
        XCTAssertTrue(image.contains(".clipped()"))
        XCTAssertTrue(image.contains(".contentShape(RoundedRectangle"))
        XCTAssertTrue(image.contains("LinearGradient"), "Mock 初始图必须由程序生成")
    }

    func testEntryDeleteUsesMenuAndDestructiveConfirmation() throws {
        let entry = try source("XiaomaoApp/SmallThings/SmallThingEntryCard.swift")
        let store = try source("XiaomaoApp/SmallThings/SmallThingsStore.swift")
        let service = try source("XiaomaoApp/SmallThings/SmallThingsService.swift")

        XCTAssertTrue(entry.contains("smallThings.entry.menu"))
        XCTAssertTrue(entry.contains("删除这件小事"))
        XCTAssertTrue(entry.contains("confirmationDialog("))
        XCTAssertTrue(entry.contains("role: .destructive"))
        XCTAssertTrue(entry.contains("store.deleteEntryPersisted(entryID: entry.id)"))
        XCTAssertTrue(store.contains("func deleteEntryPersisted(entryID: UUID) async -> Bool"))
        XCTAssertTrue(store.contains("entries.removeAll { $0.id == entryID }"))
        XCTAssertTrue(service.contains("/v1/small-things/entries/delete"))
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

        XCTAssertTrue(store.contains("$0.reviewer == .me"))
        XCTAssertTrue(store.contains("$0.expenseStatus == .pending"))
        XCTAssertTrue(approval.contains("entry.expenseStatusDisplayName"))
        XCTAssertTrue(approval.contains("Task.sleep(for: .milliseconds(1_800))"))
        XCTAssertTrue(approval.contains("smallThings.approval.approve"))
        XCTAssertTrue(approval.contains("smallThings.approval.reject"))
        XCTAssertTrue(approval.contains("smallThings.approval.undo"))
        XCTAssertTrue(approval.contains("store.reviewPersisted"))
        XCTAssertTrue(approval.contains("store.undoLastReviewPersisted()"))
        XCTAssertFalse(approval.contains("Alert("))
        XCTAssertFalse(approval.contains("alert("))
    }

    func testPendingCopyAndLightweightActionsUseServerRolesAndLocalUpdates() throws {
        let models = try source("XiaomaoApp/SmallThings/SmallThingsModels.swift")
        let store = try source("XiaomaoApp/SmallThings/SmallThingsStore.swift")
        let composer = try source("XiaomaoApp/SmallThings/SmallThingComposerView.swift")

        XCTAssertTrue(models.contains("reviewer == .me ? \"等我看\" : \"等对方看\""))
        XCTAssertTrue(composer.contains("等对方看"))
        XCTAssertTrue(store.contains("entries[index].reacted.toggle()"))
        XCTAssertTrue(store.contains("entries[currentEntryIndex].comments.removeAll"))

        let reactionStart = try XCTUnwrap(store.range(of: "func toggleReactionPersisted"))
        let commentStart = try XCTUnwrap(store.range(of: "func addCommentPersisted", range: reactionStart.upperBound..<store.endIndex))
        let reactionBlock = String(store[reactionStart.lowerBound..<commentStart.lowerBound])
        XCTAssertFalse(reactionBlock.contains("refreshFromBackend"))
        XCTAssertFalse(reactionBlock.contains("loadState()"))
        XCTAssertFalse(reactionBlock.contains("performRemoteWrite"))
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
            "smallThings.ledger.adjustLimit",
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
