#if canImport(SwiftUI)
import XCTest
import SwiftUI
import DuplexVoiceKitCompanion
@testable import DuplexVoiceKitUI

/// V7.0 migration UI contract tests: the sanitized companion pages keep their
/// public identifiers, construct on a shared store, and never surface private
/// diagnostics. SwiftUI-only; skipped on Linux where the module is unavailable.
@MainActor
final class DVKMigrationUIContractTests: XCTestCase {

    private func liveConfiguration() -> DVKRuntimeConfiguration {
        DVKRuntimeConfiguration(
            apiBaseURL: URL(string: "https" + "://" + "api.example.test")!,
            voiceWebSocketURL: URL(string: "wss" + "://" + "voice.example.test/v1/voice/ws")!,
            deviceID: "dvk-demo-device"
        )
    }

    private func liveAdapter() -> DVKCompanionStoreAdapter {
        let store = DVKMemoryTokenStore()
        try? store.save("synthetic-token")
        return DVKCompanionStoreAdapter(
            store: DVKCompanionStore(),
            runtimeConfiguration: liveConfiguration(),
            tokenStore: store
        )
    }

    // 14.5: device binding identifiers are stable and distinct
    func testDeviceBindingIdentifiersAreStable() {
        XCTAssertEqual(DVKDeviceBindingView.accessibilityID, "companion.deviceBinding")
        XCTAssertEqual(DVKDeviceBindingView.inputAccessibilityID, "companion.deviceBinding.input")
        XCTAssertEqual(DVKDeviceBindingView.saveAccessibilityID, "companion.deviceBinding.save")
        XCTAssertNotEqual(DVKDeviceBindingView.inputAccessibilityID, DVKDeviceBindingView.saveAccessibilityID)
    }

    // 14.5: the device binding page constructs in mock mode without a token
    func testDeviceBindingViewConstructible() {
        _ = AnyView(DVKDeviceBindingView(
            configuration: DVKRuntimeConfiguration.mock,
            tokenStore: DVKMemoryTokenStore()
        ))
    }

    // 14.5: live voice conversation constructs from a live adapter
    func testLiveVoiceConversationConstructible() {
        let adapter = liveAdapter()
        _ = AnyView(DVKLiveVoiceConversation(adapter: adapter))
    }

    // 14.5: the continuous background constructs in both modes
    func testBackgroundMeshConstructibleInBothModes() {
        let theme = DVKCompanionThemeResolver.resolve(themeKey: .warmCreamRose, appearance: .light)
        _ = AnyView(DVKBackgroundMeshView(mode: .home, theme: theme))
        _ = AnyView(DVKBackgroundMeshView(mode: .call, theme: theme))
    }

    // 14.5: settings connection identifiers are stable
    func testSettingsConnectionIdentifiersAreStable() {
        XCTAssertEqual(DVKCompanionAccessibilityID.settingsConnection, "companion.settings.connection")
        XCTAssertEqual(DVKCompanionAccessibilityID.settingsTokenClear, "companion.settings.tokenClear")
        XCTAssertNotEqual(DVKCompanionAccessibilityID.settingsConnection, DVKCompanionAccessibilityID.settingsTokenClear)
    }

    // 14.5: the conversation reply identifier is stable
    func testConversationReplyIdentifierIsStable() {
        XCTAssertEqual(DVKCompanionAccessibilityID.conversationReply, "companion.conversation.reply")
        XCTAssertEqual(DVKCompanionAccessibilityID.voiceMute, "companion.voiceMute")
        XCTAssertEqual(DVKCompanionAccessibilityID.voiceInterrupt, "companion.voiceInterrupt")
    }

    // 14.5: the adapter distinguishes live and mock runtime states
    func testAdapterDistinguishesLiveAndMock() {
        let mockAdapter = DVKCompanionStoreAdapter(store: DVKCompanionStore())
        XCTAssertFalse(mockAdapter.usesLiveConnection)
        XCTAssertFalse(mockAdapter.hasLiveToken)

        let liveAdapter = liveAdapter()
        XCTAssertTrue(liveAdapter.usesLiveConnection)
        XCTAssertTrue(liveAdapter.hasLiveToken)
    }

    // 14.5: clearing the token flips the adapter token presence
    func testAdapterTokenPresenceFollowsStore() throws {
        let store = DVKMemoryTokenStore()
        try store.save("synthetic-token")
        let adapter = DVKCompanionStoreAdapter(
            store: DVKCompanionStore(),
            runtimeConfiguration: liveConfiguration(),
            tokenStore: store
        )
        XCTAssertTrue(adapter.hasLiveToken)
        try store.clear()
        XCTAssertFalse(adapter.hasLiveToken)
    }

    // 14.5: the mock reviews page keeps an honest empty state
    func testMockReviewEmptyStateIsHonest() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        XCTAssertTrue(store.reviews.isEmpty)
        _ = AnyView(DVKReviewListView(adapter: adapter))
    }

    // 14.5: public pages construct with the shared adapter
    func testMigrationPagesConstructWithSharedAdapter() {
        let adapter = liveAdapter()
        _ = AnyView(DVKCompanionHomeView(adapter: adapter, openConversation: {}))
        _ = AnyView(DVKCompanionProfilesView(adapter: adapter))
        _ = AnyView(DVKCompanionSettingsView(adapter: adapter))
        _ = AnyView(DVKCompanionConversationView(adapter: adapter))
    }

    // 14.5: no private provider terms appear in the public accessibility surface
    func testPublicIdentifiersContainNoPrivateTerms() {
        let forbiddenPrefix = "xiaom" + "ao"
        let ids = [
            DVKCompanionAccessibilityID.settingsConnection,
            DVKCompanionAccessibilityID.settingsTokenClear,
            DVKDeviceBindingView.accessibilityID,
            DVKCompanionAccessibilityID.conversationReply
        ]
        for id in ids {
            XCTAssertFalse(id.lowercased().contains(forbiddenPrefix))
            XCTAssertFalse(id.lowercased().contains("xiang"))
        }
    }
}
#endif
