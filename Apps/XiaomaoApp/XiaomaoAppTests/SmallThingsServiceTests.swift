import Foundation
import ImageIO
import UIKit
import XCTest
@testable import XiaomaoApp

@MainActor
final class SmallThingsServiceTests: XCTestCase {
    func testProductionStateMapsServerIDsParticipantsAndMediaReference() async throws {
        let backend = SmallThingsBackendSpy()
        let service = ProductionSmallThingsService(backend: backend)

        let state = try await service.loadState()

        XCTAssertEqual(state.bindingState, .bound)
        XCTAssertEqual(state.ledgerLimit, 52)
        XCTAssertEqual(state.approvedAmount, 12)
        XCTAssertEqual(state.pendingAmount, 8)
        XCTAssertEqual(state.remainingAmount, 32)
        let entry = try XCTUnwrap(state.entries.first)
        XCTAssertEqual(entry.serverID, SmallThingsBackendSpy.entryID)
        XCTAssertEqual(entry.requester, .partner)
        XCTAssertNil(entry.reviewer)
        XCTAssertEqual(entry.imageMediaID, SmallThingsBackendSpy.mediaID)
        XCTAssertEqual(entry.comments.first?.serverID, SmallThingsBackendSpy.commentID)
        XCTAssertEqual(
            entry.comments.first?.replies.first?.serverID,
            SmallThingsBackendSpy.replyID
        )
        let routes = await backend.routes()
        XCTAssertEqual(routes, ["/v1/small-things/state"])
    }

    func testCreateNoteRerendersJPEGWithoutMetadataBeforeUploading() async throws {
        let backend = SmallThingsBackendSpy()
        let service = ProductionSmallThingsService(backend: backend)
        let source = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image {
            context in
            UIColor.systemPink.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
        let sourceData = try XCTUnwrap(source.pngData())

        try await service.createNote(
            title: "synthetic-title",
            body: "synthetic-body",
            imageData: sourceData,
            requestID: "synthetic-note"
        )

        let requests = await backend.requests()
        XCTAssertEqual(
            requests.map(\.route),
            [
                "/v1/small-things/media/upload",
                "/v1/small-things/entries/create"
            ]
        )
        let uploadBody = try Self.jsonBody(requests[0])
        XCTAssertEqual(uploadBody["mime_type"] as? String, "image/jpeg")
        let encoded = try XCTUnwrap(uploadBody["data_base64"] as? String)
        let uploaded = try XCTUnwrap(Data(base64Encoded: encoded))
        XCTAssertLessThanOrEqual(uploaded.count, 1_900_000)
        XCTAssertEqual(Data(uploaded.prefix(2)), Data([0xFF, 0xD8]))
        let sourceRef = try XCTUnwrap(
            CGImageSourceCreateWithData(uploaded as CFData, nil)
        )
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [CFString: Any]
        )
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(properties[kCGImagePropertyExifAuxDictionary])

        let entryBody = try Self.jsonBody(requests[1])
        let imageMetadata = try XCTUnwrap(
            entryBody["image_metadata"] as? [String: Any]
        )
        XCTAssertEqual(imageMetadata["media_id"] as? String, SmallThingsBackendSpy.mediaID)
        XCTAssertFalse(entryBody.keys.contains("image_data"))
    }

    func testFormalSmallThingsActionsUseBackendRoutes() async throws {
        let backend = SmallThingsBackendSpy()
        let service = ProductionSmallThingsService(backend: backend)

        try await service.createExpense(
            purpose: "synthetic-expense",
            amountCents: 123,
            note: "synthetic-note",
            requestID: "expense"
        )
        try await service.deleteEntry(
            entryID: SmallThingsBackendSpy.entryID,
            requestID: "delete"
        )
        try await service.toggleReaction(entryID: SmallThingsBackendSpy.entryID, requestID: "reaction")
        try await service.createComment(
            entryID: SmallThingsBackendSpy.entryID,
            text: "synthetic-comment",
            requestID: "comment"
        )
        try await service.createReply(
            entryID: SmallThingsBackendSpy.entryID,
            commentID: SmallThingsBackendSpy.commentID,
            replyToID: SmallThingsBackendSpy.replyID,
            text: "synthetic-reply",
            requestID: "reply"
        )
        let receipt = try await service.review(
            entryID: SmallThingsBackendSpy.entryID,
            status: .approved,
            message: "synthetic-review",
            requestID: "review"
        )
        try await service.undo(receipt, requestID: "undo")
        let bindingCode = try await service.createBindingCode(requestID: "code")
        XCTAssertEqual(bindingCode, "123456")
        try await service.acceptBindingCode("123456", requestID: "accept")
        try await service.unbind(requestID: "unbind")
        let media = try await service.loadMedia(mediaID: SmallThingsBackendSpy.mediaID)
        XCTAssertEqual(media, SmallThingsBackendSpy.mediaBytes)

        let routes = await backend.routes()
        XCTAssertEqual(
            routes,
            [
                "/v1/small-things/entries/create",
                "/v1/small-things/entries/delete",
                "/v1/small-things/reactions/toggle",
                "/v1/small-things/comments/create",
                "/v1/small-things/replies/create",
                "/v1/small-things/approvals/review",
                "/v1/small-things/approvals/undo",
                "/v1/small-things/binding/code/create",
                "/v1/small-things/binding/code/accept",
                "/v1/small-things/binding/unbind",
                "/v1/small-things/media/read"
            ]
        )
    }

    func testLedgerLimitUpdateUsesBackendAndAppliesAuthoritativeValue() async throws {
        let backend = SmallThingsBackendSpy()
        let service = ProductionSmallThingsService(backend: backend)

        let result = try await service.updateLedgerLimit(
            limitCents: 12_345,
            requestID: "limit-update"
        )

        XCTAssertEqual(result.ledgerLimit, 123.45)
        let requests = await backend.requests()
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.route, "/v1/small-things/ledger/limit")
        let body = try Self.jsonBody(request)
        XCTAssertEqual(body["limit_cents"] as? Int, 12_345)
        XCTAssertEqual(body["request_id"] as? String, "limit-update")
    }

    func testProductionStoreReloadsAuthoritativeStateAfterWrite() async {
        let service = SmallThingsServiceSpy()
        let store = SmallThingsStore(service: service)

        await store.refreshFromBackend()
        XCTAssertTrue(store.entries.isEmpty)

        let saved = await store.addNotePersisted(
            title: "synthetic",
            body: "authoritative",
            imageData: nil
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.serverID, "authoritative-entry")
        let createCount = await service.createNoteCount()
        let loadCount = await service.loadCount()
        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(loadCount, 2)
    }

    private static func jsonBody(_ request: BackendAdapterRequest) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: request.payload) as? [String: Any]
        )
    }
}

private actor SmallThingsBackendSpy: BackendAdapter {
    static let entryID = "11111111111111111111111111111111"
    static let commentID = "22222222222222222222222222222222"
    static let replyID = "33333333333333333333333333333333"
    static let mediaID = "44444444444444444444444444444444"
    static let mediaBytes = Data([0xFF, 0xD8, 0xFF, 0xD9])

    private var captured: [BackendAdapterRequest] = []

    func execute(_ request: BackendAdapterRequest) async throws -> BackendAdapterResponse {
        captured.append(request)
        let payload: Data
        switch request.route {
        case "/v1/small-things/state":
            payload = try JSONSerialization.data(withJSONObject: [
                "binding": ["state": "bound", "partner": "partner"],
                "ledger": [
                    "limit_cents": 5_200,
                    "approved_cents": 1_200,
                    "pending_cents": 800,
                    "remaining_cents": 3_200,
                    "approved_ratio": 1_200.0 / 5_200.0
                ],
                "entries": [
                    [
                        "id": Self.entryID,
                        "created_at": "2026-08-06T00:00:00Z",
                        "type": "note",
                        "requester": "partner",
                        "title": "synthetic",
                        "body": "synthetic-body",
                        "image_metadata": ["media_id": Self.mediaID],
                        "comments": [
                            [
                                "id": Self.commentID,
                                "author": "partner",
                                "text": "synthetic-comment",
                                "replies": [
                                    [
                                        "id": Self.replyID,
                                        "author": "me",
                                        "reply_to_author": "partner",
                                        "text": "synthetic-reply"
                                    ]
                                ]
                            ]
                        ],
                        "reacted_by_me": true
                    ]
                ],
                "pending_approvals": [],
                "next_cursor": NSNull()
            ])
        case "/v1/small-things/media/upload":
            payload = try JSONSerialization.data(withJSONObject: [
                "media": ["media_id": Self.mediaID]
            ])
        case "/v1/small-things/ledger/limit":
            payload = try JSONSerialization.data(withJSONObject: [
                "ledger": [
                    "limit_cents": 12_345,
                    "approved_cents": 1_200,
                    "pending_cents": 800,
                    "remaining_cents": 10_345,
                    "approved_ratio": 1_200.0 / 12_345.0
                ]
            ])
        case "/v1/small-things/media/read":
            payload = try JSONSerialization.data(withJSONObject: [
                "data_base64": Self.mediaBytes.base64EncodedString()
            ])
        case "/v1/small-things/approvals/review":
            payload = try JSONSerialization.data(withJSONObject: [
                "undo_token": "synthetic-undo"
            ])
        case "/v1/small-things/binding/code/create":
            payload = try JSONSerialization.data(withJSONObject: ["code": "123456"])
        case "/v1/small-things/reactions/toggle":
            payload = try JSONSerialization.data(withJSONObject: [
                "entry_id": Self.entryID,
                "reacted_by_me": true
            ])
        case "/v1/small-things/comments/create":
            payload = try JSONSerialization.data(withJSONObject: [
                "comment": [
                    "id": Self.commentID,
                    "author": "me",
                    "text": "synthetic-comment",
                    "replies": []
                ]
            ])
        case "/v1/small-things/replies/create":
            payload = try JSONSerialization.data(withJSONObject: [
                "reply": [
                    "id": Self.replyID,
                    "entry_id": Self.entryID,
                    "comment_id": Self.commentID,
                    "author": "me",
                    "reply_to_author": "partner",
                    "text": "synthetic-reply"
                ]
            ])
        default:
            payload = try JSONSerialization.data(withJSONObject: [:])
        }
        return BackendAdapterResponse(statusCode: 200, payload: payload)
    }

    func snapshot() async -> BackendAdapterSnapshot {
        BackendAdapterSnapshot(
            mode: .production,
            invocationCount: captured.count,
            networkRequestCount: captured.count
        )
    }

    func routes() -> [String] { captured.map(\.route) }
    func requests() -> [BackendAdapterRequest] { captured }
}

private actor SmallThingsServiceSpy: SmallThingsServicing {
    private var loads = 0
    private var noteCreates = 0

    func loadState() async throws -> SmallThingsRemoteState {
        loads += 1
        let entries: [SmallThingEntry]
        if noteCreates == 0 {
            entries = []
        } else {
            entries = [SmallThingEntry(
                serverID: "authoritative-entry",
                type: .note,
                requester: .me,
                title: "synthetic",
                body: "authoritative"
            )]
        }
        return SmallThingsRemoteState(
            bindingState: .bound,
            ledgerLimit: 52,
            approvedAmount: 0,
            pendingAmount: 0,
            remainingAmount: 52,
            approvedRatio: 0,
            entries: entries
        )
    }

    func updateLedgerLimit(
        limitCents: Int,
        requestID: String
    ) async throws -> SmallThingsLedgerLimitResult {
        _ = requestID
        return SmallThingsLedgerLimitResult(ledgerLimit: Double(limitCents) / 100)
    }

    func createNote(
        title: String,
        body: String,
        imageData: Data?,
        requestID: String
    ) async throws {
        _ = title
        _ = body
        _ = imageData
        _ = requestID
        noteCreates += 1
    }

    func createExpense(
        purpose: String,
        amountCents: Int,
        note: String,
        requestID: String
    ) async throws {
        _ = purpose
        _ = amountCents
        _ = note
        _ = requestID
    }

    func deleteEntry(entryID: String, requestID: String) async throws {
        _ = entryID
        _ = requestID
    }

    func toggleReaction(entryID: String, requestID: String) async throws -> SmallThingsReactionResult {
        _ = requestID
        return SmallThingsReactionResult(entryID: entryID, reacted: true)
    }

    func createComment(entryID: String, text: String, requestID: String) async throws -> SmallThingsCommentResult {
        _ = requestID
        return SmallThingsCommentResult(
            entryID: entryID,
            comment: SmallThingComment(author: .me, text: text)
        )
    }

    func createReply(
        entryID: String,
        commentID: String,
        replyToID: String,
        text: String,
        requestID: String
    ) async throws -> SmallThingsReplyResult {
        _ = replyToID
        _ = requestID
        return SmallThingsReplyResult(
            entryID: entryID,
            commentID: commentID,
            reply: SmallThingReply(
                author: .me,
                text: text,
                replyToAuthor: .partner
            )
        )
    }

    func review(
        entryID: String,
        status: SmallThingExpenseStatus,
        message: String,
        requestID: String
    ) async throws -> SmallThingsReviewReceipt {
        _ = entryID
        _ = status
        _ = message
        return SmallThingsReviewReceipt(
            reviewRequestID: requestID,
            undoToken: "synthetic"
        )
    }

    func undo(_ receipt: SmallThingsReviewReceipt, requestID: String) async throws {
        _ = receipt
        _ = requestID
    }

    func createBindingCode(requestID: String) async throws -> String {
        _ = requestID
        return "123456"
    }

    func acceptBindingCode(_ code: String, requestID: String) async throws {
        _ = code
        _ = requestID
    }

    func unbind(requestID: String) async throws { _ = requestID }
    func loadMedia(mediaID: String) async throws -> Data {
        _ = mediaID
        return Data()
    }

    func createNoteCount() -> Int { noteCreates }
    func loadCount() -> Int { loads }
}
