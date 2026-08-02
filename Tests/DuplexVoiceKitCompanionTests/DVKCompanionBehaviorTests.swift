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

    func testActiveVoiceSessionCannotBeOverwritten() {
        let store = DVKCompanionStore()
        store.beginVoiceDemo()
        store.beginVoiceDemo()
        XCTAssertEqual(store.advanceVoiceDemo(), .listening)
    }

    func testFullVoiceProgressionGeneratesExactlyOneReview() async {
        let store = DVKCompanionStore()
        store.beginVoiceDemo()
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
        store.beginVoiceDemo()
        store.setMode(.text)
        store.setMode(.voice)
        while store.voiceState != .ended {
            _ = store.advanceVoiceDemo()
        }
        await store.endVoiceDemo()
        XCTAssertEqual(store.reviews.count, 1)
    }

    func testUserInputDoesNotDrivePlaybackAmplitude() {
        let store = DVKCompanionStore()
        store.beginVoiceDemo()
        _ = store.advanceVoiceDemo()
        _ = store.advanceVoiceDemo()
        _ = store.advanceVoiceDemo()
        let amplitude = store.playbackAmplitude
        store.setDraft("input")
        XCTAssertEqual(store.playbackAmplitude, amplitude)
    }

    func testClearSelectedReviewUsesNilState() async {
        let store = DVKCompanionStore()
        store.beginVoiceDemo()
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
    func testLimitedPrivacyBlocksVoice() { let store=DVKCompanionStore(); store.setPrivacy(.limited); store.beginVoiceDemo(); XCTAssertEqual(store.voiceState,.idle) }
    func testPrivacyCanEnterAndLeaveLimited() { let store=DVKCompanionStore(); store.setPrivacy(.limited); XCTAssertEqual(store.privacy,.limited); store.reauthorize(); XCTAssertEqual(store.privacy,.allowed) }
    func testReauthorizeRestoresVoice() { let store=DVKCompanionStore(); store.setPrivacy(.limited); store.reauthorize(); store.beginVoiceDemo(); XCTAssertEqual(store.voiceState,.connecting) }
    func testVoiceStateAdvancesInOrder() { let store=DVKCompanionStore(); store.beginVoiceDemo(); XCTAssertEqual(store.advanceVoiceDemo(),.listening); XCTAssertEqual(store.advanceVoiceDemo(),.processing); XCTAssertEqual(store.advanceVoiceDemo(),.speaking); XCTAssertEqual(store.advanceVoiceDemo(),.ended) }
    func testVoiceCannotAdvanceBeforeStart() { let store=DVKCompanionStore(); XCTAssertEqual(store.advanceVoiceDemo(),.idle) }
    func testSpeakingDrivesAmplitude() { let store=DVKCompanionStore(); store.beginVoiceDemo(); _=store.advanceVoiceDemo(); _=store.advanceVoiceDemo(); _=store.advanceVoiceDemo(); XCTAssertEqual(store.playbackAmplitude,0.72) }
    func testEndingVoiceResetsAmplitude() async { let store=DVKCompanionStore(); store.beginVoiceDemo(); await store.endVoiceDemo(); XCTAssertEqual(store.playbackAmplitude,0) }
    func testVoiceEndCreatesOneReview() async { let store=DVKCompanionStore(); store.beginVoiceDemo(); await store.endVoiceDemo(); XCTAssertEqual(store.reviews.count,1) }
    func testVoiceReviewContainsDurationAndSummary() async { let store=DVKCompanionStore(); store.beginVoiceDemo(); await store.endVoiceDemo(); let review=try! XCTUnwrap(store.reviews.first); XCTAssertGreaterThanOrEqual(review.duration,0); XCTAssertFalse(review.summary.isEmpty) }
    func testReviewGenerationIsIdempotentBySessionKey() async { let generator=DVKMockReviewGenerator(); let date=Date(); let first=await generator.generate(sessionKey:"same",startedAt:date,endedAt:date); let second=await generator.generate(sessionKey:"same",startedAt:date,endedAt:date); XCTAssertNotNil(first); XCTAssertNil(second) }
    func testReviewSelectionAndDeletion() async { let store=DVKCompanionStore(); store.beginVoiceDemo(); await store.endVoiceDemo(); let review=try! XCTUnwrap(store.reviews.first); store.selectReview(id:review.id); XCTAssertEqual(store.selectedReview()?.id,review.id); store.deleteReview(id:review.id); XCTAssertTrue(store.reviews.isEmpty); XCTAssertNil(store.selectedReview()) }
    func testDeletingUnknownReviewIsNoOp() { let store=DVKCompanionStore(); store.deleteReview(id:"missing"); XCTAssertEqual(store.reviews.count,0) }
    func testEggCardsAreExactlyFive() { XCTAssertEqual(DVKCompanionEasterEgg.allCases.count,5) }
    func testOnlyOneEggIsActive() { let store=DVKCompanionStore(); store.presentEasterEgg(.care); store.presentEasterEgg(.about); XCTAssertEqual(store.activeEasterEgg,.about) }
    func testClosingEggRestoresMainFlow() { let store=DVKCompanionStore(); store.presentEasterEgg(.help); store.dismissEasterEgg(); XCTAssertNil(store.activeEasterEgg); XCTAssertEqual(store.mode,.text) }
    func testVoiceModeHasNoNetworkServiceRequirement() { let store=DVKCompanionStore(); store.setMode(.voice); XCTAssertEqual(store.mode,.voice); XCTAssertEqual(store.voiceState,.idle) }
}
