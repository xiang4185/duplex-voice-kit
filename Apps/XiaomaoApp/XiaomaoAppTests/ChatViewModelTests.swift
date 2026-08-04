import Foundation
import XCTest
@testable import XiaomaoApp

private func serverMessage(
    id: String,
    role: ChatMessage.Role,
    content: String
) -> ChatMessage {
    ChatMessage(
        id: id,
        role: role,
        content: content,
        createdAt: Date(timeIntervalSince1970: 1_775_000_000)
    )
}

private func loadedHistory() -> Result<ChatHistoryResult, Error> {
    .success(ChatHistoryResult(
        sessionID: "server-session",
        messages: [serverMessage(id: "history-1", role: .assistant, content: "合成历史")]
    ))
}

private func successfulSend() -> ChatSendResult {
    ChatSendResult(
        sessionID: "server-session",
        userMessage: serverMessage(id: "send-user", role: .user, content: "合成发送"),
        assistantMessage: serverMessage(id: "send-assistant", role: .assistant, content: "合成回复"),
        route: "direct",
        degraded: false,
        persisted: true
    )
}

@MainActor
final class ChatViewModelTests: XCTestCase {
    func testHistoryLoadStoresServerSessionMessagesIDsAndDates() async {
        let messages = [serverMessage(id: "opaque-history-1", role: .user, content: "合成历史")]
        let service = ChatServiceSpy(historyResults: [
            .success(ChatHistoryResult(sessionID: "server-session", messages: messages))
        ])
        let viewModel = ChatViewModel(service: service)

        await viewModel.loadHistory()

        XCTAssertTrue(viewModel.hasLoadedHistory)
        XCTAssertEqual(viewModel.sessionID, "server-session")
        XCTAssertEqual(viewModel.messages, messages)
        XCTAssertEqual(viewModel.messages.first?.id, "opaque-history-1")
        XCTAssertEqual(viewModel.messages.first?.createdAt, messages.first?.createdAt)
    }

    func testHistoryFailureDoesNotCreateSessionAndCanRetry() async {
        let service = ChatServiceSpy(historyResults: [
            .failure(SyntheticError.failed),
            .success(ChatHistoryResult(sessionID: "server-session", messages: []))
        ])
        let viewModel = ChatViewModel(service: service)

        await viewModel.loadHistory()
        XCTAssertNil(viewModel.sessionID)
        XCTAssertFalse(viewModel.hasLoadedHistory)
        XCTAssertFalse(viewModel.errorMessage.isEmpty)

        await viewModel.loadHistory()
        XCTAssertEqual(viewModel.sessionID, "server-session")
        XCTAssertTrue(viewModel.hasLoadedHistory)
        XCTAssertEqual(service.loadHistoryCallCount, 2)
    }

    func testBlankAndOverLimitMessagesDoNotSend() async {
        let service = ChatServiceSpy(historyResults: [loadedHistory()])
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()

        viewModel.draft = "   \n"
        await viewModel.send()
        viewModel.draft = String(repeating: "字", count: 201)
        await viewModel.send()

        XCTAssertEqual(service.sendCallCount, 0)
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertTrue(viewModel.errorMessage.contains("200"))
    }

    func testTwoHundredCharactersCanSend() async {
        let service = ChatServiceSpy(
            historyResults: [.success(ChatHistoryResult(sessionID: "server-session", messages: []))]
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()
        viewModel.draft = String(repeating: "字", count: 200)

        await viewModel.send()

        XCTAssertEqual(service.sendCallCount, 1)
        XCTAssertEqual(viewModel.messages.count, 2)
    }

    func testSendWithoutLoadedSessionDoesNotCallService() async {
        let service = ChatServiceSpy()
        let viewModel = ChatViewModel(service: service)
        viewModel.draft = "合成消息"

        await viewModel.send()

        XCTAssertEqual(service.sendCallCount, 0)
        XCTAssertNil(viewModel.sessionID)
        XCTAssertEqual(viewModel.draft, "合成消息")
    }

    func testSendUsesCurrentSessionAndGeneratedRequestIDAndOnlyAddsServerMessages() async {
        let user = serverMessage(id: "opaque-user", role: .user, content: "合成发送")
        let assistant = serverMessage(id: "opaque-assistant", role: .assistant, content: "合成回复")
        let service = ChatServiceSpy(
            historyResults: [loadedHistory()],
            sendResult: .success(ChatSendResult(
                sessionID: "server-session",
                userMessage: user,
                assistantMessage: assistant,
                route: "direct",
                degraded: false,
                persisted: true
            ))
        )
        let viewModel = ChatViewModel(
            service: service,
            requestIDGenerator: { "opaque-request-id" }
        )
        await viewModel.loadHistory()
        let originalMessages = viewModel.messages
        viewModel.draft = "  合成发送  "

        await viewModel.send()

        XCTAssertEqual(service.sendRequests, [
            .init(message: "合成发送", sessionID: "server-session", requestID: "opaque-request-id")
        ])
        XCTAssertEqual(viewModel.messages, originalMessages + [user, assistant])
        XCTAssertEqual(viewModel.messages.suffix(2).map(\.id), ["opaque-user", "opaque-assistant"])
        XCTAssertEqual(viewModel.draft, "")
    }

    func testSendDoesNotOptimisticallyInsertAndConsecutiveTapSendsOnce() async {
        let started = expectation(description: "send started")
        let service = ChatServiceSpy(
            historyResults: [.success(ChatHistoryResult(sessionID: "server-session", messages: []))],
            sendResult: .success(successfulSend()),
            sendDelayNanoseconds: 80_000_000,
            onSend: { started.fulfill() }
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()
        viewModel.draft = "合成发送"

        let first = Task { await viewModel.send() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(viewModel.messages.isEmpty)
        let second = Task { await viewModel.send() }
        await second.value
        await first.value

        XCTAssertEqual(service.sendCallCount, 1)
        XCTAssertEqual(viewModel.messages.count, 2)
    }

    func testSendFailureKeepsDraftAndHistory() async {
        let history = [serverMessage(id: "history", role: .assistant, content: "合成历史")]
        let service = ChatServiceSpy(
            historyResults: [.success(ChatHistoryResult(sessionID: "server-session", messages: history))],
            sendResult: .failure(SyntheticError.failed)
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()
        viewModel.draft = "合成草稿"

        await viewModel.send()

        XCTAssertEqual(viewModel.draft, "合成草稿")
        XCTAssertEqual(viewModel.messages, history)
        XCTAssertFalse(viewModel.errorMessage.isEmpty)
    }

    func testMismatchedSendResponseInvalidatesSessionButKeepsDraftAndHistory() async {
        let history = [serverMessage(id: "history", role: .assistant, content: "合成历史")]
        let mismatched = ChatSendResult(
            sessionID: "other-server-session",
            userMessage: serverMessage(id: "u", role: .user, content: "合成发送"),
            assistantMessage: serverMessage(id: "a", role: .assistant, content: "合成回复"),
            route: "direct",
            degraded: false,
            persisted: true
        )
        let service = ChatServiceSpy(
            historyResults: [.success(ChatHistoryResult(sessionID: "server-session", messages: history))],
            sendResult: .success(mismatched)
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()
        viewModel.draft = "合成草稿"

        await viewModel.send()

        XCTAssertEqual(viewModel.messages, history)
        XCTAssertEqual(viewModel.draft, "合成草稿")
        XCTAssertNil(viewModel.sessionID)
        XCTAssertFalse(viewModel.hasLoadedHistory)
        XCTAssertTrue(viewModel.canRetryHistory)
        XCTAssertFalse(viewModel.canClear)
        XCTAssertTrue(viewModel.errorMessage.contains("会话"))
    }

    func testBackendSessionMismatchInvalidatesSessionAndBlocksFurtherSend() async {
        let history = [serverMessage(id: "history", role: .assistant, content: "合成历史")]
        let service = ChatServiceSpy(
            historyResults: [.success(ChatHistoryResult(sessionID: "server-session", messages: history))],
            sendResult: .failure(AppError.server("session_mismatch"))
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()
        viewModel.draft = "合成草稿"

        await viewModel.send()
        await viewModel.send()

        XCTAssertEqual(service.sendCallCount, 1)
        XCTAssertEqual(viewModel.messages, history)
        XCTAssertEqual(viewModel.draft, "合成草稿")
        XCTAssertNil(viewModel.sessionID)
        XCTAssertFalse(viewModel.hasLoadedHistory)
        XCTAssertTrue(viewModel.canRetryHistory)
        XCTAssertFalse(viewModel.canSend)
    }

    func testSessionRecoveryReloadsNewServerSessionAndRestoresSending() async {
        let oldHistory = [serverMessage(id: "old", role: .assistant, content: "旧合成历史")]
        let newHistory = [serverMessage(id: "new", role: .assistant, content: "新合成历史")]
        let service = ChatServiceSpy(
            historyResults: [
                .success(ChatHistoryResult(sessionID: "old-session", messages: oldHistory)),
                .success(ChatHistoryResult(sessionID: "new-session", messages: newHistory))
            ],
            sendResult: .failure(AppError.server("invalid_session_id"))
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()
        viewModel.draft = "保留的合成草稿"

        await viewModel.send()
        XCTAssertTrue(viewModel.canRetryHistory)

        await viewModel.loadHistory()

        XCTAssertEqual(viewModel.sessionID, "new-session")
        XCTAssertEqual(viewModel.messages, newHistory)
        XCTAssertEqual(viewModel.draft, "保留的合成草稿")
        XCTAssertTrue(viewModel.hasLoadedHistory)
        XCTAssertFalse(viewModel.canRetryHistory)
        XCTAssertTrue(viewModel.canSend)
        XCTAssertEqual(service.loadHistoryCallCount, 2)
    }

    func testOrdinary503KeepsValidSessionAndHistory() async {
        let history = [serverMessage(id: "history", role: .assistant, content: "合成历史")]
        let service = ChatServiceSpy(
            historyResults: [.success(ChatHistoryResult(sessionID: "server-session", messages: history))],
            sendResult: .failure(AppError.server("http_503"))
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()
        viewModel.draft = "合成草稿"

        await viewModel.send()

        XCTAssertEqual(viewModel.sessionID, "server-session")
        XCTAssertTrue(viewModel.hasLoadedHistory)
        XCTAssertEqual(viewModel.messages, history)
        XCTAssertEqual(viewModel.draft, "合成草稿")
        XCTAssertFalse(viewModel.canRetryHistory)
        XCTAssertTrue(viewModel.canSend)
    }

    func testDegradedResponseUpdatesState() async {
        let degraded = ChatSendResult(
            sessionID: "server-session",
            userMessage: serverMessage(id: "u", role: .user, content: "合成发送"),
            assistantMessage: serverMessage(id: "a", role: .assistant, content: "安全降级回复"),
            route: "fallback",
            degraded: true,
            persisted: true
        )
        let service = ChatServiceSpy(
            historyResults: [.success(ChatHistoryResult(sessionID: "server-session", messages: []))],
            sendResult: .success(degraded)
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()
        viewModel.draft = "合成发送"

        await viewModel.send()

        XCTAssertTrue(viewModel.lastReplyWasDegraded)
        XCTAssertEqual(viewModel.messages.last?.id, "a")
    }

    func testClearUsesCurrentSessionKeepsSessionAndClearsMessages() async {
        let service = ChatServiceSpy(
            historyResults: [loadedHistory()],
            clearResult: .success(ChatClearResult(sessionID: "server-session", cleared: true))
        )
        let viewModel = ChatViewModel(
            service: service,
            requestIDGenerator: { "opaque-clear-request" }
        )
        await viewModel.loadHistory()

        await viewModel.clear()

        XCTAssertEqual(service.clearRequests, [
            .init(sessionID: "server-session", requestID: "opaque-clear-request")
        ])
        XCTAssertEqual(viewModel.sessionID, "server-session")
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testClearFailureKeepsMessages() async {
        let historyResult = loadedHistory()
        let expectedMessages = try! historyResult.get().messages
        let service = ChatServiceSpy(
            historyResults: [historyResult],
            clearResult: .failure(SyntheticError.failed)
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()

        await viewModel.clear()

        XCTAssertEqual(viewModel.messages, expectedMessages)
        XCTAssertEqual(viewModel.sessionID, "server-session")
        XCTAssertFalse(viewModel.errorMessage.isEmpty)
    }

    func testMismatchedClearResponseInvalidatesSessionButKeepsMessages() async {
        let expectedMessages = try! loadedHistory().get().messages
        let service = ChatServiceSpy(
            historyResults: [loadedHistory()],
            clearResult: .success(ChatClearResult(
                sessionID: "other-server-session",
                cleared: true
            ))
        )
        let viewModel = ChatViewModel(service: service)
        await viewModel.loadHistory()
        viewModel.draft = "保留的合成草稿"

        await viewModel.clear()

        XCTAssertNil(viewModel.sessionID)
        XCTAssertFalse(viewModel.hasLoadedHistory)
        XCTAssertTrue(viewModel.canRetryHistory)
        XCTAssertFalse(viewModel.canClear)
        XCTAssertEqual(viewModel.messages, expectedMessages)
        XCTAssertEqual(viewModel.draft, "保留的合成草稿")
        XCTAssertTrue(viewModel.errorMessage.contains("会话"))
    }

    func testLoadingSendingAndClearingCannotOverlap() async {
        let historyStarted = expectation(description: "history started")
        let service = ChatServiceSpy(
            historyResults: [loadedHistory()],
            loadDelayNanoseconds: 80_000_000,
            onLoadHistory: { historyStarted.fulfill() }
        )
        let viewModel = ChatViewModel(service: service)
        viewModel.draft = "合成发送"

        let loading = Task { await viewModel.loadHistory() }
        await fulfillment(of: [historyStarted], timeout: 1)
        await viewModel.send()
        await viewModel.clear()
        await loading.value

        XCTAssertEqual(service.sendCallCount, 0)
        XCTAssertEqual(service.clearCallCount, 0)
        XCTAssertTrue(viewModel.hasLoadedHistory)
    }

    func testSendingBlocksClearAndClearingBlocksSend() async {
        let sendStarted = expectation(description: "send started")
        let sendingService = ChatServiceSpy(
            historyResults: [loadedHistory()],
            sendDelayNanoseconds: 80_000_000,
            onSend: { sendStarted.fulfill() }
        )
        let sendingViewModel = ChatViewModel(service: sendingService)
        await sendingViewModel.loadHistory()
        sendingViewModel.draft = "合成发送"

        let sending = Task { await sendingViewModel.send() }
        await fulfillment(of: [sendStarted], timeout: 1)
        await sendingViewModel.clear()
        await sending.value

        XCTAssertEqual(sendingService.sendCallCount, 1)
        XCTAssertEqual(sendingService.clearCallCount, 0)

        let clearStarted = expectation(description: "clear started")
        let clearingService = ChatServiceSpy(
            historyResults: [loadedHistory()],
            clearDelayNanoseconds: 80_000_000,
            onClear: { clearStarted.fulfill() }
        )
        let clearingViewModel = ChatViewModel(service: clearingService)
        await clearingViewModel.loadHistory()
        clearingViewModel.draft = "合成发送"

        let clearing = Task { await clearingViewModel.clear() }
        await fulfillment(of: [clearStarted], timeout: 1)
        await clearingViewModel.send()
        await clearing.value

        XCTAssertEqual(clearingService.clearCallCount, 1)
        XCTAssertEqual(clearingService.sendCallCount, 0)
    }

}

private enum SyntheticError: Error {
    case failed
}

private final class ChatServiceSpy: ChatServicing, @unchecked Sendable {
    struct SendRequest: Equatable {
        let message: String
        let sessionID: String
        let requestID: String
    }

    struct ClearRequest: Equatable {
        let sessionID: String
        let requestID: String
    }

    private let lock = NSLock()
    private var historyResults: [Result<ChatHistoryResult, Error>]
    private let sendResult: Result<ChatSendResult, Error>
    private let clearResult: Result<ChatClearResult, Error>
    private let loadDelayNanoseconds: UInt64
    private let sendDelayNanoseconds: UInt64
    private let clearDelayNanoseconds: UInt64
    private let onLoadHistory: (() -> Void)?
    private let onSend: (() -> Void)?
    private let onClear: (() -> Void)?
    private var storedLoadHistoryCallCount = 0
    private var storedSendRequests: [SendRequest] = []
    private var storedClearRequests: [ClearRequest] = []

    init(
        historyResults: [Result<ChatHistoryResult, Error>] = [],
        sendResult: Result<ChatSendResult, Error> = .success(successfulSend()),
        clearResult: Result<ChatClearResult, Error> = .success(
            ChatClearResult(sessionID: "server-session", cleared: true)
        ),
        loadDelayNanoseconds: UInt64 = 0,
        sendDelayNanoseconds: UInt64 = 0,
        clearDelayNanoseconds: UInt64 = 0,
        onLoadHistory: (() -> Void)? = nil,
        onSend: (() -> Void)? = nil,
        onClear: (() -> Void)? = nil
    ) {
        self.historyResults = historyResults
        self.sendResult = sendResult
        self.clearResult = clearResult
        self.loadDelayNanoseconds = loadDelayNanoseconds
        self.sendDelayNanoseconds = sendDelayNanoseconds
        self.clearDelayNanoseconds = clearDelayNanoseconds
        self.onLoadHistory = onLoadHistory
        self.onSend = onSend
        self.onClear = onClear
    }

    var loadHistoryCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedLoadHistoryCallCount
    }

    var sendCallCount: Int { sendRequests.count }
    var clearCallCount: Int { clearRequests.count }

    var sendRequests: [SendRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedSendRequests
    }

    var clearRequests: [ClearRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedClearRequests
    }

    func loadHistory() async throws -> ChatHistoryResult {
        let result = dequeueHistoryResult()
        onLoadHistory?()
        if loadDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: loadDelayNanoseconds)
        }
        return try result.get()
    }

    func send(message: String, sessionID: String, requestID: String) async throws -> ChatSendResult {
        recordSendRequest(.init(
            message: message,
            sessionID: sessionID,
            requestID: requestID
        ))
        onSend?()
        if sendDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: sendDelayNanoseconds)
        }
        return try sendResult.get()
    }

    func clear(sessionID: String, requestID: String) async throws -> ChatClearResult {
        recordClearRequest(.init(sessionID: sessionID, requestID: requestID))
        onClear?()
        if clearDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: clearDelayNanoseconds)
        }
        return try clearResult.get()
    }

    private func dequeueHistoryResult() -> Result<ChatHistoryResult, Error> {
        lock.lock()
        defer { lock.unlock() }
        storedLoadHistoryCallCount += 1
        return historyResults.isEmpty
            ? .failure(SyntheticError.failed)
            : historyResults.removeFirst()
    }

    private func recordSendRequest(_ request: SendRequest) {
        lock.lock()
        storedSendRequests.append(request)
        lock.unlock()
    }

    private func recordClearRequest(_ request: ClearRequest) {
        lock.lock()
        storedClearRequests.append(request)
        lock.unlock()
    }
}
