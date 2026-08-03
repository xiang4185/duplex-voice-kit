import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The frozen neutral chat wire contract: POST /v1/chat with device_id,
/// session_id, message and request_id fields.
public struct DVKChatRequest: Encodable, Equatable, Sendable {
    public let deviceID: String
    public let sessionID: String
    public let message: String
    public let requestID: String

    public init(deviceID: String, sessionID: String, message: String, requestID: String) {
        self.deviceID = deviceID
        self.sessionID = sessionID
        self.message = message
        self.requestID = requestID
    }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case sessionID = "session_id"
        case message
        case requestID = "request_id"
    }
}

/// The frozen neutral chat wire response: reply plus degraded flag.
public struct DVKChatResponse: Decodable, Equatable, Sendable {
    public let reply: String
    public let degraded: Bool
}

public struct DVKChatReply: Equatable, Sendable {
    public let text: String
    public let degraded: Bool
}

public enum DVKChatServiceError: Error, Equatable, Sendable {
    case emptyMessage
    case unauthorized
    case networkUnavailable
    case server(String)
    case invalidResponse
}

/// Live chat service over POST /v1/chat.
///
/// - A new logical message always allocates a fresh request_id.
/// - A network retry of the same logical message reuses the same request_id.
/// - Empty messages are rejected before any network attempt.
/// - Mock and live flows share the same public DVKChatServicing surface.
public actor DVKChatService: DVKChatServicing {
    private let client: DVKBackendClient
    private let sessionID: String

    public init(
        baseURL: URL,
        tokenStore: any DVKTokenStoring,
        deviceID: String,
        session: URLSession = .shared,
        sessionID: String = UUID().uuidString
    ) {
        self.client = DVKBackendClient(
            baseURL: baseURL,
            tokenStore: tokenStore,
            deviceID: deviceID,
            session: session
        )
        self.sessionID = sessionID
    }

    public func send(text: String) async throws -> String {
        try await performSend(text: text, context: nil)
    }

    public func send(text: String, context: DVKCompanionSessionContext) async throws -> String {
        try await performSend(text: text, context: context)
    }

    private func performSend(
        text: String,
        context: DVKCompanionSessionContext?
    ) async throws -> String {
        _ = context
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DVKChatServiceError.emptyMessage }

        // One logical message -> one request_id, reused by the single retry.
        let requestID = UUID().uuidString
        for attempt in 0...1 {
            do {
                let response: DVKChatResponse = try await client.post(
                    path: "v1/chat",
                    body: DVKChatRequest(
                        deviceID: client.deviceID,
                        sessionID: sessionID,
                        message: trimmed,
                        requestID: requestID
                    )
                )
                return response.reply
            } catch let error as DVKBackendError {
                let retryable: Bool
                switch error {
                case .networkUnavailable: retryable = true
                case .server(let code): retryable = code.hasPrefix("http_5")
                default: retryable = false
                }
                if attempt == 0 && retryable { continue }
                throw Self.map(error)
            } catch {
                throw DVKChatServiceError.networkUnavailable
            }
        }
        throw DVKChatServiceError.networkUnavailable
    }

    private static func map(_ error: DVKBackendError) -> DVKChatServiceError {
        switch error {
        case .unauthorized: return .unauthorized
        case .networkUnavailable: return .networkUnavailable
        case .invalidConfiguration: return .networkUnavailable
        case .server(let value): return .server(value)
        case .invalidResponse: return .invalidResponse
        }
    }
}
