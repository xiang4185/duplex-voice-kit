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
        case retry(fingerprint: String, result: ChatRetryResult)
        case clear(fingerprint: String, result: ChatClearResult)
    }

    private let sessionID: String
    private let delays: Delays
    private let now: @Sendable () -> Date
    private var messages: [ChatMessage]
    private var storedResults: [String: StoredResult] = [:]

    init(
        delays: Delays = .demo,
        sessionID: String = "mock-chat-session-v2",
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
        requestID: String,
        xiaomaoMode: XiaomaoParticipationMode
    ) async throws -> ChatSendResult {
        try await pause(delays.sendNanoseconds)
        let key = "send:\(requestID)"
        let fingerprint = Self.fingerprint(sessionID, message, xiaomaoMode.rawValue)
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
        let turnID = "mock-turn-\(UUID().uuidString.lowercased())"
        let userMessage = ChatMessage(
            id: "mock-user-\(UUID().uuidString.lowercased())",
            role: .user,
            content: message,
            createdAt: timestamp,
            participant: .user,
            turnID: turnID
        )
        let developerMessage = ChatMessage(
            id: "mock-developer-\(UUID().uuidString.lowercased())",
            role: .assistant,
            content: "开发者已通过离线 Mock 回复。",
            createdAt: timestamp.addingTimeInterval(0.001),
            participant: .developer,
            turnID: turnID
        )
        var turnMessages = [userMessage, developerMessage]
        var participantResults = [
            ChatParticipantResult(
                participant: .developer,
                turnID: turnID,
                status: .completed,
                retryable: false,
                message: developerMessage
            )
        ]
        if shouldIncludeXiaomao(mode: xiaomaoMode, message: message) {
            let xiaomaoMessage = ChatMessage(
                id: "mock-xiaomao-\(UUID().uuidString.lowercased())",
                role: .assistant,
                content: "小猫也在，先陪你把这一轮接住。",
                createdAt: timestamp.addingTimeInterval(0.002),
                participant: .xiaomao,
                turnID: turnID
            )
            turnMessages.append(xiaomaoMessage)
            participantResults.append(ChatParticipantResult(
                participant: .xiaomao,
                turnID: turnID,
                status: .completed,
                retryable: false,
                message: xiaomaoMessage
            ))
        } else {
            participantResults.append(ChatParticipantResult(
                participant: .xiaomao,
                turnID: turnID,
                status: .skipped,
                retryable: false,
                message: nil
            ))
        }
        let result = ChatSendResult(
            sessionID: self.sessionID,
            turnID: turnID,
            messages: turnMessages,
            participantResults: participantResults,
            route: "mock",
            degraded: false,
            persisted: true
        )
        messages.append(contentsOf: turnMessages)
        storedResults[key] = .send(fingerprint: fingerprint, result: result)
        return result
    }

    func retryXiaomao(
        turnID: String,
        sessionID: String,
        requestID: String
    ) async throws -> ChatRetryResult {
        try await pause(delays.sendNanoseconds)
        let key = "retry:\(requestID)"
        let fingerprint = Self.fingerprint(sessionID, turnID)
        if let stored = storedResults[key] {
            guard case let .retry(storedFingerprint, result) = stored,
                  storedFingerprint == fingerprint else {
                throw AppError.server("idempotency_conflict")
            }
            return result
        }
        guard sessionID == self.sessionID,
              messages.contains(where: { $0.turnID == turnID && $0.participant == .user }) else {
            throw AppError.server("session_mismatch")
        }
        if messages.contains(where: { $0.turnID == turnID && $0.participant == .xiaomao }) {
            throw AppError.server("participant_already_completed")
        }
        let message = ChatMessage(
            id: "mock-xiaomao-retry-\(UUID().uuidString.lowercased())",
            role: .assistant,
            content: "刚才没接上，现在小猫回来啦。",
            createdAt: now(),
            participant: .xiaomao,
            turnID: turnID
        )
        messages.append(message)
        let result = ChatRetryResult(
            sessionID: sessionID,
            turnID: turnID,
            participant: .xiaomao,
            status: .completed,
            retryable: false,
            message: message,
            persisted: true
        )
        storedResults[key] = .retry(fingerprint: fingerprint, result: result)
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

    private func shouldIncludeXiaomao(
        mode: XiaomaoParticipationMode,
        message: String
    ) -> Bool {
        switch mode {
        case .off: false
        case .always: true
        case .auto:
            message.localizedCaseInsensitiveContains("小猫")
                || message.localizedCaseInsensitiveContains("猫猫")
                || message.localizedCaseInsensitiveContains("你们俩")
        }
    }

    private static func fingerprint(_ values: String...) -> String {
        values.joined(separator: "\u{1F}")
    }

    static let demoHistory: [ChatMessage] = {
        let base = Date(timeIntervalSince1970: 1_775_000_000)
        let firstTurn = "mock-history-turn-1"
        let secondTurn = "mock-history-turn-2"
        return [
            ChatMessage(
                id: "mock-history-user-1",
                role: .user,
                content: "今天总算把拖了很久的事情做完了。",
                createdAt: base,
                participant: .user,
                turnID: firstTurn
            ),
            ChatMessage(
                id: "mock-history-developer-1",
                role: .assistant,
                content: "那种一直压在心里的东西终于放下来的感觉，应该很轻松。",
                createdAt: base.addingTimeInterval(1),
                participant: .developer,
                turnID: firstTurn
            ),
            ChatMessage(
                id: "mock-history-xiaomao-1",
                role: .assistant,
                content: "应该奖励一下。至少可以理直气壮地躺一会儿。",
                createdAt: base.addingTimeInterval(2),
                participant: .xiaomao,
                turnID: firstTurn
            ),
            ChatMessage(
                id: "mock-history-user-2",
                role: .user,
                content: "你们两个今天倒是意见很一致。",
                createdAt: base.addingTimeInterval(60),
                participant: .user,
                turnID: secondTurn
            ),
            ChatMessage(
                id: "mock-history-developer-2",
                role: .assistant,
                content: "因为这次确实值得夸你。",
                createdAt: base.addingTimeInterval(61),
                participant: .developer,
                turnID: secondTurn
            ),
            ChatMessage(
                id: "mock-history-xiaomao-2",
                role: .assistant,
                content: "我负责监督你别马上又给自己安排下一件事。",
                createdAt: base.addingTimeInterval(62),
                participant: .xiaomao,
                turnID: secondTurn
            )
        ]
    }()
}
