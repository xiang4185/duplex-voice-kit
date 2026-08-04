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
    private struct DeviceRequest: Encodable {
        let deviceID: String

        enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
        }
    }

    private struct SendRequest: Encodable {
        let deviceID: String
        let sessionID: String
        let requestID: String
        let message: String

        enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
            case sessionID = "session_id"
            case requestID = "request_id"
            case message
        }
    }

    private struct ClearRequest: Encodable {
        let deviceID: String
        let sessionID: String
        let requestID: String

        enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
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

    let client: APIClient
    let environment: AppEnvironment

    func loadHistory() async throws -> ChatHistoryResult {
        let response: HistoryResponse = try await client.post(
            "/v1/chat/history",
            body: DeviceRequest(deviceID: environment.deviceID)
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
        let response: SendResponse = try await client.post(
            "/v1/chat",
            body: SendRequest(
                deviceID: environment.deviceID,
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
        let response: ClearResponse = try await client.post(
            "/v1/chat/clear",
            body: ClearRequest(
                deviceID: environment.deviceID,
                sessionID: sessionID,
                requestID: requestID
            )
        )
        return ChatClearResult(sessionID: response.sessionID, cleared: response.cleared)
    }
}
