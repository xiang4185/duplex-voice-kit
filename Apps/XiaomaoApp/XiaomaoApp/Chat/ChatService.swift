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
        let reply: String
        let route: String
        let degraded: Bool

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case reply
            case route
            case degraded
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
        ChatHistoryResult(sessionID: UUID().uuidString.lowercased(), messages: [])
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
        let now = Date()
        return ChatSendResult(
            sessionID: response.sessionID,
            userMessage: ChatMessage(
                id: requestID + ".user",
                role: .user,
                content: message,
                createdAt: now
            ),
            assistantMessage: ChatMessage(
                id: requestID + ".assistant",
                role: .assistant,
                content: response.reply,
                createdAt: now
            ),
            route: response.route,
            degraded: response.degraded,
            persisted: true
        )
    }

    func clear(sessionID: String, requestID: String) async throws -> ChatClearResult {
        _ = requestID
        return ChatClearResult(sessionID: sessionID, cleared: true)
    }

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
