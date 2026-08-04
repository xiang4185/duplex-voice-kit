import Foundation

enum SmallThingEntryType: String, Codable, CaseIterable, Hashable {
    case note
    case expense
}

enum SmallThingExpenseStatus: String, Codable, CaseIterable, Hashable {
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

enum SmallThingRequester: String, Codable, Hashable {
    case me
    case partner

    var displayName: String {
        self == .me ? "我" : "图图"
    }
}

enum SmallThingBindingState: Equatable {
    case unbound
    case bound
}

enum SmallThingBindingFeedback: Equatable {
    case idle
    case success
    case invalidCode
    case occupied
    case alreadyBound

    var message: String? {
        switch self {
        case .idle: return nil
        case .success: return "演示绑定成功，双方现在可以一起记小事。"
        case .invalidCode: return "这个演示码无效，请检查后再试。"
        case .occupied: return "这个位置已被占用，请换一个演示码。"
        case .alreadyBound: return "当前已经处于演示绑定状态。"
        }
    }
}

struct SmallThingReply: Identifiable, Equatable {
    let id: UUID
    let author: SmallThingRequester
    let text: String
    let replyToAuthor: SmallThingRequester

    init(
        id: UUID = UUID(),
        author: SmallThingRequester,
        text: String,
        replyToAuthor: SmallThingRequester
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.replyToAuthor = replyToAuthor
    }
}

struct SmallThingComment: Identifiable, Equatable {
    let id: UUID
    let author: SmallThingRequester
    let text: String
    var replies: [SmallThingReply]

    init(
        id: UUID = UUID(),
        author: SmallThingRequester,
        text: String,
        replies: [SmallThingReply] = []
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.replies = replies
    }
}

struct SmallThingEntry: Identifiable, Equatable {
    let id: UUID
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

    init(
        id: UUID = UUID(),
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
        imageData: Data? = nil
    ) {
        self.id = id
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
    }

    var commentAndReplyCount: Int {
        comments.reduce(0) { $0 + 1 + $1.replies.count }
    }
}

struct SmallThingReplyTarget: Equatable {
    let commentID: UUID
    let author: SmallThingRequester
}

struct SmallThingApprovalUndo: Equatable {
    let entryID: UUID
    let previousStatus: SmallThingExpenseStatus
    let previousMessage: String
}
