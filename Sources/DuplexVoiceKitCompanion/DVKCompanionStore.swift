import Foundation

public enum DVKCompanionTab: String, CaseIterable, Codable, Sendable { case home, profiles, reviews, settings }

@MainActor
public final class DVKCompanionStore {
    public private(set) var initializationState: DVKCompanionInitializationState = .initializing
    public private(set) var mode: DVKCompanionMode = .text
    public private(set) var draft = ""
    public private(set) var messages: [DVKCompanionMessage] = []
    public private(set) var privacy: DVKCompanionPrivacyState = .allowed
    public let privacyConfiguration: DVKCompanionPrivacyConfiguration
    public private(set) var sending = false
    public private(set) var lastFailure = false
    public private(set) var lastError: String?
    public private(set) var mockFailurePlanned = false
    public private(set) var voiceState: DVKCompanionVoiceState = .idle
    public private(set) var voiceError: String?
    public private(set) var playbackAmplitude: Float = 0
    public private(set) var activeEasterEgg: DVKCompanionEasterEgg?
    public private(set) var reviews: [DVKCompanionReview] = []
    public private(set) var generating: DVKReviewGenerating = .idle
    public private(set) var selectedReviewID: String?
    public private(set) var selectedProfileID: String?
    public private(set) var previewProfileID: String
    public private(set) var routeState: DVKCompanionProfileRouteState = .idle
    public private(set) var activeScenario: DVKCompanionMockScenario = .normalText
    public private(set) var selectedTab: DVKCompanionTab = .home
    public private(set) var appearance: DVKCompanionAppearance = .followProfile
    public private(set) var reduceMotionPreview = false
    public private(set) var presentationMode: DVKCompanionPresentationMode = .programmatic
    public private(set) var mockCharacterState: DVKCompanionCharacterPresentationState?

    public let profiles: [DVKCompanionProfile]
    private let catalog: DVKCompanionProfileCatalog
    private let chat: any DVKChatServicing
    private let reviewGenerator: DVKMockReviewGenerator
    private let routeResolver: any DVKCompanionProfileRouteResolving
    private let voiceService: any DVKVoiceServicing
    private let persistence: any DVKCompanionProfilePersistence
    private let slowGate: any DVKCompanionAsyncGate
    private var voiceSessionKey: String?
    private var voiceStartedAt: Date?
    private var voiceSessionContext: DVKCompanionSessionContext?
    private var playbackAmplitudeInput: (@Sendable (Float) -> Void)?
    private var profileAvailabilityOverrides: [String: DVKCompanionProfileAvailability] = [:]
    private var pendingReview: (sessionKey: String, startedAt: Date, endedAt: Date, profile: DVKCompanionProfileSnapshot, source: DVKCompanionMode)?

    public init(
        chat: any DVKChatServicing = DVKMockChatService(),
        reviewGenerator: DVKMockReviewGenerator = DVKMockReviewGenerator(),
        privacyConfiguration: DVKCompanionPrivacyConfiguration = .showcase,
        catalog: DVKCompanionProfileCatalog = DVKCompanionProfileCatalog(),
        routeResolver: any DVKCompanionProfileRouteResolving = DVKMockProfileRouteResolver(),
        voiceService: any DVKVoiceServicing = DVKMockVoiceService(),
        persistence: any DVKCompanionProfilePersistence = DVKInMemoryProfilePersistence(),
        slowGate: any DVKCompanionAsyncGate = DVKDeterministicSlowGate()
    ) {
        self.chat = chat; self.reviewGenerator = reviewGenerator; self.privacyConfiguration = privacyConfiguration
        self.catalog = catalog; self.profiles = catalog.profiles; self.routeResolver = routeResolver; self.voiceService = voiceService; self.persistence = persistence; self.slowGate = slowGate
        let saved = persistence.loadProfileID()
        let initial = saved.flatMap { catalog.profile(id: $0) }?.id ?? (saved == nil ? catalog.profiles.first?.id : nil) ?? "mock.gentle-cat"
        self.selectedProfileID = saved == nil ? catalog.profiles.first?.id : saved.flatMap { catalog.profile(id: $0) }?.id
        self.previewProfileID = initial
    }

    public var selectedProfile: DVKCompanionProfile? {
        guard let id = selectedProfileID, let profile = catalog.profile(id:id) else { return nil }
        return overridden(profile)
    }
    public var previewProfile: DVKCompanionProfile? {
        guard let profile = catalog.profile(id: previewProfileID) else { return nil }
        return overridden(profile)
    }
    public var selectedProfileNeedsChoice: Bool { selectedProfileID == nil }
    public var canConfirmProfileSelection: Bool { !sending && voiceSessionKey == nil && previewProfileID != selectedProfileID }
    public var canSend: Bool {
        let allows = privacy == .allowed || (privacy == .limited && privacyConfiguration.allowsTextWhilePrivacyLimited)
        return allows && !sending && !selectedProfileNeedsChoice && selectedProfile?.supports(.text) == true && !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
    }
    public var canPlanMockFailure: Bool { chat is DVKMockChatService && !sending && !mockFailurePlanned }
    public var canStartVoice: Bool { voiceSessionKey == nil && routeState != .resolving && privacy == .allowed && selectedProfile?.availability == .available && selectedProfile?.supports(.voice) == true && !selectedProfileNeedsChoice && (voiceState == .idle || voiceState == .ended) }
    public var canEndVoice: Bool { voiceSessionKey != nil && voiceState != .idle }
    public var canSelectProfiles: Bool { !sending && voiceSessionKey == nil && routeState != .resolving }
    public var hasActiveSession: Bool { voiceSessionKey != nil }
    public var characterState: DVKCompanionCharacterPresentationState {
        if let mockCharacterState { return mockCharacterState }
        if selectedProfile?.availability != .available { return .unavailable }
        switch voiceState { case .listening: return .listening; case .processing: return .thinking; case .speaking: return .speaking(amplitude: playbackAmplitude); default: return lastError == nil ? .idle : .error }
    }

    private func overridden(_ profile: DVKCompanionProfile) -> DVKCompanionProfile {
        guard let availability = profileAvailabilityOverrides[profile.id] else { return profile }
        return DVKCompanionProfile(id:profile.id, displayName:profile.displayName, shortSummary:profile.shortSummary, greeting:profile.greeting, personalityTags:profile.personalityTags, characterVisualKey:profile.characterVisualKey, themeKey:profile.themeKey, capabilities:profile.capabilities, availability:availability, accessibilityDescription:profile.accessibilityDescription)
    }

    public func initializeLocally() { initializationState = .ready }
    public func setPlaybackAmplitudeInput(_ input: (@Sendable (Float) -> Void)?) { playbackAmplitudeInput = input }
    public func receivePlaybackAmplitude(_ amplitude: Float) { playbackAmplitude = Self.clampAmplitude(amplitude) }
    public func setMode(_ mode: DVKCompanionMode) { guard voiceSessionKey == nil else { return }; self.mode = mode }
    public func setDraft(_ draft: String) { self.draft = draft }
    public func setSelectedTab(_ tab: DVKCompanionTab) { selectedTab = tab }
    public func setAppearance(_ value: DVKCompanionAppearance) { appearance = value }
    public func setReduceMotionPreview(_ value: Bool) { reduceMotionPreview = value }
    public func setPresentationMode(_ value: DVKCompanionPresentationMode) { presentationMode = value }
    public func setMockCharacterState(_ value: DVKCompanionCharacterPresentationState?) { mockCharacterState = value }
    public func setMockPlaybackAmplitude(_ value: Float) { receivePlaybackAmplitude(value) }
    public func selectPreviewProfile(id: String) { guard canSelectProfiles, catalog.profile(id:id) != nil else { return }; previewProfileID = id }
    public func confirmProfileSelection() {
        guard let rawProfile = catalog.profile(id: previewProfileID) else { return }
        let profile = overridden(rawProfile)
        guard canConfirmProfileSelection, profile.availability == .available else { return }
        selectedProfileID = profile.id; persistence.saveProfileID(profile.id); routeState = .idle; lastError = nil
    }
    public func restoreProfile(id: String?) {
        guard let id, let profile = catalog.profile(id:id), profile.availability == .available else { selectedProfileID = nil; return }
        selectedProfileID = id; previewProfileID = id; persistence.saveProfileID(id)
    }
    public func setScenario(_ scenario: DVKCompanionMockScenario) {
        activeScenario = scenario
        presentationMode = .programmatic
        mockCharacterState = nil
        playbackAmplitude = 0
        privacy = .allowed
        profileAvailabilityOverrides.removeAll()
        voiceError = nil
        lastError = nil
        routeState = .idle
        voiceState = .idle
        voiceSessionKey = nil
        voiceStartedAt = nil
        voiceSessionContext = nil
        generating = .idle
        pendingReview = nil
        mockFailurePlanned = scenario == .nextTextFailure
        if scenario == .limitedPrivacy { setPrivacy(.limited) }
        if scenario == .emptyReviews { reviews = [] }
        if scenario == .multipleReviews { seedReviews() }
        if scenario == .profileUnavailable, let id = selectedProfileID { profileAvailabilityOverrides[id] = .unavailable }
    }
    public func clearError() { lastError = nil; voiceError = nil; routeState = routeState == .failed ? .idle : routeState }
    public func setProfileAvailability(id: String, availability: DVKCompanionProfileAvailability) { profileAvailabilityOverrides[id] = availability }
    public func planNextMockFailure() async {
        guard !sending, !mockFailurePlanned, let mock = chat as? DVKMockChatService else { return }
        await mock.planNextFailure(); mockFailurePlanned = true
    }

    public func beginSendDraft() -> Task<Void,Never>? {
        guard canSend, let profile = selectedProfile else { return nil }
        let text = draft.trimmingCharacters(in:.whitespacesAndNewlines)
        let message = DVKCompanionMessage(role:.user,text:text,deliveryState:.pending,profileSnapshot:profile.snapshot)
        messages.append(message); draft = ""; sending = true; lastFailure = false; lastError = nil
        return Task { [weak self] in await self?.completeSend(messageID:message.id,text:text,profile:profile.snapshot) }
    }
    public func sendDraft() async { guard let task = beginSendDraft() else { return }; await task.value }

    public func beginRetryFailedMessage(id: String? = nil) -> Task<Void,Never>? {
        guard !sending, let failed = messages.last(where:{$0.role == .user && $0.deliveryState == .failed && (id == nil || $0.id == id)}), let profile = failed.profileSnapshot else { return nil }
        updateMessage(id:failed.id,state:.pending); draft = ""; sending = true; lastFailure = false
        return Task { [weak self] in await self?.completeSend(messageID:failed.id,text:failed.text,profile:profile) }
    }
    public func retryFailedMessage(id: String? = nil) async { guard let task = beginRetryFailedMessage(id:id) else{return}; await task.value }

    private func completeSend(messageID:String,text:String,profile:DVKCompanionProfileSnapshot) async {
        defer { sending = false; mockFailurePlanned = false }
        do {
            routeState = .resolving
            if activeScenario == .routeFailure { throw DVKCompanionProfileRoutingError.resolutionFailed }
            let token = try await routeResolver.resolve(publicProfileID:profile.publicID)
            routeState = .resolved
            if activeScenario == .slowText { await slowGate.wait() }
            if activeScenario == .nextTextFailure {
                activeScenario = .normalText
                mockFailurePlanned = false
                throw DVKCompanionChatError.plannedFailure
            }
            let reply = try await chat.send(text:text,context:DVKCompanionSessionContext(profile:profile,routeToken:token))
            updateMessage(id:messageID,state:.sent)
            messages.append(DVKCompanionMessage(role:.assistant,text:reply,deliveryState:.sent,profileSnapshot:profile))
            lastError = nil
        } catch {
            if error is DVKCompanionProfileRoutingError { routeState = .failed } else if routeState == .failed { routeState = .resolved }; updateMessage(id:messageID,state:.failed); draft = text; lastFailure = true
            lastError = error is DVKCompanionProfileRoutingError ? "This mock route could not be resolved." : "The mock message could not be sent."
        }
    }

    public func setPrivacy(_ value: DVKCompanionPrivacyState) { privacy = value; if value == .limited { publishPlaybackAmplitude(0) } }
    public func reauthorize() { privacy = .allowed }
    public func presentEasterEgg(_ egg: DVKCompanionEasterEgg) { activeEasterEgg = egg }
    public func dismissEasterEgg() { activeEasterEgg = nil }
    public func selectReview(id:String) { selectedReviewID = reviews.contains(where:{$0.id==id}) ? id : nil }
    public func clearSelectedReview() { selectedReviewID = nil }
    public func selectedReview() -> DVKCompanionReview? { guard let id = selectedReviewID else{return nil}; return reviews.first{$0.id==id} }
    public func deleteReview(id:String) { reviews.removeAll{$0.id==id}; if selectedReviewID==id { selectedReviewID = nil } }

    public func beginVoiceDemo() async {
        guard canStartVoice, let profile = selectedProfile else { return }
        let snapshot = profile.snapshot
        routeState = .resolving
        voiceError = nil
        do {
            if activeScenario == .routeFailure { throw DVKCompanionProfileRoutingError.resolutionFailed }
            let token = try await routeResolver.resolve(publicProfileID: snapshot.publicID)
            let context = DVKCompanionSessionContext(profile: snapshot, routeToken: token)
            if activeScenario == .voiceConnectionFailure { throw DVKCompanionChatError.connectionFailure }
            try await voiceService.connect(context: context)
            guard routeState == .resolving else { return }
            voiceSessionKey = UUID().uuidString
            voiceStartedAt = Date()
            voiceSessionContext = context
            routeState = .resolved
            voiceState = .connecting
            publishPlaybackAmplitude(0)
        } catch {
            routeState = .failed
            voiceState = .idle
            voiceError = error is DVKCompanionProfileRoutingError ? "This mock voice route could not be resolved." : "The mock voice connection failed."
            lastError = voiceError
            voiceSessionKey = nil
            voiceStartedAt = nil
            voiceSessionContext = nil
            publishPlaybackAmplitude(0)
        }
    }
    @discardableResult public func advanceVoiceDemo() -> DVKCompanionVoiceState {
        guard voiceSessionKey != nil, let next = voiceState.next else{return voiceState}
        if activeScenario == .voiceInterruption && next == .processing { voiceError = "The mock voice session was interrupted."; voiceState = .ended; publishPlaybackAmplitude(0); return .ended }
        voiceState = next; publishPlaybackAmplitude(next == .speaking ? 0.72 : 0); return next
    }
    public func endVoiceDemo() async {
        guard voiceSessionKey != nil, voiceStartedAt != nil else{return}
        if voiceState != .ended { voiceState = .ended; publishPlaybackAmplitude(0) }
        await finishVoiceSession()
    }
    private func finishVoiceSession() async {
        guard let key = voiceSessionKey, let started = voiceStartedAt, generating == .idle else{return}
        guard let context = voiceSessionContext else { return }
        let ended = Date()
        if activeScenario == .reviewGenerationFailure {
            pendingReview = (key, started, ended, context.profile, .voice)
            generating = .failed
            lastError = "The mock review could not be generated."
            voiceSessionKey = nil; voiceStartedAt = nil; voiceSessionContext = nil
            return
        }
        generating = .generating
        if let review = await reviewGenerator.generate(sessionKey:key,startedAt:started,endedAt:ended,profile:context.profile,source:.voice) { reviews.insert(review,at:0) }
        pendingReview = nil
        generating = .idle; voiceSessionKey = nil; voiceStartedAt = nil; voiceSessionContext = nil
    }
    public func retryReviewGeneration() async {
        guard generating == .failed else{return}
        guard let pending = pendingReview else { return }
        generating = .generating
        if let review = await reviewGenerator.generate(sessionKey:pending.sessionKey,startedAt:pending.startedAt,endedAt:pending.endedAt,profile:pending.profile,source:pending.source){reviews.insert(review,at:0)}
        pendingReview = nil
        activeScenario = .normalText
        generating = .idle; lastError = nil
    }

    private func seedReviews() {
        guard reviews.isEmpty else{return}
        let now = Date(); for (index,profile) in profiles.enumerated() { reviews.append(DVKCompanionReview(sessionKey:"seed-\(index)",title:"\(profile.displayName) mock review",startedAt:now,endedAt:now,duration:TimeInterval(index),summary:"A local review for \(profile.displayName).",profileSnapshot:profile.snapshot,source:index.isMultiple(of:2) ? .voice : .text)) }
    }
    private func updateMessage(id:String,state:DVKCompanionDeliveryState) { guard let i = messages.firstIndex(where:{$0.id==id}) else{return}; messages[i].deliveryState = state }
    private func publishPlaybackAmplitude(_ value:Float) { let v = Self.clampAmplitude(value); if let input = playbackAmplitudeInput { input(v) } else { receivePlaybackAmplitude(v) } }
    private static func clampAmplitude(_ value:Float)->Float { min(1,max(0,value)) }
}
