import Foundation
import SwiftUI
import UIKit

struct SmallThingsRemoteState: Equatable, Sendable {
    let bindingState: SmallThingBindingState
    let ledgerLimit: Double
    let approvedAmount: Double
    let pendingAmount: Double
    let remainingAmount: Double
    let approvedRatio: Double
    let entries: [SmallThingEntry]
}

struct SmallThingsReviewReceipt: Equatable, Sendable {
    let reviewRequestID: String
    let undoToken: String
}

struct SmallThingsReactionResult: Equatable, Sendable {
    let entryID: String
    let reacted: Bool
}

struct SmallThingsCommentResult: Equatable, Sendable {
    let entryID: String
    let comment: SmallThingComment
}

struct SmallThingsReplyResult: Equatable, Sendable {
    let entryID: String
    let commentID: String
    let reply: SmallThingReply
}

protocol SmallThingsServicing: Sendable {
    func loadState() async throws -> SmallThingsRemoteState
    func createNote(
        title: String,
        body: String,
        imageData: Data?,
        requestID: String
    ) async throws
    func createExpense(
        purpose: String,
        amountCents: Int,
        note: String,
        requestID: String
    ) async throws
    func toggleReaction(entryID: String, requestID: String) async throws -> SmallThingsReactionResult
    func createComment(entryID: String, text: String, requestID: String) async throws -> SmallThingsCommentResult
    func createReply(
        entryID: String,
        commentID: String,
        replyToID: String,
        text: String,
        requestID: String
    ) async throws -> SmallThingsReplyResult
    func review(
        entryID: String,
        status: SmallThingExpenseStatus,
        message: String,
        requestID: String
    ) async throws -> SmallThingsReviewReceipt
    func undo(_ receipt: SmallThingsReviewReceipt, requestID: String) async throws
    func createBindingCode(requestID: String) async throws -> String
    func acceptBindingCode(_ code: String, requestID: String) async throws
    func unbind(requestID: String) async throws
    func loadMedia(mediaID: String) async throws -> Data
}

actor ProductionSmallThingsService: SmallThingsServicing {
    private struct StateResponse: Decodable {
        let binding: BindingDTO
        let ledger: LedgerDTO
        let entries: [EntryDTO]
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case binding
            case ledger
            case entries
            case nextCursor = "next_cursor"
        }
    }

    private struct BindingDTO: Decodable {
        let state: String
    }

    private struct LedgerDTO: Decodable {
        let limitCents: Int
        let approvedCents: Int
        let pendingCents: Int
        let remainingCents: Int
        let approvedRatio: Double

        enum CodingKeys: String, CodingKey {
            case limitCents = "limit_cents"
            case approvedCents = "approved_cents"
            case pendingCents = "pending_cents"
            case remainingCents = "remaining_cents"
            case approvedRatio = "approved_ratio"
        }
    }

    private struct EntryDTO: Decodable {
        let id: String
        let createdAt: String
        let type: SmallThingEntryType
        let requester: SmallThingRequester
        let reviewer: SmallThingRequester?
        let title: String
        let body: String
        let imageMetadata: ImageMetadataDTO?
        let amountCents: Int?
        let expenseStatus: SmallThingExpenseStatus?
        let approvalMessage: String?
        let comments: [CommentDTO]
        let reactedByMe: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case createdAt = "created_at"
            case type
            case requester
            case reviewer
            case title
            case body
            case imageMetadata = "image_metadata"
            case amountCents = "amount_cents"
            case expenseStatus = "expense_status"
            case approvalMessage = "approval_message"
            case comments
            case reactedByMe = "reacted_by_me"
        }
    }

    private struct ImageMetadataDTO: Decodable {
        let mediaID: String

        enum CodingKeys: String, CodingKey {
            case mediaID = "media_id"
        }
    }

    private struct CommentDTO: Decodable {
        let id: String
        let author: SmallThingRequester
        let text: String
        let replies: [ReplyDTO]
    }

    private struct ReplyDTO: Decodable {
        let id: String
        let author: SmallThingRequester
        let replyToAuthor: SmallThingRequester
        let text: String

        enum CodingKeys: String, CodingKey {
            case id
            case author
            case replyToAuthor = "reply_to_author"
            case text
        }
    }

    private struct MediaUploadResponse: Decodable {
        let media: ImageMetadataDTO
    }

    private struct MediaReadResponse: Decodable {
        let dataBase64: String

        enum CodingKeys: String, CodingKey {
            case dataBase64 = "data_base64"
        }
    }

    private struct ReviewResponse: Decodable {
        let undoToken: String

        enum CodingKeys: String, CodingKey {
            case undoToken = "undo_token"
        }
    }

    private struct ReactionResponse: Decodable {
        let entryID: String
        let reactedByMe: Bool

        enum CodingKeys: String, CodingKey {
            case entryID = "entry_id"
            case reactedByMe = "reacted_by_me"
        }
    }

    private struct CommentResponse: Decodable {
        let comment: CommentDTO
    }

    private struct ReplyResponse: Decodable {
        let reply: ReplyEnvelopeDTO
    }

    private struct ReplyEnvelopeDTO: Decodable {
        let id: String
        let entryID: String
        let commentID: String
        let author: SmallThingRequester
        let replyToAuthor: SmallThingRequester
        let text: String

        enum CodingKeys: String, CodingKey {
            case id
            case entryID = "entry_id"
            case commentID = "comment_id"
            case author
            case replyToAuthor = "reply_to_author"
            case text
        }
    }

    private struct BindingCodeResponse: Decodable {
        let code: String
    }

    private struct EmptyResponse: Decodable {}

    private let backend: any BackendAdapter
    private let decoder = JSONDecoder()

    init(backend: any BackendAdapter) {
        self.backend = backend
    }

    func loadState() async throws -> SmallThingsRemoteState {
        var cursor: String?
        var allEntries: [EntryDTO] = []
        var first: StateResponse?
        repeat {
            let response: StateResponse = try await execute(
                route: "/v1/small-things/state",
                body: [
                    "limit": 100,
                    "cursor": cursor.map { $0 as Any } ?? NSNull()
                ]
            )
            if first == nil { first = response }
            allEntries.append(contentsOf: response.entries)
            cursor = response.nextCursor
        } while cursor != nil

        guard let state = first else {
            throw AppError.protocolError("invalid_small_things_state")
        }
        return SmallThingsRemoteState(
            bindingState: state.binding.state == "bound" ? .bound : .unbound,
            ledgerLimit: Double(state.ledger.limitCents) / 100,
            approvedAmount: Double(state.ledger.approvedCents) / 100,
            pendingAmount: Double(state.ledger.pendingCents) / 100,
            remainingAmount: Double(state.ledger.remainingCents) / 100,
            approvedRatio: state.ledger.approvedRatio,
            entries: try allEntries.map(Self.entry(from:))
        )
    }

    func createNote(
        title: String,
        body: String,
        imageData: Data?,
        requestID: String
    ) async throws {
        let mediaID: String?
        if let imageData {
            let sanitized = try await MainActor.run {
                try SmallThingsImageSanitizer.sanitize(imageData)
            }
            let response: MediaUploadResponse = try await execute(
                route: "/v1/small-things/media/upload",
                body: [
                    "request_id": requestID + "-media",
                    "mime_type": "image/jpeg",
                    "data_base64": sanitized.base64EncodedString()
                ]
            )
            mediaID = response.media.mediaID
        } else {
            mediaID = nil
        }
        let _: EmptyResponse = try await execute(
            route: "/v1/small-things/entries/create",
            body: [
                "request_id": requestID,
                "type": "note",
                "title": title,
                "body": body,
                "image_metadata": mediaID.map {
                    ["media_id": $0] as Any
                } ?? NSNull()
            ]
        )
    }

    func createExpense(
        purpose: String,
        amountCents: Int,
        note: String,
        requestID: String
    ) async throws {
        let _: EmptyResponse = try await execute(
            route: "/v1/small-things/entries/create",
            body: [
                "request_id": requestID,
                "type": "expense",
                "title": purpose,
                "body": note,
                "image_metadata": NSNull(),
                "amount_cents": amountCents
            ]
        )
    }

    func toggleReaction(entryID: String, requestID: String) async throws -> SmallThingsReactionResult {
        let response: ReactionResponse = try await execute(
            route: "/v1/small-things/reactions/toggle",
            body: ["request_id": requestID, "entry_id": entryID]
        )
        return SmallThingsReactionResult(
            entryID: response.entryID,
            reacted: response.reactedByMe
        )
    }

    func createComment(entryID: String, text: String, requestID: String) async throws -> SmallThingsCommentResult {
        let response: CommentResponse = try await execute(
            route: "/v1/small-things/comments/create",
            body: ["request_id": requestID, "entry_id": entryID, "text": text]
        )
        return SmallThingsCommentResult(
            entryID: entryID,
            comment: Self.comment(from: response.comment)
        )
    }

    func createReply(
        entryID: String,
        commentID: String,
        replyToID: String,
        text: String,
        requestID: String
    ) async throws -> SmallThingsReplyResult {
        let response: ReplyResponse = try await execute(
            route: "/v1/small-things/replies/create",
            body: [
                "request_id": requestID,
                "entry_id": entryID,
                "comment_id": commentID,
                "reply_to_id": replyToID,
                "text": text
            ]
        )
        return SmallThingsReplyResult(
            entryID: response.reply.entryID,
            commentID: response.reply.commentID,
            reply: SmallThingReply(
                id: Self.stableUUID(from: response.reply.id),
                serverID: response.reply.id,
                author: response.reply.author,
                text: response.reply.text,
                replyToAuthor: response.reply.replyToAuthor
            )
        )
    }

    func review(
        entryID: String,
        status: SmallThingExpenseStatus,
        message: String,
        requestID: String
    ) async throws -> SmallThingsReviewReceipt {
        let response: ReviewResponse = try await execute(
            route: "/v1/small-things/approvals/review",
            body: [
                "request_id": requestID,
                "entry_id": entryID,
                "decision": status.rawValue,
                "message": message
            ]
        )
        return SmallThingsReviewReceipt(
            reviewRequestID: requestID,
            undoToken: response.undoToken
        )
    }

    func undo(_ receipt: SmallThingsReviewReceipt, requestID: String) async throws {
        try await write(
            route: "/v1/small-things/approvals/undo",
            body: [
                "request_id": requestID,
                "review_request_id": receipt.reviewRequestID,
                "undo_token": receipt.undoToken
            ]
        )
    }

    func createBindingCode(requestID: String) async throws -> String {
        let response: BindingCodeResponse = try await execute(
            route: "/v1/small-things/binding/code/create",
            body: ["request_id": requestID]
        )
        return response.code
    }

    func acceptBindingCode(_ code: String, requestID: String) async throws {
        try await write(
            route: "/v1/small-things/binding/code/accept",
            body: ["request_id": requestID, "code": code]
        )
    }

    func unbind(requestID: String) async throws {
        try await write(
            route: "/v1/small-things/binding/unbind",
            body: ["request_id": requestID]
        )
    }

    func loadMedia(mediaID: String) async throws -> Data {
        let response: MediaReadResponse = try await execute(
            route: "/v1/small-things/media/read",
            body: ["media_id": mediaID]
        )
        guard let data = Data(base64Encoded: response.dataBase64),
              data.count <= 2_000_000 else {
            throw AppError.protocolError("invalid_media_response")
        }
        return data
    }

    private func write(route: String, body: [String: Any]) async throws {
        let _: EmptyResponse = try await execute(route: route, body: body)
    }

    private func execute<Response: Decodable>(
        route: String,
        body: [String: Any]
    ) async throws -> Response {
        guard JSONSerialization.isValidJSONObject(body),
              let payload = try? JSONSerialization.data(withJSONObject: body) else {
            throw AppError.protocolError("invalid_request")
        }
        let response = try await backend.execute(
            BackendAdapterRequest(route: route, payload: payload)
        )
        guard 200..<300 ~= response.statusCode else {
            throw AppError.server("http_\(response.statusCode)")
        }
        do {
            return try decoder.decode(Response.self, from: response.payload)
        } catch {
            throw AppError.protocolError("invalid_small_things_response")
        }
    }

    private static func entry(from dto: EntryDTO) throws -> SmallThingEntry {
        guard let createdAt = date(from: dto.createdAt) else {
            throw AppError.protocolError("invalid_created_at")
        }
        return SmallThingEntry(
            id: stableUUID(from: dto.id),
            serverID: dto.id,
            createdAt: createdAt,
            type: dto.type,
            requester: dto.requester,
            reviewer: dto.reviewer,
            title: dto.title,
            body: dto.body,
            amount: Double(dto.amountCents ?? 0) / 100,
            expenseStatus: dto.expenseStatus,
            approvalMessage: dto.approvalMessage ?? "",
            reacted: dto.reactedByMe,
            comments: dto.comments.map(comment(from:)),
            imageMediaID: dto.imageMetadata?.mediaID
        )
    }

    private static func comment(from dto: CommentDTO) -> SmallThingComment {
        SmallThingComment(
            id: stableUUID(from: dto.id),
            serverID: dto.id,
            author: dto.author,
            text: dto.text,
            replies: dto.replies.map { reply in
                SmallThingReply(
                    id: stableUUID(from: reply.id),
                    serverID: reply.id,
                    author: reply.author,
                    text: reply.text,
                    replyToAuthor: reply.replyToAuthor
                )
            }
        )
    }

    private static func stableUUID(from rawValue: String) -> UUID {
        let compact = rawValue.replacingOccurrences(of: "-", with: "")
        if compact.count == 32 {
            let chars = Array(compact)
            let formatted = [
                String(chars[0..<8]),
                String(chars[8..<12]),
                String(chars[12..<16]),
                String(chars[16..<20]),
                String(chars[20..<32])
            ].joined(separator: "-")
            if let value = UUID(uuidString: formatted) { return value }
        }
        return UUID(uuidString: rawValue) ?? UUID()
    }

    private static func date(from rawValue: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: rawValue) ?? ISO8601DateFormatter().date(from: rawValue)
    }
}

@MainActor
enum SmallThingsImageSanitizer {
    static func sanitize(_ source: Data) throws -> Data {
        guard source.count <= 12_000_000,
              let image = UIImage(data: source) else {
            throw AppError.protocolError("invalid_image")
        }
        let maximumDimension: CGFloat = 2_048
        let scale = min(
            1,
            maximumDimension / max(image.size.width, image.size.height)
        )
        let size = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.82, 0.68, 0.54, 0.40] {
            if let data = rendered.jpegData(compressionQuality: quality),
               data.count <= 1_900_000 {
                return data
            }
        }
        throw AppError.protocolError("image_too_large")
    }
}
