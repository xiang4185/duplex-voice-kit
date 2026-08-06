import Foundation

enum ChatParticipant: String, Codable, CaseIterable, Equatable, Sendable {
    case user
    case developer
    case xiaomao

    var displayName: String {
        switch self {
        case .user: "你"
        case .developer: "开发者"
        case .xiaomao: "小猫"
        }
    }
}

enum ChatMessageStatus: String, Codable, Equatable, Sendable {
    case pending
    case sending
    case completed
    case failed
    case skipped
}

enum XiaomaoParticipationMode: String, Codable, CaseIterable, Hashable, Sendable {
    case off
    case auto
    case always

    var title: String {
        switch self {
        case .off: "小猫关闭"
        case .auto: "提到小猫时参与"
        case .always: "小猫每轮参与"
        }
    }

    var footerTitle: String {
        switch self {
        case .off: "小猫当前安静旁听"
        case .auto: "提到小猫时，她会加入对话"
        case .always: "小猫会在每一轮接话"
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
    }

    let id: String
    let role: Role
    let participant: ChatParticipant
    let turnID: String
    let status: ChatMessageStatus
    let content: String
    let createdAt: Date

    init(
        id: String,
        role: Role,
        content: String,
        createdAt: Date,
        participant: ChatParticipant? = nil,
        turnID: String? = nil,
        status: ChatMessageStatus = .completed
    ) {
        self.id = id
        self.role = role
        self.participant = participant ?? (role == .user ? .user : .developer)
        self.turnID = turnID ?? id
        self.status = status
        self.content = content
        self.createdAt = createdAt
    }

    var isUser: Bool { participant == .user }
}

struct ChatParticipantResult: Codable, Equatable, Sendable {
    let participant: ChatParticipant
    let turnID: String
    let status: ChatMessageStatus
    let retryable: Bool
    let message: ChatMessage?
}
