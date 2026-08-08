import Foundation

protocol ChatServicing: Sendable {
    func loadHistory() async throws -> ChatHistoryResult
    func send(
        message: String,
        sessionID: String,
        requestID: String,
        xiaomaoMode: XiaomaoParticipationMode
    ) async throws -> ChatSendResult
    func retryXiaomao(
        turnID: String,
        sessionID: String,
        requestID: String
    ) async throws -> ChatRetryResult
    func clear(sessionID: String, requestID: String) async throws -> ChatClearResult
}

extension ChatServicing {
    func send(
        message: String,
        sessionID: String,
        requestID: String
    ) async throws -> ChatSendResult {
        try await send(
            message: message,
            sessionID: sessionID,
            requestID: requestID,
            xiaomaoMode: .auto
        )
    }
}

struct ChatHistoryResult: Equatable, Sendable {
    let sessionID: String
    let messages: [ChatMessage]
}

struct ChatSendResult: Equatable, Sendable {
    let sessionID: String
    let turnID: String
    let messages: [ChatMessage]
    let participantResults: [ChatParticipantResult]
    let route: String
    let degraded: Bool
    let persisted: Bool

    init(
        sessionID: String,
        turnID: String,
        messages: [ChatMessage],
        participantResults: [ChatParticipantResult],
        route: String,
        degraded: Bool,
        persisted: Bool
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.messages = messages
        self.participantResults = participantResults
        self.route = route
        self.degraded = degraded
        self.persisted = persisted
    }

    var userMessage: ChatMessage {
        messages.first(where: { $0.participant == .user }) ?? messages[0]
    }

    var developerMessage: ChatMessage? {
        messages.first(where: { $0.participant == .developer })
    }
}

struct ChatRetryResult: Equatable, Sendable {
    let sessionID: String
    let turnID: String
    let participant: ChatParticipant
    let status: ChatMessageStatus
    let retryable: Bool
    let message: ChatMessage?
    let persisted: Bool
}

struct ChatClearResult: Equatable, Sendable {
    let sessionID: String
    let cleared: Bool
}

actor ChatService: ChatServicing {
    private struct HistoryRequest: Encodable {}
    private struct HistoryResponse: Decodable {
        let sessionID: String
        let messages: [ServerMessage]

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case messages
        }
    }

    private struct SendRequest: Encodable {
        let sessionID: String
        let message: String
        let requestID: String
        let xiaomaoMode: String

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case message
            case requestID = "request_id"
            case xiaomaoMode = "xiaomao_mode"
        }
    }

    private struct SendResponse: Decodable {
        let sessionID: String
        let turnID: String
        let messages: [ServerMessage]
        let participantResults: [ServerParticipantResult]
        let route: String
        let degraded: Bool
        let persisted: Bool

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case turnID = "turn_id"
            case messages
            case participantResults = "participant_results"
            case route
            case degraded
            case persisted
        }
    }

    private struct RetryRequest: Encodable {
        let sessionID: String
        let requestID: String
        let turnID: String
        let participant: String

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case requestID = "request_id"
            case turnID = "turn_id"
            case participant
        }
    }

    private struct RetryResponse: Decodable {
        let sessionID: String
        let turnID: String
        let participant: ChatParticipant
        let status: ChatMessageStatus
        let retryable: Bool
        let message: ServerMessage?
        let persisted: Bool

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case turnID = "turn_id"
            case participant
            case status
            case retryable
            case message
            case persisted
        }
    }

    private struct ClearRequest: Encodable {
        let sessionID: String
        let requestID: String

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case requestID = "request_id"
        }
    }

    private struct ClearResponse: Decodable {
        let sessionID: String
        let cleared: Bool

        private enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case cleared
        }
    }

    private struct ServerParticipantResult: Decodable {
        let participant: ChatParticipant
        let turnID: String
        let status: ChatMessageStatus
        let retryable: Bool
        let message: ServerMessage?

        private enum CodingKeys: String, CodingKey {
            case participant
            case turnID = "turn_id"
            case status
            case retryable
            case message
        }

        func clientResult() throws -> ChatParticipantResult {
            ChatParticipantResult(
                participant: participant,
                turnID: turnID,
                status: status,
                retryable: retryable,
                message: try message?.clientMessage()
            )
        }
    }

    private struct ServerMessage: Decodable {
        let id: String
        let role: ChatMessage.Role
        let participant: ChatParticipant
        let turnID: String
        let status: ChatMessageStatus
        let content: String
        let createdAt: String

        private enum CodingKeys: String, CodingKey {
            case id
            case role
            case participant
            case turnID = "turn_id"
            case status
            case content
            case createdAt = "created_at"
        }

        func clientMessage() throws -> ChatMessage {
            guard let date = ChatService.date(from: createdAt) else {
                throw AppError.protocolError("invalid_created_at")
            }
            return ChatMessage(
                id: id,
                role: role,
                content: content,
                createdAt: date,
                participant: participant,
                turnID: turnID,
                status: status
            )
        }
    }

    private let backend: any BackendAdapter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(backend: any BackendAdapter) {
        self.backend = backend
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func loadHistory() async throws -> ChatHistoryResult {
        let response = try await execute(
            route: "/v1/chat/history",
            body: HistoryRequest(),
            as: HistoryResponse.self
        )
        return ChatHistoryResult(
            sessionID: response.sessionID,
            messages: try response.messages.map { try $0.clientMessage() }
        )
    }

    func send(
        message: String,
        sessionID: String,
        requestID: String,
        xiaomaoMode: XiaomaoParticipationMode
    ) async throws -> ChatSendResult {
        let response = try await execute(
            route: "/v1/chat",
            body: SendRequest(
                sessionID: sessionID,
                message: message,
                requestID: requestID,
                xiaomaoMode: xiaomaoMode.rawValue
            ),
            as: SendResponse.self
        )
        let messages = try response.messages.map { try $0.clientMessage() }
        guard response.persisted,
              !response.turnID.isEmpty,
              messages.contains(where: { $0.participant == .user }),
              messages.allSatisfy({ $0.turnID == response.turnID }) else {
            throw AppError.protocolError("invalid_chat_contract")
        }
        return ChatSendResult(
            sessionID: response.sessionID,
            turnID: response.turnID,
            messages: messages,
            participantResults: try response.participantResults.map {
                try $0.clientResult()
            },
            route: response.route,
            degraded: response.degraded,
            persisted: response.persisted
        )
    }

    func retryXiaomao(
        turnID: String,
        sessionID: String,
        requestID: String
    ) async throws -> ChatRetryResult {
        let response = try await execute(
            route: "/v1/chat/retry",
            body: RetryRequest(
                sessionID: sessionID,
                requestID: requestID,
                turnID: turnID,
                participant: ChatParticipant.xiaomao.rawValue
            ),
            as: RetryResponse.self
        )
        return ChatRetryResult(
            sessionID: response.sessionID,
            turnID: response.turnID,
            participant: response.participant,
            status: response.status,
            retryable: response.retryable,
            message: try response.message?.clientMessage(),
            persisted: response.persisted
        )
    }

    func clear(sessionID: String, requestID: String) async throws -> ChatClearResult {
        let response = try await execute(
            route: "/v1/chat/clear",
            body: ClearRequest(sessionID: sessionID, requestID: requestID),
            as: ClearResponse.self
        )
        return ChatClearResult(sessionID: response.sessionID, cleared: response.cleared)
    }

    private func execute<Request: Encodable, Response: Decodable>(
        route: String,
        body: Request,
        as type: Response.Type
    ) async throws -> Response {
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            throw AppError.protocolError("invalid_request")
        }
        let response = try await backend.execute(
            BackendAdapterRequest(route: route, payload: payload)
        )
        guard 200..<300 ~= response.statusCode else {
            throw AppError.server("http_\(response.statusCode)")
        }
        do {
            return try decoder.decode(type, from: response.payload)
        } catch {
            throw AppError.protocolError("invalid_response")
        }
    }

    private static func date(from rawValue: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: rawValue) { return date }
        return ISO8601DateFormatter().date(from: rawValue)
    }
}
