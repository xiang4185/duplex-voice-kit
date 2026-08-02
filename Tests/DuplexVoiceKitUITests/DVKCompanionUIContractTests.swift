import XCTest
@testable import DuplexVoiceKitUI

final class DVKCompanionUIContractTests: XCTestCase {
    func testModePickerIdentifierIsStable() { XCTAssertEqual(DVKCompanionAccessibilityID.modePicker,"companion.modePicker") }
    func testTextInputIdentifierIsStable() { XCTAssertEqual(DVKCompanionAccessibilityID.chatInput,"companion.chatInput") }
    func testSendAndRetryIdentifiersAreDistinct() {
        XCTAssertEqual(DVKCompanionAccessibilityID.chatPlanFailure, "companion.chatPlanFailure")
        XCTAssertEqual(DVKCompanionAccessibilityID.chatSending, "companion.chatSending")
        XCTAssertNotEqual(DVKCompanionAccessibilityID.chatSend,DVKCompanionAccessibilityID.chatRetry)
    }
    func testVoiceIdentifiersAreComplete() { XCTAssertFalse(DVKCompanionAccessibilityID.voiceStart.isEmpty); XCTAssertFalse(DVKCompanionAccessibilityID.voiceAdvance.isEmpty); XCTAssertFalse(DVKCompanionAccessibilityID.voiceEnd.isEmpty) }
    func testPlaybackRelayClampsAmplitude() {
        let relay = DVKPlaybackAmplitudeRelay()
        relay.playbackAmplitudeDidChange(2)
        XCTAssertEqual(relay.currentAmplitude, 1)
        relay.playbackAmplitudeDidChange(-1)
        XCTAssertEqual(relay.currentAmplitude, 0)
    }

    func testPrivacyAndReviewIdentifiersAreComplete() { XCTAssertFalse(DVKCompanionAccessibilityID.privacyAllowed.isEmpty); XCTAssertFalse(DVKCompanionAccessibilityID.reauthorize.isEmpty); XCTAssertFalse(DVKCompanionAccessibilityID.reviewList.isEmpty); XCTAssertFalse(DVKCompanionAccessibilityID.reviewDelete.isEmpty) }
}

#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

extension DVKCompanionUIContractTests {
    @MainActor
    func testPublicViewsAreConstructibleFromOneStore() {
        let store = DVKCompanionStore()
        let startup = DVKCompanionStartupView(store: store)
        let main = DVKCompanionView(store: store)
        let limited = DVKPrivacyLimitedView(onReauthorize: {})
        let waveform = DVKPlaybackAmplitudeView(amplitude: 0.5, reduceMotion: true)
        _ = AnyView(startup)
        _ = AnyView(main)
        _ = AnyView(limited)
        _ = AnyView(waveform)
        XCTAssertEqual(store.mode, .text)
    }

    @MainActor
    func testReviewDetailExposesDeleteContract() {
        let review = DVKCompanionReview(sessionKey: "ui-contract", title: "Review", startedAt: Date(), endedAt: Date(), duration: 0, summary: "Summary")
        let detail = DVKReviewDetailView(review: review, onDelete: {}, onClose: {})
        _ = AnyView(detail)
        XCTAssertEqual(DVKCompanionAccessibilityID.reviewDelete, "companion.reviewDelete")
    }
}
#endif
