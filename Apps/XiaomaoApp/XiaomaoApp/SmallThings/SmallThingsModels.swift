import Foundation

enum SmallThingEntryType: String, Codable, CaseIterable {
    case note
    case expense
}

enum SmallThingExpenseStatus: String, Codable {
    case pending
    case approved
    case rejected
}

enum SmallThingRequester: String, Codable {
    case me
    case partner
}

struct SmallThingReply: Identifiable, Equatable {
    let id: UUID
    let author: SmallThingRequester
    let text: String
    let replyToAuthor: SmallThingRequester

    init(id: UUID = UUID(), author: SmallThingRequester, text: String, replyToAuthor: SmallThingRequester) {
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

    init(id: UUID = UUID(), author: SmallThingRequester, text: String, replies: [SmallThingReply] = []) {
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
}

struct SmallThingApprovalUndo: Equatable {
    let entryID: UUID
    let previousStatus: SmallThingExpenseStatus
    let previousMessage: String
}
