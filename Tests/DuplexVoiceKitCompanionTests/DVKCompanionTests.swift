import XCTest
@testable import DuplexVoiceKitCompanion

@MainActor final class DVKCompanionTests: XCTestCase {
    func testDefaultModeIsText() { XCTAssertEqual(DVKCompanionStore().mode, .text) }
    func testModeSwitch() { let s=DVKCompanionStore(); s.setDraft("hello"); s.setMode(.voice); XCTAssertEqual(s.draft,"hello"); XCTAssertEqual(s.mode,.voice) }
    func testEmptyDraftCannotSend() { XCTAssertFalse(DVKCompanionStore().canSend) }
    func testSuccessfulSend() async { let s=DVKCompanionStore(); s.setDraft("hi"); await s.sendDraft(); XCTAssertEqual(s.messages.count,2); XCTAssertEqual(s.messages[0].deliveryState,.sent) }
    func testFailureAndRetry() async { let chat=DVKMockChatService(); await chat.failNextSend(); let s=DVKCompanionStore(chat:chat); s.setDraft("retry"); await s.sendDraft(); XCTAssertTrue(s.lastFailure); await s.retryLastMessage(); XCTAssertEqual(s.messages.filter{$0.role == .user}.count,1); XCTAssertFalse(s.lastFailure) }
    func testLimitedBlocksVoice() { let s=DVKCompanionStore(); s.setPrivacy(.limited); s.beginVoiceDemo(); XCTAssertEqual(s.mockVoiceState,"idle"); s.reauthorize(); s.beginVoiceDemo(); XCTAssertEqual(s.mockVoiceState,"connecting") }
    func testVoiceProgression() { let s=DVKCompanionStore(); s.beginVoiceDemo(); s.advanceVoiceDemo(); XCTAssertEqual(s.mockVoiceState,"listening"); s.advanceVoiceDemo(); XCTAssertEqual(s.mockVoiceState,"processing") }
    func testReviewIdempotency() async { let g=DVKMockReviewGenerator(); let d=Date(); XCTAssertNotNil(await g.generate(sessionKey:"one",startedAt:d,endedAt:d)); XCTAssertNil(await g.generate(sessionKey:"one",startedAt:d,endedAt:d)) }
    func testReviewDeletion() async { let s=DVKCompanionStore(); s.beginVoiceDemo(); await s.endVoiceDemo(); let id=try! XCTUnwrap(s.reviews.first?.id); s.deleteReview(id:id); XCTAssertTrue(s.reviews.isEmpty) }
    func testOneEggAtATime() { let s=DVKCompanionStore(); s.present(.care); s.present(.help); XCTAssertEqual(s.activeEasterEgg,.help); s.dismissEasterEgg(); XCTAssertNil(s.activeEasterEgg) }
}
