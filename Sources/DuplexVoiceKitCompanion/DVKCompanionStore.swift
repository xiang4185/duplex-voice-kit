import Foundation

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
    public private(set) var mockFailurePlanned = false
    public private(set) var voiceState: DVKCompanionVoiceState = .idle
    public private(set) var playbackAmplitude: Float = 0
    public private(set) var activeEasterEgg: DVKCompanionEasterEgg?
    public private(set) var reviews: [DVKCompanionReview] = []
    public private(set) var generating: DVKReviewGenerating = .idle
    public private(set) var selectedReviewID: String?

    private let chat: any DVKChatServicing
    private let reviewGenerator: DVKMockReviewGenerator
    private var voiceSessionKey: String?
    private var voiceStartedAt: Date?
    private var playbackAmplitudeInput: (@Sendable (Float) -> Void)?

    public init(
        chat: any DVKChatServicing = DVKMockChatService(),
        reviewGenerator: DVKMockReviewGenerator = DVKMockReviewGenerator(),
        privacyConfiguration: DVKCompanionPrivacyConfiguration = .showcase
    ) {
        self.chat = chat
        self.reviewGenerator = reviewGenerator
        self.privacyConfiguration = privacyConfiguration
    }

    public var canSend: Bool {
        let allowsText = privacy == .allowed ||
            (privacy == .limited && privacyConfiguration.allowsTextWhilePrivacyLimited)
        return allowsText && !sending &&
            !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var canPlanMockFailure: Bool {
        chat is DVKMockChatService && !sending && !mockFailurePlanned
    }

    public var canStartVoice: Bool {
        voiceSessionKey == nil && privacy == .allowed &&
            (voiceState == .idle || voiceState == .ended)
    }

    public var canEndVoice: Bool {
        voiceSessionKey != nil && voiceState != .idle
    }

    public func initializeLocally() { initializationState = .ready }

    public func setPlaybackAmplitudeInput(_ input: (@Sendable (Float) -> Void)?) {
        playbackAmplitudeInput = input
    }

    public func receivePlaybackAmplitude(_ amplitude: Float) {
        playbackAmplitude = Self.clampAmplitude(amplitude)
    }

    public func setMode(_ mode: DVKCompanionMode) { self.mode = mode }
    public func setDraft(_ draft: String) { self.draft = draft }

    public func planNextMockFailure() async {
        guard !sending, !mockFailurePlanned,
              let mock = chat as? DVKMockChatService else { return }
        await mock.planNextFailure()
        mockFailurePlanned = true
    }

    public func beginSendDraft() -> Task<Void, Never>? {
        guard canSend else { return nil }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = DVKCompanionMessage(role: .user, text: text, deliveryState: .pending)
        messages.append(message)
        draft = ""
        sending = true
        lastFailure = false
        return Task { [weak self] in
            await self?.completeSend(messageID: message.id, text: text)
        }
    }

    public func sendDraft() async {
        guard let operation = beginSendDraft() else { return }
        await operation.value
    }

    public func beginRetryFailedMessage(id: String? = nil) -> Task<Void, Never>? {
        guard !sending else { return nil }
        guard let failed = messages.last(where: {
            $0.role == .user && $0.deliveryState == .failed &&
            (id == nil || $0.id == id)
        }) else { return nil }
        let text = failed.text
        updateMessage(id: failed.id, state: .pending)
        draft = ""
        sending = true
        lastFailure = false
        return Task { [weak self] in
            await self?.completeSend(messageID: failed.id, text: text)
        }
    }

    public func retryFailedMessage(id: String? = nil) async {
        guard let operation = beginRetryFailedMessage(id: id) else { return }
        await operation.value
    }

    public func setPrivacy(_ privacy: DVKCompanionPrivacyState) {
        self.privacy = privacy
        if privacy == .limited { publishPlaybackAmplitude(0) }
    }

    public func reauthorize() { privacy = .allowed }
    public func presentEasterEgg(_ egg: DVKCompanionEasterEgg) { activeEasterEgg = egg }
    public func dismissEasterEgg() { activeEasterEgg = nil }

    public func selectReview(id: String) {
        guard reviews.contains(where: { $0.id == id }) else {
            clearSelectedReview()
            return
        }
        selectedReviewID = id
    }

    public func clearSelectedReview() { selectedReviewID = nil }

    public func selectedReview() -> DVKCompanionReview? {
        guard let selectedReviewID else { return nil }
        return reviews.first { $0.id == selectedReviewID }
    }

    public func deleteReview(id: String) {
        reviews.removeAll { $0.id == id }
        if selectedReviewID == id { clearSelectedReview() }
    }

    public func beginVoiceDemo() {
        guard canStartVoice else { return }
        voiceSessionKey = UUID().uuidString
        voiceStartedAt = Date()
        voiceState = .connecting
        publishPlaybackAmplitude(0)
    }

    @discardableResult
    public func advanceVoiceDemo() -> DVKCompanionVoiceState {
        guard voiceSessionKey != nil, let next = voiceState.next else { return voiceState }
        voiceState = next
        publishPlaybackAmplitude(next == .speaking ? 0.72 : 0)
        return next
    }

    public func endVoiceDemo() async {
        guard voiceSessionKey != nil, voiceStartedAt != nil else { return }
        if voiceState != .ended {
            voiceState = .ended
            publishPlaybackAmplitude(0)
        }
        await finishVoiceSession()
    }

    private func completeSend(messageID: String, text: String) async {
        defer {
            sending = false
            mockFailurePlanned = false
        }
        do {
            let reply = try await chat.send(text: text)
            updateMessage(id: messageID, state: .sent)
            messages.append(DVKCompanionMessage(role: .assistant, text: reply, deliveryState: .sent))
        } catch {
            updateMessage(id: messageID, state: .failed)
            draft = text
            lastFailure = true
        }
    }

    private func finishVoiceSession() async {
        guard let voiceSessionKey, let voiceStartedAt, generating == .idle else { return }
        generating = .generating
        if let review = await reviewGenerator.generate(
            sessionKey: voiceSessionKey,
            startedAt: voiceStartedAt,
            endedAt: Date()
        ) {
            reviews.insert(review, at: 0)
        }
        generating = .idle
        self.voiceSessionKey = nil
        self.voiceStartedAt = nil
    }

    private func publishPlaybackAmplitude(_ amplitude: Float) {
        let clamped = Self.clampAmplitude(amplitude)
        if let playbackAmplitudeInput {
            playbackAmplitudeInput(clamped)
        } else {
            receivePlaybackAmplitude(clamped)
        }
    }

    private func updateMessage(id: String, state: DVKCompanionDeliveryState) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].deliveryState = state
    }

    private static func clampAmplitude(_ amplitude: Float) -> Float {
        min(1, max(0, amplitude))
    }
}
