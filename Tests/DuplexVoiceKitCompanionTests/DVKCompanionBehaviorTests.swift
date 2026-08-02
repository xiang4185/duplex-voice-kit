import XCTest
@testable import DuplexVoiceKitCompanion

private actor DVKControlledChatService: DVKChatServicing {
    private var continuation: CheckedContinuation<String, Error>?
    private var started = false
    func send(text: String) async throws -> String {
        started = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }
    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }
    func release(with reply: String) {
        continuation?.resume(returning: reply)
        continuation = nil
    }
}

private actor DVKRecordingVoiceService: DVKVoiceServicing {
    private var contexts: [DVKCompanionSessionContext] = []
    func connect(context: DVKCompanionSessionContext) async throws { contexts.append(context) }
    func recordedContexts() -> [DVKCompanionSessionContext] { contexts }
}

@MainActor
final class DVKCompanionBehaviorTests: XCTestCase {
    func testShowcasePrivacyAllowsConfiguredText() async {
        let store = DVKCompanionStore(privacyConfiguration: .showcase)
        store.setPrivacy(.limited)
        store.setDraft("text")
        XCTAssertTrue(store.canSend)
        await store.sendDraft()
        XCTAssertEqual(store.messages.count, 2)
    }

    func testModeSwitchPreservesMessagesAndFailure() async {
        let chat = DVKMockChatService()
        await chat.planNextFailure()
        let store = DVKCompanionStore(chat: chat)
        store.setDraft("failed")
        await store.sendDraft()
        store.setMode(.voice)
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].deliveryState, .failed)
        XCTAssertTrue(store.lastFailure)
    }

    func testSendingIsObservableBeforeControlledServiceCompletes() async {
        let chat = DVKControlledChatService()
        let store = DVKCompanionStore(chat: chat)
        store.setDraft("hold")
        let operation = store.beginSendDraft()
        XCTAssertTrue(store.sending)
        XCTAssertEqual(store.messages.last?.deliveryState, .pending)
        await chat.waitUntilStarted()
        await chat.release(with: "reply")
        await operation?.value
        XCTAssertFalse(store.sending)
    }

    func testConcurrentSecondSendIsRejected() async {
        let chat = DVKControlledChatService()
        let store = DVKCompanionStore(chat: chat)
        store.setDraft("one")
        let first = store.beginSendDraft()
        store.setDraft("two")
        XCTAssertNil(store.beginSendDraft())
        await chat.waitUntilStarted()
        await chat.release(with: "reply")
        await first?.value
        XCTAssertEqual(store.messages.filter { $0.role == .user }.count, 1)
    }

    func testMockFailureControlDrivesFailureThenRetrySuccess() async {
        let chat = DVKMockChatService()
        let store = DVKCompanionStore(chat: chat)
        await store.planNextMockFailure()
        store.setDraft("retry")
        await store.sendDraft()
        XCTAssertTrue(store.lastFailure)
        await store.retryFailedMessage()
        XCTAssertFalse(store.lastFailure)
        XCTAssertEqual(store.messages.filter { $0.role == .assistant }.count, 1)
    }

    func testActiveVoiceSessionCannotBeOverwritten() async {
        let store = DVKCompanionStore()
        await store.beginVoiceDemo()
        await store.beginVoiceDemo()
        XCTAssertEqual(store.advanceVoiceDemo(), .listening)
    }

    func testFullVoiceProgressionGeneratesExactlyOneReview() async {
        let store = DVKCompanionStore()
        await store.beginVoiceDemo()
        _ = store.advanceVoiceDemo()
        _ = store.advanceVoiceDemo()
        _ = store.advanceVoiceDemo()
        XCTAssertEqual(store.advanceVoiceDemo(), .ended)
        await store.endVoiceDemo()
        await store.endVoiceDemo()
        XCTAssertEqual(store.reviews.count, 1)
    }

    func testModeSwitchDoesNotGenerateDuplicateReview() async {
        let store = DVKCompanionStore()
        await store.beginVoiceDemo()
        store.setMode(.text)
        store.setMode(.voice)
        while store.voiceState != .ended {
            _ = store.advanceVoiceDemo()
        }
        await store.endVoiceDemo()
        XCTAssertEqual(store.reviews.count, 1)
    }

    func testUserInputDoesNotDrivePlaybackAmplitude() async {
        let store = DVKCompanionStore()
        await store.beginVoiceDemo()
        _ = store.advanceVoiceDemo()
        _ = store.advanceVoiceDemo()
        _ = store.advanceVoiceDemo()
        let amplitude = store.playbackAmplitude
        store.setDraft("input")
        XCTAssertEqual(store.playbackAmplitude, amplitude)
    }

    func testClearSelectedReviewUsesNilState() async {
        let store = DVKCompanionStore()
        await store.beginVoiceDemo()
        await store.endVoiceDemo()
        store.selectReview(id: store.reviews[0].id)
        store.clearSelectedReview()
        XCTAssertNil(store.selectedReview())
    }

    func testDefaultModeIsText() { XCTAssertEqual(DVKCompanionStore().mode, .text) }
    func testDefaultPrivacyIsAllowed() { XCTAssertEqual(DVKCompanionStore().privacy, .allowed) }
    func testDraftIsStoredByStore() { let store=DVKCompanionStore(); store.setDraft("hello"); XCTAssertEqual(store.draft,"hello") }
    func testWhitespaceDraftCannotSend() { let store=DVKCompanionStore(); store.setDraft("   "); XCTAssertFalse(store.canSend) }
    func testEmptyDraftCannotSend() { XCTAssertFalse(DVKCompanionStore().canSend) }
    func testModeSwitchPreservesDraft() { let store=DVKCompanionStore(); store.setDraft("keep"); store.setMode(.voice); XCTAssertEqual(store.draft,"keep") }
    func testSuccessfulSendAddsOneUserAndOneAssistant() async { let store=DVKCompanionStore(); store.setDraft("hello"); await store.sendDraft(); XCTAssertEqual(store.messages.count,2); XCTAssertEqual(store.messages[0].deliveryState,.sent); XCTAssertEqual(store.messages[1].role,.assistant) }
    func testSuccessfulSendClearsDraft() async { let store=DVKCompanionStore(); store.setDraft("hello"); await store.sendDraft(); XCTAssertEqual(store.draft,"") }
    func testMockChatReturnsDeterministicReply() async throws { let chat=DVKMockChatService(); let reply=try await chat.send(text:"hello"); XCTAssertEqual(reply,"Mock reply: hello") }
    func testFailureMarksMessageAndRestoresDraft() async { let chat=DVKMockChatService(); await chat.planNextFailure(); let store=DVKCompanionStore(chat:chat); store.setDraft("retry"); await store.sendDraft(); XCTAssertTrue(store.lastFailure); XCTAssertEqual(store.messages.count,1); XCTAssertEqual(store.messages[0].deliveryState,.failed); XCTAssertEqual(store.draft,"retry") }
    func testFailureDoesNotAddAssistantMessage() async { let chat=DVKMockChatService(); await chat.planNextFailure(); let store=DVKCompanionStore(chat:chat); store.setDraft("retry"); await store.sendDraft(); XCTAssertEqual(store.messages.filter{$0.role == .assistant}.count,0) }
    func testRetryUpdatesExistingMessage() async { let chat=DVKMockChatService(); await chat.planNextFailure(); let store=DVKCompanionStore(chat:chat); store.setDraft("retry"); await store.sendDraft(); let id=store.messages[0].id; await store.retryFailedMessage(id:id); XCTAssertEqual(store.messages.filter{$0.role == .user}.count,1); XCTAssertEqual(store.messages.count,2); XCTAssertEqual(store.messages[0].deliveryState,.sent) }
    func testRetryClearsFailure() async { let chat=DVKMockChatService(); await chat.planNextFailure(); let store=DVKCompanionStore(chat:chat); store.setDraft("retry"); await store.sendDraft(); await store.retryFailedMessage(); XCTAssertFalse(store.lastFailure) }
    func testLimitedPrivacyBlocksSend() async { let store=DVKCompanionStore(privacyConfiguration: DVKCompanionPrivacyConfiguration(allowsTextWhilePrivacyLimited: false)); store.setPrivacy(.limited); store.setDraft("blocked"); await store.sendDraft(); XCTAssertEqual(store.messages.count,0); XCTAssertFalse(store.canSend) }
    func testLimitedPrivacyBlocksVoice() async { let store=DVKCompanionStore(); store.setPrivacy(.limited); await store.beginVoiceDemo(); XCTAssertEqual(store.voiceState,.idle) }
    func testPrivacyCanEnterAndLeaveLimited() { let store=DVKCompanionStore(); store.setPrivacy(.limited); XCTAssertEqual(store.privacy,.limited); store.reauthorize(); XCTAssertEqual(store.privacy,.allowed) }
    func testReauthorizeRestoresVoice() async { let store=DVKCompanionStore(); store.setPrivacy(.limited); store.reauthorize(); await store.beginVoiceDemo(); XCTAssertEqual(store.voiceState,.connecting) }
    func testVoiceStateAdvancesInOrder() async { let store=DVKCompanionStore(); await store.beginVoiceDemo(); XCTAssertEqual(store.advanceVoiceDemo(),.listening); XCTAssertEqual(store.advanceVoiceDemo(),.processing); XCTAssertEqual(store.advanceVoiceDemo(),.speaking); XCTAssertEqual(store.advanceVoiceDemo(),.ended) }
    func testVoiceCannotAdvanceBeforeStart() { let store=DVKCompanionStore(); XCTAssertEqual(store.advanceVoiceDemo(),.idle) }
    func testSpeakingDrivesAmplitude() async { let store=DVKCompanionStore(); await store.beginVoiceDemo(); _=store.advanceVoiceDemo(); _=store.advanceVoiceDemo(); _=store.advanceVoiceDemo(); XCTAssertEqual(store.playbackAmplitude,0.72) }
    func testEndingVoiceResetsAmplitude() async { let store=DVKCompanionStore(); await store.beginVoiceDemo(); await store.endVoiceDemo(); XCTAssertEqual(store.playbackAmplitude,0) }
    func testVoiceEndCreatesOneReview() async { let store=DVKCompanionStore(); await store.beginVoiceDemo(); await store.endVoiceDemo(); XCTAssertEqual(store.reviews.count,1) }
    func testVoiceReviewContainsDurationAndSummary() async { let store=DVKCompanionStore(); await store.beginVoiceDemo(); await store.endVoiceDemo(); let review=try! XCTUnwrap(store.reviews.first); XCTAssertGreaterThanOrEqual(review.duration,0); XCTAssertFalse(review.summary.isEmpty) }
    func testReviewGenerationIsIdempotentBySessionKey() async { let generator=DVKMockReviewGenerator(); let date=Date(); let first=await generator.generate(sessionKey:"same",startedAt:date,endedAt:date); let second=await generator.generate(sessionKey:"same",startedAt:date,endedAt:date); XCTAssertNotNil(first); XCTAssertNil(second) }
    func testReviewSelectionAndDeletion() async { let store=DVKCompanionStore(); await store.beginVoiceDemo(); await store.endVoiceDemo(); let review=try! XCTUnwrap(store.reviews.first); store.selectReview(id:review.id); XCTAssertEqual(store.selectedReview()?.id,review.id); store.deleteReview(id:review.id); XCTAssertTrue(store.reviews.isEmpty); XCTAssertNil(store.selectedReview()) }
    func testDeletingUnknownReviewIsNoOp() { let store=DVKCompanionStore(); store.deleteReview(id:"missing"); XCTAssertEqual(store.reviews.count,0) }
    func testEggCardsAreExactlyFive() { XCTAssertEqual(DVKCompanionEasterEgg.allCases.count,5) }
    func testOnlyOneEggIsActive() { let store=DVKCompanionStore(); store.presentEasterEgg(.care); store.presentEasterEgg(.about); XCTAssertEqual(store.activeEasterEgg,.about) }
    func testClosingEggRestoresMainFlow() { let store=DVKCompanionStore(); store.presentEasterEgg(.help); store.dismissEasterEgg(); XCTAssertNil(store.activeEasterEgg); XCTAssertEqual(store.mode,.text) }
    func testVoiceModeHasNoNetworkServiceRequirement() { let store=DVKCompanionStore(); store.setMode(.voice); XCTAssertEqual(store.mode,.voice); XCTAssertEqual(store.voiceState,.idle) }
}

extension DVKCompanionBehaviorTests {
    func testCatalogContainsFourPublicCats() {
        let profiles = DVKCompanionProfileCatalog().profiles
        XCTAssertEqual(profiles.count, 4)
        XCTAssertTrue(profiles.allSatisfy { $0.id.hasPrefix("mock.") })
        XCTAssertTrue(profiles.allSatisfy { $0.supports(.text) && $0.supports(.voice) && $0.supports(.review) })
    }

    func testProfilesHaveDistinctVisualAndGreetingData() {
        let profiles = DVKCompanionProfileCatalog().profiles
        XCTAssertEqual(Set(profiles.map(\.characterVisualKey)).count, 4)
        XCTAssertEqual(Set(profiles.map(\.greeting)).count, 4)
        XCTAssertTrue(profiles.allSatisfy { $0.personalityTags.count >= 2 })
    }

    func testPreviewSelectionDoesNotCommitUntilConfirmed() {
        let store = DVKCompanionStore()
        let original = store.selectedProfileID
        store.selectPreviewProfile(id: "mock.story-cat")
        XCTAssertEqual(store.selectedProfileID, original)
        XCTAssertEqual(store.previewProfileID, "mock.story-cat")
        store.confirmProfileSelection()
        XCTAssertEqual(store.selectedProfileID, "mock.story-cat")
    }

    func testPersistenceRestoresSavedProfile() {
        let persistence = DVKInMemoryProfilePersistence(profileID: "mock.thoughtful-cat")
        let store = DVKCompanionStore(persistence: persistence)
        XCTAssertEqual(store.selectedProfileID, "mock.thoughtful-cat")
        XCTAssertEqual(store.selectedProfile?.displayName, "Sage")
    }

    func testInvalidPersistedProfileRequiresChoice() {
        let persistence = DVKInMemoryProfilePersistence(profileID: "mock.missing-cat")
        let store = DVKCompanionStore(persistence: persistence)
        XCTAssertNil(store.selectedProfileID)
        XCTAssertTrue(store.selectedProfileNeedsChoice)
        XCTAssertFalse(store.canSend)
    }

    func testConfirmedProfileIsPersisted() {
        let persistence = DVKInMemoryProfilePersistence()
        let store = DVKCompanionStore(persistence: persistence)
        store.selectPreviewProfile(id: "mock.cheerful-cat")
        store.confirmProfileSelection()
        XCTAssertEqual(persistence.loadProfileID(), "mock.cheerful-cat")
    }

    func testUnavailableProfileCannotBeConfirmed() {
        let store = DVKCompanionStore()
        store.setProfileAvailability(id: "mock.story-cat", availability: .unavailable)
        store.selectPreviewProfile(id: "mock.story-cat")
        store.confirmProfileSelection()
        XCTAssertNotEqual(store.selectedProfileID, "mock.story-cat")
    }

    func testUnavailableProfileDisablesVoice() {
        let store = DVKCompanionStore()
        store.setProfileAvailability(id: store.selectedProfileID!, availability: .unavailable)
        XCTAssertFalse(store.canStartVoice)
        XCTAssertEqual(store.characterState, .unavailable)
    }

    func testTextContextUsesSelectedProfile() async {
        let chat = DVKMockChatService()
        let store = DVKCompanionStore(chat: chat)
        store.selectPreviewProfile(id: "mock.story-cat")
        store.confirmProfileSelection()
        store.setDraft("hello story")
        await store.sendDraft()
        let contexts = await chat.sentContexts()
        XCTAssertEqual(contexts.last?.profile.publicID, "mock.story-cat")
        XCTAssertEqual(store.messages.first?.profileSnapshot?.publicID, "mock.story-cat")
    }

    func testRouteFailureIsVisibleAndDoesNotSwitchProfile() async {
        let resolver = DVKMockProfileRouteResolver()
        await resolver.setFailure(true)
        let store = DVKCompanionStore(routeResolver: resolver)
        store.setDraft("route")
        await store.sendDraft()
        XCTAssertEqual(store.routeState, .failed)
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.messages.first?.deliveryState, .failed)
    }

    func testVoiceContextFreezesProfileDuringActiveSession() async {
        let store = DVKCompanionStore()
        await store.beginVoiceDemo()
        let active = store.selectedProfileID
        store.selectPreviewProfile(id: "mock.story-cat")
        XCTAssertFalse(store.canSelectProfiles)
        XCTAssertEqual(store.voiceState, .connecting)
        XCTAssertEqual(store.selectedProfileID, active)
    }

    func testNewTextUsesNewProfileAndOldMessageKeepsSnapshot() async {
        let chat = DVKMockChatService()
        let store = DVKCompanionStore(chat: chat)
        store.setDraft("first")
        await store.sendDraft()
        store.selectPreviewProfile(id: "mock.cheerful-cat")
        store.confirmProfileSelection()
        store.setDraft("second")
        await store.sendDraft()
        XCTAssertEqual(store.messages[0].profileSnapshot?.publicID, "mock.gentle-cat")
        XCTAssertEqual(store.messages[2].profileSnapshot?.publicID, "mock.cheerful-cat")
    }

    func testReviewKeepsVoiceProfileSnapshot() async {
        let store = DVKCompanionStore()
        store.selectPreviewProfile(id: "mock.thoughtful-cat")
        store.confirmProfileSelection()
        await store.beginVoiceDemo()
        await store.endVoiceDemo()
        XCTAssertEqual(store.reviews.first?.profileSnapshot?.publicID, "mock.thoughtful-cat")
        XCTAssertEqual(store.reviews.first?.source, .voice)
    }

    func testRouteTokenIsNotPartOfReviewModel() {
        let review = DVKCompanionReview(sessionKey: "safe", title: "Safe", startedAt: Date(), endedAt: Date(), duration: 1, summary: "summary")
        XCTAssertNil(review.profileSnapshot)
        XCTAssertFalse(String(describing: review).contains("mock-route"))
    }

    func testSlowScenarioKeepsSendingObservable() async {
        let chat = DVKMockChatService()
        await chat.setSlow(true)
        let store = DVKCompanionStore(chat: chat)
        store.setScenario(.slowText)
        store.setDraft("slow")
        let task = store.beginSendDraft()
        XCTAssertTrue(store.sending)
        await task?.value
        XCTAssertFalse(store.sending)
        XCTAssertEqual(store.messages.last?.role, .assistant)
    }

    func testPlannedTextFailureScenarioIsDeterministic() async {
        let store = DVKCompanionStore()
        await store.planNextMockFailure()
        store.setScenario(.nextTextFailure)
        store.setDraft("fail")
        await store.sendDraft()
        XCTAssertEqual(store.messages.first?.deliveryState, .failed)
        XCTAssertTrue(store.lastFailure)
    }

    func testVoiceConnectionFailureIsVisible() async {
        let store = DVKCompanionStore()
        store.setScenario(.voiceConnectionFailure)
        await store.beginVoiceDemo()
        XCTAssertEqual(store.voiceState, .idle)
        XCTAssertNotNil(store.voiceError)
    }

    func testVoiceInterruptionEndsSessionWithError() async {
        let store = DVKCompanionStore()
        store.setScenario(.voiceInterruption)
        await store.beginVoiceDemo()
        _ = store.advanceVoiceDemo()
        XCTAssertEqual(store.advanceVoiceDemo(), .ended)
        XCTAssertNotNil(store.voiceError)
    }

    func testReviewGenerationFailureCanRetry() async {
        let store = DVKCompanionStore()
        store.setScenario(.reviewGenerationFailure)
        await store.beginVoiceDemo()
        await store.endVoiceDemo()
        XCTAssertEqual(store.generating, .failed)
        await store.retryReviewGeneration()
        XCTAssertEqual(store.generating, .idle)
        XCTAssertEqual(store.reviews.count, 1)
    }

    func testMultipleReviewsScenarioSeedsHistory() {
        let store = DVKCompanionStore()
        store.setScenario(.multipleReviews)
        XCTAssertEqual(store.reviews.count, 4)
    }

    func testEmptyReviewsScenarioClearsHistory() {
        let store = DVKCompanionStore()
        store.setScenario(.multipleReviews)
        store.setScenario(.emptyReviews)
        XCTAssertTrue(store.reviews.isEmpty)
    }

    func testModeSwitchPreservesSelectedProfileAndMessages() async {
        let store = DVKCompanionStore()
        store.setDraft("keep")
        await store.sendDraft()
        let id = store.selectedProfileID
        store.setMode(.voice)
        XCTAssertEqual(store.selectedProfileID, id)
        XCTAssertEqual(store.messages.count, 2)
    }

    func testPlaybackAmplitudeIsClampedAtBothBounds() {
        let store = DVKCompanionStore()
        store.receivePlaybackAmplitude(2)
        XCTAssertEqual(store.playbackAmplitude, 1)
        store.receivePlaybackAmplitude(-2)
        XCTAssertEqual(store.playbackAmplitude, 0)
    }

    func testUserInputCannotInvokePlaybackRelay() {
        let store = DVKCompanionStore()
        store.setPlaybackAmplitudeInput { _ in }
        store.setDraft("typing")
        XCTAssertEqual(store.playbackAmplitude, 0)
    }

    func testAppearanceAndReduceMotionAreStoreDriven() {
        let store = DVKCompanionStore()
        store.setAppearance(.dark)
        store.setReduceMotionPreview(true)
        XCTAssertEqual(store.appearance, .dark)
        XCTAssertTrue(store.reduceMotionPreview)
    }

    func testTabIntentIsStoreDriven() {
        let store = DVKCompanionStore()
        store.setSelectedTab(.profiles)
        XCTAssertEqual(store.selectedTab, .profiles)
    }

    func testLimitedPrivacyShowcaseConfigurationAllowsTextButNotVoice() {
        let store = DVKCompanionStore(privacyConfiguration: .showcase)
        store.setPrivacy(.limited)
        XCTAssertTrue(store.privacyConfiguration.allowsTextWhilePrivacyLimited)
        XCTAssertFalse(store.canStartVoice)
        store.setDraft("limited")
        XCTAssertTrue(store.canSend)
    }
}

extension DVKCompanionBehaviorTests {
    func testVoiceUsesInjectedResolverAndVoiceServiceContext() async {
        let voice = DVKRecordingVoiceService()
        let store = DVKCompanionStore(voiceService: voice)
        await store.beginVoiceDemo()
        let contexts = await voice.recordedContexts()
        XCTAssertEqual(contexts.first?.profile.publicID, store.selectedProfileID)
        XCTAssertEqual(store.routeState, .resolved)
        XCTAssertTrue(store.hasActiveSession)
    }

    func testVoiceRouteFailureCreatesNoSessionOrReview() async {
        let store = DVKCompanionStore()
        store.setScenario(.routeFailure)
        await store.beginVoiceDemo()
        XCTAssertFalse(store.hasActiveSession)
        XCTAssertEqual(store.voiceState, .idle)
        XCTAssertTrue(store.reviews.isEmpty)
        XCTAssertEqual(store.routeState, .failed)
    }

    func testConnectionFailureCanBeRetriedWithoutReview() async {
        let store = DVKCompanionStore()
        store.setScenario(.voiceConnectionFailure)
        await store.beginVoiceDemo()
        XCTAssertFalse(store.hasActiveSession)
        XCTAssertTrue(store.reviews.isEmpty)
        store.setScenario(.normalText)
        await store.beginVoiceDemo()
        XCTAssertTrue(store.hasActiveSession)
    }

    func testNextTextFailureWorksWithoutManualPlan() async {
        let store = DVKCompanionStore()
        store.setScenario(.nextTextFailure)
        store.setDraft("automatic")
        await store.sendDraft()
        XCTAssertTrue(store.lastFailure)
        XCTAssertEqual(store.messages.first?.deliveryState, .failed)
        await store.retryFailedMessage()
        XCTAssertFalse(store.lastFailure)
        XCTAssertEqual(store.messages.filter { $0.role == .assistant }.count, 1)
        store.setDraft("after retry")
        await store.sendDraft()
        XCTAssertEqual(store.messages.filter { $0.role == .assistant && $0.deliveryState == .sent }.count, 2)
    }

    func testNormalScenarioClearsPreviousFailureAndAvailability() async {
        let store = DVKCompanionStore()
        store.setScenario(.profileUnavailable)
        XCTAssertEqual(store.selectedProfile?.availability, .unavailable)
        store.setScenario(.normalText)
        XCTAssertEqual(store.selectedProfile?.availability, .available)
        XCTAssertNil(store.lastError)
        XCTAssertNil(store.voiceError)
    }

    func testReviewRetryKeepsOriginalProfileAfterCurrentProfileChanges() async {
        let store = DVKCompanionStore()
        store.setScenario(.reviewGenerationFailure)
        let original = store.selectedProfileID
        await store.beginVoiceDemo()
        await store.endVoiceDemo()
        XCTAssertEqual(store.generating, .failed)
        store.selectPreviewProfile(id: "mock.story-cat")
        store.confirmProfileSelection()
        await store.retryReviewGeneration()
        XCTAssertEqual(store.reviews.first?.profileSnapshot?.publicID, original)
    }

    func testPlaybackAndCharacterControlsAreIndependent() {
        let store = DVKCompanionStore()
        store.setMockPlaybackAmplitude(0.8)
        store.setMockCharacterState(.listening)
        XCTAssertEqual(store.playbackAmplitude, 0.8)
        XCTAssertEqual(store.characterState, .listening)
        store.setPresentationMode(.staticFallback)
        XCTAssertEqual(store.presentationMode, .staticFallback)
    }

    func testFollowProfileIsDefaultAppearance() {
        XCTAssertEqual(DVKCompanionStore().appearance, .followProfile)
    }
}
