import Foundation
import XCTest
@testable import XiaomaoApp

final class ChatServiceContractTests: XCTestCase {
    func testProductionHistorySendClearAndRetryUseFormalEndpoints() async throws {
        let backend = ContractBackend()
        let service = ChatService(backend: backend)

        let history = try await service.loadHistory()
        let sent = try await service.send(
            message: "synthetic-message",
            sessionID: history.sessionID,
            requestID: "synthetic-send",
            xiaomaoMode: .always
        )
        let retried = try await service.retryXiaomao(
            turnID: "retry-turn",
            sessionID: history.sessionID,
            requestID: "synthetic-retry"
        )
        let cleared = try await service.clear(
            sessionID: history.sessionID,
            requestID: "synthetic-clear"
        )

        XCTAssertEqual(history.sessionID, "synthetic-session")
        XCTAssertEqual(history.messages.first?.participant, .developer)
        XCTAssertEqual(sent.turnID, "send-turn")
        XCTAssertEqual(
            sent.messages.map(\.participant),
            [.user, .xiaomao]
        )
        XCTAssertEqual(sent.participantResults.first?.participant, .developer)
        XCTAssertEqual(sent.participantResults.first?.status, .pending)
        XCTAssertEqual(sent.participantResults.last?.participant, .xiaomao)
        XCTAssertEqual(sent.participantResults.last?.status, .completed)
        XCTAssertEqual(retried.participant, .xiaomao)
        XCTAssertEqual(retried.message?.turnID, "retry-turn")
        XCTAssertEqual(cleared.sessionID, history.sessionID)
        XCTAssertTrue(cleared.cleared)
        let routes = await backend.routes()
        XCTAssertEqual(
            routes,
            [
                "/v1/chat/history",
                "/v1/chat",
                "/v1/chat/retry",
                "/v1/chat/clear"
            ]
        )
    }

    func testSendBodyContainsExplicitParticipationModeAndDoesNotInventPersistence() async throws {
        let backend = ContractBackend()
        let service = ChatService(backend: backend)

        let result = try await service.send(
            message: "synthetic-message",
            sessionID: "synthetic-session",
            requestID: "synthetic-request",
            xiaomaoMode: .off
        )

        let lastRequest = await backend.lastRequest()
        let request = try XCTUnwrap(lastRequest)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: request.payload) as? [String: Any]
        )
        XCTAssertEqual(request.route, "/v1/chat")
        XCTAssertEqual(body["session_id"] as? String, "synthetic-session")
        XCTAssertEqual(body["request_id"] as? String, "synthetic-request")
        XCTAssertEqual(body["xiaomao_mode"] as? String, "off")
        XCTAssertTrue(result.persisted)
        XCTAssertEqual(result.messages.first?.participant, .user)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.participantResults.first?.participant, .developer)
        XCTAssertEqual(result.participantResults.first?.status, .pending)
    }

    func testDeveloperTargetIsForwardedToSharedChatRequests() async throws {
        let backend = ContractBackend()
        let service = ChatService(backend: backend, targetDeviceID: "customer-device")

        _ = try await service.loadHistory()
        let sent = try await service.send(
            message: "developer-message",
            sessionID: "synthetic-session",
            requestID: "developer-request",
            xiaomaoMode: .off
        )

        let requests = await backend.allRequests()
        let historyBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: requests[0].payload) as? [String: Any]
        )
        let sendBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: requests[1].payload) as? [String: Any]
        )
        XCTAssertEqual(historyBody["target_device_id"] as? String, "customer-device")
        XCTAssertEqual(sendBody["target_device_id"] as? String, "customer-device")
        XCTAssertEqual(sent.messages.first?.participant, .developer)
    }
}

private actor ContractBackend: BackendAdapter {
    private var requests: [BackendAdapterRequest] = []

    func execute(_ request: BackendAdapterRequest) async throws -> BackendAdapterResponse {
        requests.append(request)
        let payload: Data
        switch request.route {
        case "/v1/chat/history":
            payload = try JSONSerialization.data(withJSONObject: [
                "session_id": "synthetic-session",
                "messages": [
                    Self.message(
                        id: "history-developer",
                        participant: "developer",
                        turnID: "history-turn",
                        content: "synthetic-history"
                    )
                ]
            ])
        case "/v1/chat":
            let requestBody = try XCTUnwrap(
                JSONSerialization.jsonObject(with: request.payload) as? [String: Any]
            )
            let includesXiaomao = requestBody["xiaomao_mode"] as? String == "always"
            let isDeveloper = requestBody["target_device_id"] != nil
            var messages = [
                Self.message(
                    id: isDeveloper ? "send-developer" : "send-user",
                    role: "user",
                    participant: isDeveloper ? "developer" : "user",
                    turnID: "send-turn",
                    content: "synthetic-message"
                )
            ]
            if includesXiaomao {
                messages.append(Self.message(
                    id: "send-xiaomao",
                    participant: "xiaomao",
                    turnID: "send-turn",
                    content: "synthetic-xiaomao"
                ))
            }
            let xiaomaoMessage: Any = includesXiaomao
                ? Self.message(
                    id: "send-xiaomao",
                    participant: "xiaomao",
                    turnID: "send-turn",
                    content: "synthetic-xiaomao"
                )
                : NSNull()
            payload = try JSONSerialization.data(withJSONObject: [
                "session_id": "synthetic-session",
                "turn_id": "send-turn",
                "messages": messages,
                "participant_results": [
                    [
                        "participant": "developer",
                        "turn_id": "send-turn",
                        "status": "pending",
                        "retryable": false,
                        "message": NSNull()
                    ],
                    [
                        "participant": "xiaomao",
                        "turn_id": "send-turn",
                        "status": includesXiaomao ? "completed" : "skipped",
                        "retryable": false,
                        "message": xiaomaoMessage
                    ]
                ],
                "route": includesXiaomao ? "direct" : "human",
                "degraded": false,
                "persisted": true
            ])
        case "/v1/chat/retry":
            payload = try JSONSerialization.data(withJSONObject: [
                "session_id": "synthetic-session",
                "turn_id": "retry-turn",
                "participant": "xiaomao",
                "status": "completed",
                "retryable": false,
                "message": Self.message(
                    id: "retry-xiaomao",
                    participant: "xiaomao",
                    turnID: "retry-turn",
                    content: "synthetic-retry"
                ),
                "persisted": true
            ])
        case "/v1/chat/clear":
            payload = try JSONSerialization.data(withJSONObject: [
                "session_id": "synthetic-session",
                "cleared": true
            ])
        default:
            XCTFail("Unexpected route: \(request.route)")
            payload = Data()
        }
        return BackendAdapterResponse(statusCode: 200, payload: payload)
    }

    func snapshot() async -> BackendAdapterSnapshot {
        BackendAdapterSnapshot(
            mode: .production,
            invocationCount: requests.count,
            networkRequestCount: requests.count
        )
    }

    func routes() -> [String] { requests.map(\.route) }
    func lastRequest() -> BackendAdapterRequest? { requests.last }
    func allRequests() -> [BackendAdapterRequest] { requests }

    private static func message(
        id: String,
        role: String = "assistant",
        participant: String,
        turnID: String,
        content: String
    ) -> [String: Any] {
        [
            "id": id,
            "role": role,
            "participant": participant,
            "turn_id": turnID,
            "status": "completed",
            "content": content,
            "created_at": "2026-08-06T00:00:00Z"
        ]
    }
}
