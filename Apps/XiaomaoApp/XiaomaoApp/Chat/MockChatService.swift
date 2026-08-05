import Foundation

actor MockChatService: ChatServicing {
    struct Delays: Equatable, Sendable {
        let historyNanoseconds: UInt64
        let sendNanoseconds: UInt64
        let clearNanoseconds: UInt64

        static let demo = Delays(
            historyNanoseconds: 220_000_000,
            sendNanoseconds: 650_000_000,
            clearNanoseconds: 280_000_000
        )
        static let zero = Delays(
            historyNanoseconds: 0,
            sendNanoseconds: 0,
            clearNanoseconds: 0
        )
    }

    private enum StoredResult: Sendable {
        case send(fingerprint: String, result: ChatSendResult)
        case clear(fingerprint: String, result: ChatClearResult)
    }

    private let sessionID: String
    private let delays: Delays
    private let now: @Sendable () -> Date
    private var messages: [ChatMessage]
    private var storedResults: [String: StoredResult] = [:]

    init(
        delays: Delays = .demo,
        sessionID: String = "mock-chat-session-v1",
        initialMessages: [ChatMessage] = MockChatService.demoHistory,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.delays = delays
        self.sessionID = sessionID
        self.messages = initialMessages
        self.now = now
    }

    func loadHistory() async throws -> ChatHistoryResult {
        try await pause(delays.historyNanoseconds)
        return ChatHistoryResult(sessionID: sessionID, messages: messages)
    }

    func send(
        message: String,
        sessionID: String,
        requestID: String
    ) async throws -> ChatSendResult {
        try await pause(delays.sendNanoseconds)
        let key = "send:\(requestID)"
        let fingerprint = Self.fingerprint(sessionID, message)
        if let stored = storedResults[key] {
            guard case let .send(storedFingerprint, result) = stored,
                  storedFingerprint == fingerprint else {
                throw AppError.server("idempotency_conflict")
            }
            return result
        }
        guard sessionID == self.sessionID else {
            throw AppError.server("session_mismatch")
        }

        let timestamp = now()
        let userMessage = ChatMessage(
            id: "mock-user-\(UUID().uuidString.lowercased())",
            role: .user,
            content: message,
            createdAt: timestamp
        )
        let assistantMessage = ChatMessage(
            id: "mock-assistant-\(UUID().uuidString.lowercased())",
            role: .assistant,
            content: "这是离线演示回复。消息只保留在本次 App 运行期间。",
            createdAt: timestamp.addingTimeInterval(0.001)
        )
        let result = ChatSendResult(
            sessionID: self.sessionID,
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            route: "direct",
            degraded: false,
            persisted: true
        )
        messages.append(userMessage)
        messages.append(assistantMessage)
        storedResults[key] = .send(fingerprint: fingerprint, result: result)
        return result
    }

    func clear(sessionID: String, requestID: String) async throws -> ChatClearResult {
        try await pause(delays.clearNanoseconds)
        let key = "clear:\(requestID)"
        let fingerprint = Self.fingerprint(sessionID)
        if let stored = storedResults[key] {
            guard case let .clear(storedFingerprint, result) = stored,
                  storedFingerprint == fingerprint else {
                throw AppError.server("idempotency_conflict")
            }
            return result
        }
        guard sessionID == self.sessionID else {
            throw AppError.server("session_mismatch")
        }

        let result = ChatClearResult(sessionID: self.sessionID, cleared: true)
        messages = []
        storedResults[key] = .clear(fingerprint: fingerprint, result: result)
        return result
    }

    private func pause(_ nanoseconds: UInt64) async throws {
        guard nanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func fingerprint(_ values: String...) -> String {
        values.joined(separator: "\u{1F}")
    }

    static let demoHistory: [ChatMessage] = {
        let base = Date(timeIntervalSince1970: 1_775_000_000)
        return [
            ChatMessage(
                id: "mock-history-assistant-1",
                role: .assistant,
                content: "这里是离线聊天演示。",
                createdAt: base
            ),
            ChatMessage(
                id: "mock-history-user-1",
                role: .user,
                content: "我想试试消息时间流。",
                createdAt: base.addingTimeInterval(60)
            ),
            ChatMessage(
                id: "mock-history-assistant-2",
                role: .assistant,
                content: "可以发送一条短消息，也可以输入稍长的文字查看自动换行。演示内容不会写入本地文件。",
                createdAt: base.addingTimeInterval(120)
            ),
            ChatMessage(
                id: "mock-history-user-2",
                role: .user,
                content: "那就从这里开始。",
                createdAt: base.addingTimeInterval(180)
            )
        ]
    }()
}
