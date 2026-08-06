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
    @Published private(set) var generatedBindingCode: String?
    @Published private(set) var isLoading = false
    @Published private(set) var operationError: String?
    @Published var validationMessage: String?

    private let service: (any SmallThingsServicing)?
    private var remoteReviewReceipt: SmallThingsReviewReceipt?

    init(
        entries: [SmallThingEntry]? = nil,
        bindingState: SmallThingBindingState = .unbound,
        service: (any SmallThingsServicing)? = nil
    ) {
        self.service = service
        self.entries = entries ?? (service == nil ? Self.mockEntries() : [])
        self.bindingState = bindingState
    }

    var isProduction: Bool { service != nil }

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
                    && $0.reviewer == .me
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
        operationError = nil
    }

    func resetBindingFeedback() {
        guard bindingState == .unbound else { return }
        bindingFeedback = .idle
        validationMessage = nil
    }

    func refreshFromBackend() async {
        guard let service, !isLoading else { return }
        isLoading = true
        operationError = nil
        defer { isLoading = false }
        do {
            let state = try await service.loadState()
            bindingState = state.bindingState
            entries = state.entries
            await hydrateRemoteImages(using: service)
        } catch {
            operationError = Self.userFacingMessage(for: error)
        }
    }

    @discardableResult
    func addNotePersisted(title: String, body: String, imageData: Data?) async -> Bool {
        guard let service else { return addNote(title: title, body: body, imageData: imageData) }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty || !cleanBody.isEmpty else {
            validationMessage = "标题或正文至少填写一项"
            return false
        }
        return await performRemoteWrite {
            try await service.createNote(
                title: cleanTitle,
                body: cleanBody,
                imageData: imageData,
                requestID: UUID().uuidString.lowercased()
            )
        }
    }

    @discardableResult
    func addExpensePersisted(
        purpose: String,
        amountText: String,
        note: String
    ) async -> Bool {
        guard let service else {
            return addExpense(purpose: purpose, amountText: amountText, note: note)
        }
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
        return await performRemoteWrite {
            try await service.createExpense(
                purpose: cleanPurpose,
                amountCents: Int((amount * 100).rounded()),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                requestID: UUID().uuidString.lowercased()
            )
        }
    }

    func toggleReactionPersisted(entryID: UUID) async {
        guard let service else {
            toggleReaction(entryID: entryID)
            return
        }
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              let serverID = entries[index].serverID else { return }
        let previous = entries[index].reacted
        entries[index].reacted.toggle()
        operationError = nil
        do {
            let result = try await service.toggleReaction(
                entryID: serverID,
                requestID: UUID().uuidString.lowercased()
            )
            if let currentIndex = entries.firstIndex(where: { $0.id == entryID }) {
                entries[currentIndex].reacted = result.reacted
            }
        } catch {
            if let currentIndex = entries.firstIndex(where: { $0.id == entryID }) {
                entries[currentIndex].reacted = previous
            }
            operationError = Self.userFacingMessage(for: error)
        }
    }

    @discardableResult
    func addCommentPersisted(entryID: UUID, text: String) async -> Bool {
        guard let service else { return addComment(entryID: entryID, text: text) }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let serverID = entries[entryIndex].serverID else { return false }
        let temporaryID = UUID()
        entries[entryIndex].comments.append(
            SmallThingComment(id: temporaryID, author: .me, text: clean)
        )
        operationError = nil
        do {
            let result = try await service.createComment(
                entryID: serverID,
                text: clean,
                requestID: UUID().uuidString.lowercased()
            )
            guard let currentEntryIndex = entries.firstIndex(where: { $0.id == entryID }),
                  let temporaryIndex = entries[currentEntryIndex].comments.firstIndex(where: { $0.id == temporaryID }) else {
                return true
            }
            entries[currentEntryIndex].comments[temporaryIndex] = result.comment
            return true
        } catch {
            if let currentEntryIndex = entries.firstIndex(where: { $0.id == entryID }) {
                entries[currentEntryIndex].comments.removeAll { $0.id == temporaryID }
            }
            operationError = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    func addReplyPersisted(
        entryID: UUID,
        commentID: UUID,
        replyToID: UUID,
        replyTo: SmallThingRequester,
        text: String
    ) async -> Bool {
        guard let service else {
            return addReply(
                entryID: entryID,
                commentID: commentID,
                replyTo: replyTo,
                text: text
            )
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let entry = entry(id: entryID),
              let entryServerID = entry.serverID,
              let comment = entry.comments.first(where: { $0.id == commentID }),
              let commentServerID = comment.serverID else { return false }
        let targetServerID: String?
        if replyToID == commentID {
            targetServerID = commentServerID
        } else {
            targetServerID = comment.replies.first(where: { $0.id == replyToID })?.serverID
        }
        guard let targetServerID else { return false }
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let commentIndex = entries[entryIndex].comments.firstIndex(where: { $0.id == commentID }) else {
            return false
        }
        let temporaryID = UUID()
        entries[entryIndex].comments[commentIndex].replies.append(
            SmallThingReply(
                id: temporaryID,
                author: .me,
                text: clean,
                replyToAuthor: replyTo
            )
        )
        operationError = nil
        do {
            let result = try await service.createReply(
                entryID: entryServerID,
                commentID: commentServerID,
                replyToID: targetServerID,
                text: clean,
                requestID: UUID().uuidString.lowercased()
            )
            guard let currentEntryIndex = entries.firstIndex(where: { $0.id == entryID }),
                  let currentCommentIndex = entries[currentEntryIndex].comments.firstIndex(where: { $0.id == commentID }),
                  let temporaryIndex = entries[currentEntryIndex].comments[currentCommentIndex].replies.firstIndex(where: { $0.id == temporaryID }) else {
                return true
            }
            entries[currentEntryIndex].comments[currentCommentIndex].replies[temporaryIndex] = result.reply
            return true
        } catch {
            if let currentEntryIndex = entries.firstIndex(where: { $0.id == entryID }),
               let currentCommentIndex = entries[currentEntryIndex].comments.firstIndex(where: { $0.id == commentID }) {
                entries[currentEntryIndex].comments[currentCommentIndex].replies.removeAll { $0.id == temporaryID }
            }
            operationError = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    func reviewPersisted(
        entryID: UUID,
        status: SmallThingExpenseStatus,
        message: String
    ) async -> Bool {
        guard let service else {
            return review(entryID: entryID, status: status, message: message)
        }
        guard status != .pending,
              let entry = entry(id: entryID),
              entry.requester == .partner,
              entry.reviewer == .me,
              entry.expenseStatus == .pending,
              let serverID = entry.serverID else { return false }
        isLoading = true
        operationError = nil
        defer { isLoading = false }
        do {
            let requestID = UUID().uuidString.lowercased()
            remoteReviewReceipt = try await service.review(
                entryID: serverID,
                status: status,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                requestID: requestID
            )
            lastUndo = SmallThingApprovalUndo(
                entryID: entryID,
                previousStatus: .pending,
                previousMessage: entry.approvalMessage
            )
            let state = try await service.loadState()
            bindingState = state.bindingState
            entries = state.entries
            await hydrateRemoteImages(using: service)
            return true
        } catch {
            operationError = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    func undoLastReviewPersisted() async -> Bool {
        guard let service else { return undoLastReview() }
        guard let receipt = remoteReviewReceipt else { return false }
        let success = await performRemoteWrite {
            try await service.undo(
                receipt,
                requestID: UUID().uuidString.lowercased()
            )
        }
        if success {
            remoteReviewReceipt = nil
            lastUndo = nil
        }
        return success
    }

    @discardableResult
    func createBindingCodePersisted() async -> Bool {
        guard let service else {
            generatedBindingCode = Self.localBindingCode
            return true
        }
        isLoading = true
        operationError = nil
        defer { isLoading = false }
        do {
            generatedBindingCode = try await service.createBindingCode(
                requestID: UUID().uuidString.lowercased()
            )
            bindingFeedback = .idle
            return true
        } catch {
            operationError = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    func bindPersisted(code: String) async -> Bool {
        guard let service else { return bindDemo(code: code) }
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 6, clean.allSatisfy(\.isNumber) else {
            validationMessage = "请输入六位数字"
            return false
        }
        let success = await performRemoteWrite {
            try await service.acceptBindingCode(
                clean,
                requestID: UUID().uuidString.lowercased()
            )
        }
        if success {
            bindingFeedback = .success
            generatedBindingCode = nil
        }
        return success
    }

    func unbindPersisted() async {
        guard let service else {
            unbindDemo()
            return
        }
        let success = await performRemoteWrite {
            try await service.unbind(requestID: UUID().uuidString.lowercased())
        }
        if success {
            generatedBindingCode = nil
            bindingFeedback = .idle
        }
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
                reviewer: .partner,
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
              entries[index].reviewer == .me,
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
        remoteReviewReceipt = nil
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

    private func performRemoteWrite(
        _ operation: () async throws -> Void
    ) async -> Bool {
        guard let service else { return false }
        isLoading = true
        operationError = nil
        validationMessage = nil
        defer { isLoading = false }
        do {
            try await operation()
            let state = try await service.loadState()
            bindingState = state.bindingState
            entries = state.entries
            await hydrateRemoteImages(using: service)
            return true
        } catch {
            operationError = Self.userFacingMessage(for: error)
            validationMessage = operationError
            return false
        }
    }

    private func hydrateRemoteImages(using service: any SmallThingsServicing) async {
        for index in entries.indices {
            guard let mediaID = entries[index].imageMediaID else { continue }
            if let data = try? await service.loadMedia(mediaID: mediaID),
               entries.indices.contains(index),
               entries[index].imageMediaID == mediaID {
                entries[index].imageData = data
            }
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        guard let appError = error as? AppError else {
            return "操作失败，请稍后重试。"
        }
        switch appError {
        case .unauthorized:
            return "授权已失效，请重新配置连接。"
        case .networkUnavailable:
            return "网络不可用，请检查连接后重试。"
        case .configuration:
            return "小事服务配置不可用。"
        case let .server(code):
            switch code {
            case "not_bound": return "请先完成关系绑定。"
            case "ledger_limit_exceeded": return "金额超过当前可用额度。"
            case "invalid_code", "expired_code", "code_already_used":
                return "绑定码无效或已过期。"
            case "already_bound": return "当前已经处于绑定状态。"
            case "media_too_large": return "图片过大，请选择较小的图片。"
            case "unsupported_media_type", "media_type_mismatch", "invalid_media_dimensions":
                return "图片格式不受支持。"
            default:
                if code.hasPrefix("http_") {
                    return "服务器返回异常状态（\(code.replacingOccurrences(of: "http_", with: "HTTP "))）。"
                }
                return "服务器拒绝了本次操作。"
            }
        case .protocolError:
            return "服务端数据格式异常，请稍后重试。"
        case .audio:
            return "操作失败，请稍后重试。"
        }
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
                reviewer: .me,
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
