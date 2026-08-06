import Foundation
import XCTest
@testable import XiaomaoApp

final class ChatServiceContractTests: XCTestCase {
    func testProductionHistoryAndClearRemainLocal() async throws {
        let backend = ContractBackend()
        let service = ChatService(backend: backend)

        let history = try await service.loadHistory()
        let cleared = try await service.clear(
            sessionID: history.sessionID,
            requestID: "synthetic-clear"
        )

        XCTAssertTrue(history.messages.isEmpty)
        XCTAssertFalse(history.sessionID.isEmpty)
        XCTAssertEqual(cleared.sessionID, history.sessionID)
        XCTAssertTrue(cleared.cleared)
        let routes = await backend.routes()
        XCTAssertEqual(routes, [])
    }

    func testSendUsesOnlyExistingChatEndpointAndMapsCurrentResponse() async throws {
        let backend = ContractBackend()
        let service = ChatService(backend: backend)

        let result = try await service.send(
            message: "synthetic-message",
            sessionID: "synthetic-session",
            requestID: "synthetic-request"
        )

        let routes = await backend.routes()
        XCTAssertEqual(routes, ["/v1/chat"])
        XCTAssertEqual(result.sessionID, "synthetic-session")
        XCTAssertEqual(result.userMessage.content, "synthetic-message")
        XCTAssertEqual(result.assistantMessage.content, "synthetic-reply")
        XCTAssertEqual(result.route, "direct")
        XCTAssertFalse(result.degraded)
        XCTAssertTrue(result.persisted)
    }
}

private actor ContractBackend: BackendAdapter {
    private var requestedRoutes: [String] = []

    func execute(_ request: BackendAdapterRequest) async throws -> BackendAdapterResponse {
        requestedRoutes.append(request.route)
        let requestObject = try JSONSerialization.jsonObject(with: request.payload) as? [String: Any]
        let sessionID = requestObject?["session_id"] as? String ?? ""
        let payload = try JSONSerialization.data(withJSONObject: [
            "session_id": sessionID,
            "reply": "synthetic-reply",
            "route": "direct",
            "degraded": false
        ])
        return BackendAdapterResponse(statusCode: 200, payload: payload)
    }

    func snapshot() async -> BackendAdapterSnapshot {
        BackendAdapterSnapshot(
            mode: .production,
            invocationCount: requestedRoutes.count,
            networkRequestCount: requestedRoutes.count
        )
    }

    func routes() -> [String] { requestedRoutes }
}
