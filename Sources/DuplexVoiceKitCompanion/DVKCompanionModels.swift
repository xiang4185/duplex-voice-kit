import Foundation

public enum DVKCompanionMode: String, CaseIterable, Codable, Sendable { case voice, text }
public enum DVKCompanionMessageRole: String, Codable, Sendable { case user, assistant }
public enum DVKCompanionDeliveryState: String, Codable, Sendable { case pending, sent, failed }

public struct DVKCompanionMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let role: DVKCompanionMessageRole
    public var text: String
    public var deliveryState: DVKCompanionDeliveryState
    public let createdAt: Date
    public init(id: UUID = UUID(), role: DVKCompanionMessageRole, text: String, deliveryState: DVKCompanionDeliveryState, createdAt: Date = Date()) { self.id=id; self.role=role; self.text=text; self.deliveryState=deliveryState; self.createdAt=createdAt }
}
public enum DVKCompanionPrivacyState: String, CaseIterable, Codable, Sendable { case allowed, limited }
public enum DVKCompanionEasterEgg: String, CaseIterable, Codable, Sendable { case care, localFun, help, privacy, about }
public enum DVKReviewGenerating: String, Codable, Sendable { case idle, generating }
public struct DVKCompanionReview: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID; public let sessionKey: String; public let title: String; public let startedAt: Date; public let endedAt: Date; public let duration: TimeInterval; public let summary: String
    public init(id: UUID = UUID(), sessionKey: String, title: String, startedAt: Date, endedAt: Date, duration: TimeInterval, summary: String) { self.id=id; self.sessionKey=sessionKey; self.title=title; self.startedAt=startedAt; self.endedAt=endedAt; self.duration=duration; self.summary=summary }
}
public protocol DVKChatServicing: Sendable { func send(_ text: String) async throws -> String }
public enum DVKMockChatError: Error, Equatable, Sendable { case plannedFailure }
public actor DVKMockChatService: DVKChatServicing {
    private var shouldFailNext=false
    public init() {}
    public func failNextSend(){shouldFailNext=true}
    public func send(_ text:String) async throws -> String { if shouldFailNext { shouldFailNext=false; throw DVKMockChatError.plannedFailure }; return "Mock reply: \(text.trimmingCharacters(in: .whitespacesAndNewlines))" }
}
public actor DVKMockReviewGenerator {
    private var keys:Set<String>=[]
    public init() {}
    public func generate(sessionKey:String, startedAt:Date, endedAt:Date)->DVKCompanionReview? { guard keys.insert(sessionKey).inserted else{return nil}; return DVKCompanionReview(sessionKey:sessionKey,title:"Mock voice review",startedAt:startedAt,endedAt:endedAt,duration:max(0,endedAt.timeIntervalSince(startedAt)),summary:"A local showcase session was completed.") }
}
