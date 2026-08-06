import Foundation

enum SmallThingEntryType: String, Codable, CaseIterable, Hashable, Sendable {
    case note
    case expense
}

enum SmallThingExpenseStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case approved
    case rejected

    var displayName: String {
        switch self {
        case .pending: return "等我看"
        case .approved: return "已点头"
        case .rejected: return "再想想"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock.fill"
        case .approved: return "checkmark.circle.fill"
        case .rejected: return "arrow.uturn.backward.circle.fill"
        }
    }
}

enum SmallThingRequester: String, Codable, Hashable, Sendable {
    case me
    case partner

    var displayName: String {
        self == .me ? "我" : "对方"
    }
}

enum SmallThingBindingState: Equatable, Sendable {
    case unbound
    case bound
}

enum SmallThingBindingFeedback: Equatable, Sendable {
    case idle
    case success
    case invalidCode
    case occupied
    case alreadyBound

    var message: String? {
        switch self {
        case .idle: return nil
        case .success: return "绑定成功，双方现在可以一起记小事。"
        case .invalidCode: return "这个绑定码无效，请检查后再试。"
        case .occupied: return "这个绑定码已失效，请重新生成。"
        case .alreadyBound: return "当前已经处于绑定状态。"
        }
    }
}

struct SmallThingReply: Identifiable, Equatable, Sendable {
    let id: UUID
    let serverID: String?
    let author: SmallThingRequester
    let text: String
    let replyToAuthor: SmallThingRequester

    init(
        id: UUID = UUID(),
        serverID: String? = nil,
        author: SmallThingRequester,
        text: String,
        replyToAuthor: SmallThingRequester
    ) {
        self.id = id
        self.serverID = serverID
        self.author = author
        self.text = text
        self.replyToAuthor = replyToAuthor
    }
}

struct SmallThingComment: Identifiable, Equatable, Sendable {
    let id: UUID
    let serverID: String?
    let author: SmallThingRequester
    let text: String
    var replies: [SmallThingReply]

    init(
        id: UUID = UUID(),
        serverID: String? = nil,
        author: SmallThingRequester,
        text: String,
        replies: [SmallThingReply] = []
    ) {
        self.id = id
        self.serverID = serverID
        self.author = author
        self.text = text
        self.replies = replies
    }
}

struct SmallThingEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let serverID: String?
    let createdAt: Date
    let type: SmallThingEntryType
    let requester: SmallThingRequester
    var title: String
    var body: String
    var amount: Double
    var expenseStatus: SmallThingExpenseStatus?
    var approvalMessage: String
    var reacted: Bool
    var comments: [SmallThingComment]
    var imageData: Data?
    var imageMediaID: String?

    init(
        id: UUID = UUID(),
        serverID: String? = nil,
        createdAt: Date = Date(),
        type: SmallThingEntryType,
        requester: SmallThingRequester,
        title: String = "",
        body: String = "",
        amount: Double = 0,
        expenseStatus: SmallThingExpenseStatus? = nil,
        approvalMessage: String = "",
        reacted: Bool = false,
        comments: [SmallThingComment] = [],
        imageData: Data? = nil,
        imageMediaID: String? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.createdAt = createdAt
        self.type = type
        self.requester = requester
        self.title = title
        self.body = body
        self.amount = amount
        self.expenseStatus = expenseStatus
        self.approvalMessage = approvalMessage
        self.reacted = reacted
        self.comments = comments
        self.imageData = imageData
        self.imageMediaID = imageMediaID
    }

    var commentAndReplyCount: Int {
        comments.reduce(0) { $0 + 1 + $1.replies.count }
    }
}

struct SmallThingReplyTarget: Equatable, Sendable {
    let commentID: UUID
    let targetID: UUID
    let author: SmallThingRequester

    init(
        commentID: UUID,
        targetID: UUID? = nil,
        author: SmallThingRequester
    ) {
        self.commentID = commentID
        self.targetID = targetID ?? commentID
        self.author = author
    }
}

struct SmallThingApprovalUndo: Equatable, Sendable {
    let entryID: UUID
    let previousStatus: SmallThingExpenseStatus
    let previousMessage: String
}
