import Foundation

public enum DVKCompanionMode: String, CaseIterable, Codable, Sendable {
    case voice
    case text
}

public enum DVKCompanionMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

public enum DVKCompanionDeliveryState: String, Codable, Sendable {
    case pending
    case sent
    case failed
}

public struct DVKCompanionMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let role: DVKCompanionMessageRole
    public let text: String
    public var deliveryState: DVKCompanionDeliveryState
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        role: DVKCompanionMessageRole,
        text: String,
        deliveryState: DVKCompanionDeliveryState,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.deliveryState = deliveryState
        self.createdAt = createdAt
    }
}

public enum DVKCompanionPrivacyState: String, CaseIterable, Codable, Sendable {
    case allowed
    case limited
}

public struct DVKCompanionPrivacyConfiguration: Codable, Equatable, Sendable {
    public let allowsTextWhilePrivacyLimited: Bool
    public init(allowsTextWhilePrivacyLimited: Bool = false) {
        self.allowsTextWhilePrivacyLimited = allowsTextWhilePrivacyLimited
    }
    public static let showcase = DVKCompanionPrivacyConfiguration(allowsTextWhilePrivacyLimited: true)
}

public enum DVKCompanionInitializationState: String, Codable, Sendable {
    case initializing
    case ready
}

public enum DVKCompanionEasterEgg: String, CaseIterable, Codable, Sendable {
    case care
    case localFun
    case help
    case privacy
    case about

    public var title: String {
        switch self {
        case .care: return "Care"
        case .localFun: return "Local fun"
        case .help: return "How it works"
        case .privacy: return "Privacy"
        case .about: return "About this showcase"
        }
    }

    public var detail: String {
        switch self {
        case .care: return "A small local moment of care, with no account or network."
        case .localFun: return "The showcase is deterministic so every demo can be inspected."
        case .help: return "Text and voice are mock flows over the same local state store."
        case .privacy: return "Limited privacy keeps browsing and configured text demos available while voice actions stay blocked."
        case .about: return "DuplexVoiceKit Companion is a public, provider-neutral demo layer."
        }
    }
}

public enum DVKCompanionVoiceState: String, CaseIterable, Codable, Sendable {
    case idle
    case connecting
    case listening
    case processing
    case speaking
    case ended

    public var next: DVKCompanionVoiceState? {
        switch self {
        case .idle: return .connecting
        case .connecting: return .listening
        case .listening: return .processing
        case .processing: return .speaking
        case .speaking: return .ended
        case .ended: return nil
        }
    }
}

public enum DVKCompanionChatError: Error, Equatable, Sendable {
    case plannedFailure
}

public protocol DVKChatServicing: Sendable {
    func send(text: String) async throws -> String
}

public actor DVKMockChatService: DVKChatServicing {
    private var failNext = false
    private var sentTexts: [String] = []

    public init() {}

    public func planNextFailure() {
        failNext = true
    }

    public func sentTextCount() -> Int {
        sentTexts.count
    }

    public func send(text: String) async throws -> String {
        sentTexts.append(text)
        if failNext {
            failNext = false
            throw DVKCompanionChatError.plannedFailure
        }
        return "Mock reply: \(text)"
    }
}

public enum DVKReviewGenerating: String, Codable, Sendable {
    case idle
    case generating
}

public struct DVKCompanionReview: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sessionKey: String
    public let title: String
    public let startedAt: Date
    public let endedAt: Date
    public let duration: TimeInterval
    public let summary: String

    public init(
        id: String = UUID().uuidString,
        sessionKey: String,
        title: String,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        summary: String
    ) {
        self.id = id
        self.sessionKey = sessionKey
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.summary = summary
    }
}

public actor DVKMockReviewGenerator {
    private var generatedSessionKeys: Set<String> = []

    public init() {}

    public func generate(sessionKey: String, startedAt: Date, endedAt: Date) -> DVKCompanionReview? {
        guard generatedSessionKeys.insert(sessionKey).inserted else { return nil }
        return DVKCompanionReview(
            sessionKey: sessionKey,
            title: "Mock voice review",
            startedAt: startedAt,
            endedAt: endedAt,
            duration: max(0, endedAt.timeIntervalSince(startedAt)),
            summary: "A local showcase session completed with deterministic mock states."
        )
    }
}
