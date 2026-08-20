import XCTest
import UIKit
@testable import XiaomaoApp

final class ChatAvatarStoreTests: XCTestCase {
    @MainActor
    func testLoadCachesBothSharedParticipantAvatars() async throws {
        let suite = "ChatAvatarStoreTests.load.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let userData = Data("user-avatar".utf8)
        let developerData = Data("developer-avatar".utf8)
        let backend = AvatarBackendStub(
            stateAvatars: [
                (.user, userData),
                (.developer, developerData),
            ]
        )
        let store = ChatAvatarStore(
            service: ChatAvatarService(backend: backend, targetDeviceID: nil),
            localParticipant: .user,
            defaults: defaults
        )

        await store.load()

        XCTAssertEqual(store.imageData(for: .user), userData)
        XCTAssertEqual(store.imageData(for: .developer), developerData)
        let routes = await backend.routes()
        XCTAssertEqual(routes, ["/v1/chat/avatars"])
    }

    @MainActor
    func testUpdateCompressesAndPersistsOnlyAuthenticatedParticipant() async throws {
        let suite = "ChatAvatarStoreTests.update.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = AvatarBackendStub(updateParticipant: .developer)
        let store = ChatAvatarStore(
            service: ChatAvatarService(
                backend: backend,
                targetDeviceID: "owner-device"
            ),
            localParticipant: .developer,
            defaults: defaults
        )
        let source = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 320)).image { context in
            UIColor.systemPink.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 640, height: 320))
        }

        await store.update(with: try XCTUnwrap(source.pngData()))

        let saved = try XCTUnwrap(store.imageData(for: .developer))
        let image = try XCTUnwrap(UIImage(data: saved))
        XCTAssertEqual(image.size, CGSize(width: 256, height: 256))
        XCTAssertLessThan(saved.count, 512_000)
        XCTAssertNil(store.errorMessage)
        let routes = await backend.routes()
        XCTAssertEqual(routes, ["/v1/chat/avatar/update"])
    }

    @MainActor
    func testFailedUploadKeepsLocalAvatarAndRetriesOnLoad() async throws {
        let suite = "ChatAvatarStoreTests.retry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = AvatarBackendStub(updateParticipant: .user, updateFailures: 1)
        let store = ChatAvatarStore(
            service: ChatAvatarService(backend: backend, targetDeviceID: nil),
            localParticipant: .user,
            defaults: defaults
        )
        let source = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image {
            context in
            UIColor.systemBlue.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        }

        await store.update(with: try XCTUnwrap(source.pngData()))
        XCTAssertNotNil(store.imageData(for: .user))
        XCTAssertNotNil(store.errorMessage)

        await store.load()
        XCTAssertNil(store.errorMessage)
        let routes = await backend.routes()
        XCTAssertEqual(
            routes,
            ["/v1/chat/avatar/update", "/v1/chat/avatars", "/v1/chat/avatar/update"]
        )
    }
}

private actor AvatarBackendStub: BackendAdapter {
    private let stateAvatars: [(ChatParticipant, Data)]
    private let updateParticipant: ChatParticipant
    private var updateFailures: Int
    private var requestedRoutes: [String] = []

    init(
        stateAvatars: [(ChatParticipant, Data)] = [],
        updateParticipant: ChatParticipant = .user,
        updateFailures: Int = 0
    ) {
        self.stateAvatars = stateAvatars
        self.updateParticipant = updateParticipant
        self.updateFailures = updateFailures
    }

    func execute(_ request: BackendAdapterRequest) async throws -> BackendAdapterResponse {
        requestedRoutes.append(request.route)
        switch request.route {
        case "/v1/chat/avatars":
            return BackendAdapterResponse(
                statusCode: 200,
                payload: try JSONSerialization.data(withJSONObject: [
                    "avatars": stateAvatars.map { participant, data in
                        [
                            "participant": participant.rawValue,
                            "mime_type": "image/jpeg",
                            "data_base64": data.base64EncodedString(),
                        ]
                    }
                ])
            )
        case "/v1/chat/avatar/update":
            if updateFailures > 0 {
                updateFailures -= 1
                throw AppError.networkUnavailable
            }
            guard let body = try JSONSerialization.jsonObject(with: request.payload) as? [String: Any],
                  let encoded = body["data_base64"] as? String else {
                throw HostAdapterError.invalidResponse
            }
            return BackendAdapterResponse(
                statusCode: 200,
                payload: try JSONSerialization.data(withJSONObject: [
                    "avatar": [
                        "participant": updateParticipant.rawValue,
                        "mime_type": "image/jpeg",
                        "data_base64": encoded,
                    ]
                ])
            )
        default:
            return BackendAdapterResponse(statusCode: 404)
        }
    }

    func snapshot() async -> BackendAdapterSnapshot {
        BackendAdapterSnapshot(mode: .mock, invocationCount: requestedRoutes.count, networkRequestCount: 0)
    }

    func routes() -> [String] { requestedRoutes }
}
