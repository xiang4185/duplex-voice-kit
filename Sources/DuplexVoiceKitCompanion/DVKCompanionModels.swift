import Foundation

public enum DVKCompanionMode: String, CaseIterable, Codable, Sendable { case voice, text }
public enum DVKCompanionMessageRole: String, Codable, Sendable { case user, assistant }
public enum DVKCompanionDeliveryState: String, Codable, Sendable { case pending, sent, failed }
public enum DVKCompanionPrivacyState: String, CaseIterable, Codable, Sendable { case allowed, limited }
public enum DVKCompanionInitializationState: String, Codable, Sendable { case initializing, ready }
public enum DVKCompanionEasterEgg: String, CaseIterable, Codable, Sendable {
    case care, localFun, help, privacy, about
    public var title: String { switch self { case .care:return "Care"; case .localFun:return "Local fun"; case .help:return "How it works"; case .privacy:return "Privacy"; case .about:return "About this showcase" } }
    public var detail: String { switch self { case .care:return "A small local moment of care, with no account or network."; case .localFun:return "The showcase is deterministic so every demo can be inspected."; case .help:return "Text and voice are mock flows over the same local state store."; case .privacy:return "Limited privacy keeps browsing and configured text demos available while voice actions stay blocked."; case .about:return "DuplexVoiceKit Companion is a public, provider-neutral demo layer." } }
}
public enum DVKCompanionProfileAvailability: String, Codable, Sendable { case available, unavailable, loading }
public enum DVKCompanionCapability: String, CaseIterable, Codable, Sendable { case text, voice, review }
public enum DVKCompanionProfileRouteState: String, Codable, Sendable { case idle, resolving, resolved, failed }
public enum DVKCompanionProfileThemeKey: String, Codable, Sendable { case warmCreamRose, coralGold, mistBlue, lavenderNight }
public enum DVKCompanionProfileRoutingError: Error, Equatable, Sendable { case unavailable, resolutionFailed, unknownProfile }
public enum DVKCompanionMockScenario: String, CaseIterable, Codable, Sendable {
    case normalText, slowText, nextTextFailure, routeFailure, profileUnavailable
    case voiceConnectionFailure, voiceInterruption, reviewGenerationFailure
    case limitedPrivacy, multipleReviews, emptyReviews
}
public enum DVKCompanionAppearance: String, CaseIterable, Codable, Sendable { case followProfile, light, dark }
public enum DVKCompanionPresentationMode: String, CaseIterable, Codable, Sendable { case programmatic, staticFallback }
public enum DVKCompanionCharacterPresentationState: Equatable, Sendable {
    case idle, listening, thinking, speaking(amplitude: Float), celebrating, unavailable, error
}

public struct DVKCompanionPrivacyConfiguration: Codable, Equatable, Sendable {
    public let allowsTextWhilePrivacyLimited: Bool
    public init(allowsTextWhilePrivacyLimited: Bool = false) { self.allowsTextWhilePrivacyLimited = allowsTextWhilePrivacyLimited }
    public static let showcase = DVKCompanionPrivacyConfiguration(allowsTextWhilePrivacyLimited: true)
}

public struct DVKCompanionProfileSnapshot: Codable, Equatable, Sendable {
    public let publicID: String
    public let displayName: String
    public let summary: String
    public let greeting: String
    public let tags: [String]
    public let visualKey: String
    public let themeKey: DVKCompanionProfileThemeKey
    public let capabilities: [DVKCompanionCapability]
    public let availability: DVKCompanionProfileAvailability
    public let accessibilityDescription: String
    public init(publicID: String, displayName: String, summary: String, greeting: String, tags: [String], visualKey: String, themeKey: DVKCompanionProfileThemeKey, capabilities: [DVKCompanionCapability], availability: DVKCompanionProfileAvailability, accessibilityDescription: String) {
        self.publicID = publicID; self.displayName = displayName; self.summary = summary; self.greeting = greeting; self.tags = tags; self.visualKey = visualKey; self.themeKey = themeKey; self.capabilities = capabilities; self.availability = availability; self.accessibilityDescription = accessibilityDescription
    }
}

public struct DVKCompanionProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let shortSummary: String
    public let greeting: String
    public let personalityTags: [String]
    public let characterVisualKey: String
    public let themeKey: DVKCompanionProfileThemeKey
    public let capabilities: [DVKCompanionCapability]
    public let availability: DVKCompanionProfileAvailability
    public let accessibilityDescription: String
    public init(id: String, displayName: String, shortSummary: String, greeting: String, personalityTags: [String], characterVisualKey: String, themeKey: DVKCompanionProfileThemeKey, capabilities: [DVKCompanionCapability], availability: DVKCompanionProfileAvailability = .available, accessibilityDescription: String) {
        self.id=id; self.displayName=displayName; self.shortSummary=shortSummary; self.greeting=greeting; self.personalityTags=personalityTags; self.characterVisualKey=characterVisualKey; self.themeKey=themeKey; self.capabilities=capabilities; self.availability=availability; self.accessibilityDescription=accessibilityDescription
    }
    public var snapshot: DVKCompanionProfileSnapshot { DVKCompanionProfileSnapshot(publicID:id, displayName:displayName, summary:shortSummary, greeting:greeting, tags:personalityTags, visualKey:characterVisualKey, themeKey:themeKey, capabilities:capabilities, availability:availability, accessibilityDescription:accessibilityDescription) }
    public func supports(_ capability: DVKCompanionCapability) -> Bool { capabilities.contains(capability) }
}

public struct DVKCompanionProfileCatalog: Sendable {
    public let profiles: [DVKCompanionProfile]
    public init(profiles: [DVKCompanionProfile] = DVKCompanionProfileCatalog.defaultProfiles) { self.profiles = profiles }
    public func profile(id: String) -> DVKCompanionProfile? { profiles.first { $0.id == id } }
    public static let defaultProfiles: [DVKCompanionProfile] = [
        DVKCompanionProfile(id:"mock.gentle-cat", displayName:"Mellow", shortSummary:"A soft pause for ordinary days.", greeting:"Take your time. I’m here with you.", personalityTags:["gentle","steady","warm"], characterVisualKey:"cream-rose", themeKey:.warmCreamRose, capabilities:[.text,.voice,.review], accessibilityDescription:"Mellow, a cream colored mock cat with rose ears. Gentle, steady, and warm."),
        DVKCompanionProfile(id:"mock.cheerful-cat", displayName:"Sunny", shortSummary:"A bright nudge when you need momentum.", greeting:"Let’s find one small bright thing.", personalityTags:["cheerful","curious","uplifting"], characterVisualKey:"coral-gold", themeKey:.coralGold, capabilities:[.text,.voice,.review], accessibilityDescription:"Sunny, a coral colored mock cat with golden markings. Cheerful, curious, and uplifting."),
        DVKCompanionProfile(id:"mock.thoughtful-cat", displayName:"Sage", shortSummary:"A calm space to sort the tangled bits.", greeting:"We can look at this one piece at a time.", personalityTags:["thoughtful","clear","patient"], characterVisualKey:"silver-mist", themeKey:.mistBlue, capabilities:[.text,.voice,.review], accessibilityDescription:"Sage, a silver mock cat with mist blue details. Thoughtful, clear, and patient."),
        DVKCompanionProfile(id:"mock.story-cat", displayName:"Luna", shortSummary:"A little doorway into story and wonder.", greeting:"Tell me where the story starts.", personalityTags:["imaginative","playful","dreamy"], characterVisualKey:"lavender-night", themeKey:.lavenderNight, capabilities:[.text,.voice,.review], accessibilityDescription:"Luna, a lavender mock cat with night sky details. Imaginative, playful, and dreamy.")
    ]
}

public protocol DVKCompanionProfileRouteResolving: Sendable {
    func resolve(publicProfileID: String) async throws -> DVKCompanionRouteToken
}
public struct DVKCompanionRouteToken: Equatable, Sendable {
    public let value: String
    public init(opaqueValue: String) { self.value = opaqueValue }
}
public struct DVKCompanionSessionContext: Equatable, Sendable {
    public let profile: DVKCompanionProfileSnapshot
    public let routeToken: DVKCompanionRouteToken
    public init(profile: DVKCompanionProfileSnapshot, routeToken: DVKCompanionRouteToken) { self.profile=profile; self.routeToken=routeToken }
}
public protocol DVKVoiceServicing: Sendable {
    func connect(context: DVKCompanionSessionContext) async throws
}
public protocol DVKCompanionAsyncGate: Sendable {
    func wait() async
}
public actor DVKDeterministicSlowGate: DVKCompanionAsyncGate {
    public init() {}
    public func wait() async {
        for _ in 0..<8 {
            if Task.isCancelled { return }
            await Task.yield()
        }
    }
}
public actor DVKMockProfileRouteResolver: DVKCompanionProfileRouteResolving {
    private var shouldFail = false
    public init() {}
    public func setFailure(_ value: Bool) { shouldFail=value }
    public func resolve(publicProfileID: String) throws -> DVKCompanionRouteToken {
        if shouldFail { throw DVKCompanionProfileRoutingError.resolutionFailed }
        return DVKCompanionRouteToken(opaqueValue: "mock-route-\(publicProfileID)")
    }
}
public actor DVKMockVoiceService: DVKVoiceServicing {
    public init() {}
    public func connect(context: DVKCompanionSessionContext) async throws {}
}

public protocol DVKCompanionProfilePersistence: Sendable {
    func loadProfileID() -> String?
    func saveProfileID(_ id: String)
}
public final class DVKInMemoryProfilePersistence: DVKCompanionProfilePersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    public init(profileID: String? = nil) { value=profileID }
    public func loadProfileID() -> String? { lock.lock(); defer { lock.unlock() }; return value }
    public func saveProfileID(_ id: String) { lock.lock(); value=id; lock.unlock() }
}

public struct DVKCompanionMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let role: DVKCompanionMessageRole
    public let text: String
    public var deliveryState: DVKCompanionDeliveryState
    public let createdAt: Date
    public let profileSnapshot: DVKCompanionProfileSnapshot?
    public init(id: String = UUID().uuidString, role: DVKCompanionMessageRole, text: String, deliveryState: DVKCompanionDeliveryState, createdAt: Date = Date(), profileSnapshot: DVKCompanionProfileSnapshot? = nil) {
        self.id=id; self.role=role; self.text=text; self.deliveryState=deliveryState; self.createdAt=createdAt; self.profileSnapshot=profileSnapshot
    }
}

public enum DVKCompanionVoiceState: String, CaseIterable, Codable, Sendable { case idle, connecting, listening, processing, speaking, ended
    public var next: DVKCompanionVoiceState? { switch self { case .idle:return .connecting; case .connecting:return .listening; case .listening:return .processing; case .processing:return .speaking; case .speaking:return .ended; case .ended:return nil } }
}
public enum DVKCompanionChatError: Error, Equatable, Sendable { case plannedFailure, routeFailure, connectionFailure, interrupted }
public protocol DVKChatServicing: Sendable {
    func send(text: String) async throws -> String
    func send(text: String, context: DVKCompanionSessionContext) async throws -> String
}
public extension DVKChatServicing {
    func send(text: String, context: DVKCompanionSessionContext) async throws -> String { try await send(text: text) }
}
public actor DVKMockChatService: DVKChatServicing {
    private var failNext=false; private var sentTexts:[String]=[]; private var contexts:[DVKCompanionSessionContext]=[]; private var slow=false
    public init() {}
    public func planNextFailure() { failNext=true }
    public func setSlow(_ value: Bool) { slow=value }
    public func sentTextCount() -> Int { sentTexts.count }
    public func sentContexts() -> [DVKCompanionSessionContext] { contexts }
    public func send(text: String) async throws -> String { sentTexts.append(text); if failNext { failNext=false; throw DVKCompanionChatError.plannedFailure }; return "Mock reply: \(text)" }
    public func send(text: String, context: DVKCompanionSessionContext) async throws -> String { contexts.append(context); if slow { await Task.yield() }; return try await send(text:text) }
}

public enum DVKReviewGenerating: String, Codable, Sendable { case idle, generating, failed }
public struct DVKCompanionReview: Identifiable, Codable, Equatable, Sendable {
    public let id: String; public let sessionKey: String; public let title: String; public let startedAt: Date; public let endedAt: Date; public let duration: TimeInterval; public let summary: String
    public let profileSnapshot: DVKCompanionProfileSnapshot?
    public let source: DVKCompanionMode
    public init(id: String=UUID().uuidString, sessionKey: String, title: String, startedAt: Date, endedAt: Date, duration: TimeInterval, summary: String, profileSnapshot: DVKCompanionProfileSnapshot?=nil, source: DVKCompanionMode = .voice) {
        self.id=id; self.sessionKey=sessionKey; self.title=title; self.startedAt=startedAt; self.endedAt=endedAt; self.duration=duration; self.summary=summary; self.profileSnapshot=profileSnapshot; self.source=source
    }
}
public actor DVKMockReviewGenerator {
    private var generatedSessionKeys:Set<String>=[]
    public init() {}
    public func generate(sessionKey:String, startedAt:Date, endedAt:Date) -> DVKCompanionReview? { guard generatedSessionKeys.insert(sessionKey).inserted else{return nil}; return DVKCompanionReview(sessionKey:sessionKey,title:"Mock voice review",startedAt:startedAt,endedAt:endedAt,duration:max(0,endedAt.timeIntervalSince(startedAt)),summary:"A local showcase session completed with deterministic mock states.") }
    public func generate(sessionKey:String, startedAt:Date, endedAt:Date, profile:DVKCompanionProfileSnapshot?, source:DVKCompanionMode) -> DVKCompanionReview? { guard generatedSessionKeys.insert(sessionKey).inserted else{return nil}; return DVKCompanionReview(sessionKey:sessionKey,title:"\(profile?.displayName ?? "Mock") review",startedAt:startedAt,endedAt:endedAt,duration:max(0,endedAt.timeIntervalSince(startedAt)),summary:"A local \(source.rawValue) showcase session completed with deterministic mock states.",profileSnapshot:profile,source:source) }
}
