import Foundation

struct ChatHistoryResult: Equatable, Sendable {
    let sessionID: String
    let messages: [ChatMessage]
}

struct ChatSendResult: Equatable, Sendable {
    let sessionID: String
    let userMessage: ChatMessage
    let assistantMessage: ChatMessage
    let route: String
    let degraded: Bool
    let persisted: Bool
}

struct ChatClearResult: Equatable, Sendable {
    let sessionID: String
    let cleared: Bool
}

protocol ChatServicing: Sendable {
    func loadHistory() async throws -> ChatHistoryResult
    func send(message: String, sessionID: String, requestID: String) async throws -> ChatSendResult
    func clear(sessionID: String, requestID: String) async throws -> ChatClearResult
}

struct ChatService: ChatServicing {
    private struct SendRequest: Encodable {
        let sessionID: String
        let requestID: String
        let message: String

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case requestID = "request_id"
            case message
        }
    }

    private struct ClearRequest: Encodable {
        let sessionID: String
        let requestID: String

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case requestID = "request_id"
        }
    }

    private struct HistoryResponse: Decodable {
        let sessionID: String
        let messages: [ChatMessage]

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case messages
        }
    }

    private struct SendResponse: Decodable {
        let sessionID: String
        let userMessage: ChatMessage
        let assistantMessage: ChatMessage
        let route: String
        let degraded: Bool
        let persisted: Bool

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case userMessage = "user_message"
            case assistantMessage = "assistant_message"
            case route
            case degraded
            case persisted
        }
    }

    private struct ClearResponse: Decodable {
        let sessionID: String
        let cleared: Bool

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case cleared
        }
    }

    let backend: any BackendAdapter

    init(backend: any BackendAdapter) {
        self.backend = backend
    }

    func loadHistory() async throws -> ChatHistoryResult {
        let response: HistoryResponse = try await execute(
            route: "/v1/chat/history",
            body: EmptyRequest()
        )
        return ChatHistoryResult(
            sessionID: response.sessionID,
            messages: response.messages
        )
    }

    func send(
        message: String,
        sessionID: String,
        requestID: String
    ) async throws -> ChatSendResult {
        let response: SendResponse = try await execute(
            route: "/v1/chat",
            body: SendRequest(
                sessionID: sessionID,
                requestID: requestID,
                message: message
            )
        )
        return ChatSendResult(
            sessionID: response.sessionID,
            userMessage: response.userMessage,
            assistantMessage: response.assistantMessage,
            route: response.route,
            degraded: response.degraded,
            persisted: response.persisted
        )
    }

    func clear(sessionID: String, requestID: String) async throws -> ChatClearResult {
        let response: ClearResponse = try await execute(
            route: "/v1/chat/clear",
            body: ClearRequest(
                sessionID: sessionID,
                requestID: requestID
            )
        )
        return ChatClearResult(sessionID: response.sessionID, cleared: response.cleared)
    }

    private struct EmptyRequest: Encodable {}

    private func execute<Input: Encodable, Output: Decodable>(
        route: String,
        body: Input
    ) async throws -> Output {
        let payload = try JSONEncoder().encode(body)
        let response = try await backend.execute(
            BackendAdapterRequest(route: route, payload: payload)
        )
        guard 200..<300 ~= response.statusCode else {
            throw AppError.server("http_\(response.statusCode)")
        }
        do {
            return try JSONDecoder().decode(Output.self, from: response.payload)
        } catch {
            throw AppError.protocolError("invalid_response")
        }
    }
}
