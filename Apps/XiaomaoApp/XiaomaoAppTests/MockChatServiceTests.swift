import Foundation
import XCTest
@testable import XiaomaoApp

final class MockChatServiceTests: XCTestCase {
    func testDefaultHistoryLoadsWithStableSession() async throws {
        let service = MockChatService(delays: .zero)

        let first = try await service.loadHistory()
        let second = try await service.loadHistory()

        XCTAssertFalse(first.sessionID.isEmpty)
        XCTAssertEqual(first.sessionID, second.sessionID)
        XCTAssertEqual(first.messages, second.messages)
        XCTAssertGreaterThanOrEqual(first.messages.count, 3)
        XCTAssertTrue(first.messages.contains { $0.role == .user })
        XCTAssertTrue(first.messages.contains { $0.role == .assistant })
    }

    func testSendReturnsAuthoritativeMessagesAndHistoryReadsThemBack() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let service = MockChatService(
            delays: .zero,
            initialMessages: [],
            now: { timestamp }
        )
        let history = try await service.loadHistory()

        let sent = try await service.send(
            message: "合成发送",
            sessionID: history.sessionID,
            requestID: "send-1"
        )
        let reloaded = try await service.loadHistory()

        XCTAssertEqual(sent.sessionID, history.sessionID)
        XCTAssertEqual(sent.userMessage.role, .user)
        XCTAssertEqual(sent.userMessage.content, "合成发送")
        XCTAssertEqual(sent.userMessage.createdAt, timestamp)
        XCTAssertEqual(sent.assistantMessage.role, .assistant)
        XCTAssertFalse(sent.assistantMessage.content.isEmpty)
        XCTAssertEqual(sent.route, "direct")
        XCTAssertFalse(sent.degraded)
        XCTAssertTrue(sent.persisted)
        XCTAssertEqual(reloaded.messages, [sent.userMessage, sent.assistantMessage])
    }

    func testClearEmptiesMessagesAndKeepsSession() async throws {
        let service = MockChatService(delays: .zero)
        let history = try await service.loadHistory()

        let cleared = try await service.clear(
            sessionID: history.sessionID,
            requestID: "clear-1"
        )
        let reloaded = try await service.loadHistory()

        XCTAssertTrue(cleared.cleared)
        XCTAssertEqual(cleared.sessionID, history.sessionID)
        XCTAssertEqual(reloaded.sessionID, history.sessionID)
        XCTAssertTrue(reloaded.messages.isEmpty)
    }

    func testSendRetryIsIdempotentAndDoesNotAppendTwice() async throws {
        let service = MockChatService(delays: .zero, initialMessages: [])
        let history = try await service.loadHistory()

        let first = try await service.send(
            message: "同一请求",
            sessionID: history.sessionID,
            requestID: "same-send"
        )
        let second = try await service.send(
            message: "同一请求",
            sessionID: history.sessionID,
            requestID: "same-send"
        )
        let reloaded = try await service.loadHistory()

        XCTAssertEqual(first, second)
        XCTAssertEqual(reloaded.messages, [first.userMessage, first.assistantMessage])
    }

    func testSameSendRequestWithDifferentContentConflicts() async throws {
        let service = MockChatService(delays: .zero, initialMessages: [])
        let history = try await service.loadHistory()
        _ = try await service.send(
            message: "第一次",
            sessionID: history.sessionID,
            requestID: "conflict-send"
        )

        await assertServerError("idempotency_conflict") {
            _ = try await service.send(
                message: "不同内容",
                sessionID: history.sessionID,
                requestID: "conflict-send"
            )
        }

        await assertServerError("idempotency_conflict") {
            _ = try await service.send(
                message: "第一次",
                sessionID: "different-session",
                requestID: "conflict-send"
            )
        }
    }

    func testClearRetryIsIdempotentAndOperationSpaceIsSeparate() async throws {
        let service = MockChatService(delays: .zero)
        let history = try await service.loadHistory()

        let first = try await service.clear(
            sessionID: history.sessionID,
            requestID: "shared-request"
        )
        let second = try await service.clear(
            sessionID: history.sessionID,
            requestID: "shared-request"
        )
        let sent = try await service.send(
            message: "不同操作可复用请求 ID",
            sessionID: history.sessionID,
            requestID: "shared-request"
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(sent.userMessage.content, "不同操作可复用请求 ID")
    }

    @MainActor
    func testPublicDefaultServiceIsOfflineMock() {
        XCTAssertTrue(MainTabView.publicDefaultChatService() is MockChatService)
    }

    @MainActor
    func testPublicDefaultLoadsWithoutEndpointTokenOrDeviceConfiguration() async {
        let viewModel = ChatViewModel(
            service: MainTabView.publicDefaultChatService()
        )

        await viewModel.loadHistory()

        XCTAssertTrue(viewModel.isConfigurationAvailable)
        XCTAssertTrue(viewModel.hasLoadedHistory)
        XCTAssertNotNil(viewModel.sessionID)
        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.errorMessage.isEmpty)
    }

    private func assertServerError(
        _ expectedCode: String,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected server error \(expectedCode)")
        } catch AppError.server(let code) {
            XCTAssertEqual(code, expectedCode)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
