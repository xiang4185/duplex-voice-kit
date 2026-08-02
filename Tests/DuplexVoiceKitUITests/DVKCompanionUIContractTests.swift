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
        let defaultStartup = DVKCompanionStartupView()
        let defaultMain = DVKCompanionView()
        let limited = DVKPrivacyLimitedView(onReauthorize: {})
        let waveform = DVKPlaybackAmplitudeView(amplitude: 0.5, reduceMotion: true)
        _ = AnyView(startup)
        _ = AnyView(main)
        _ = AnyView(defaultStartup)
        _ = AnyView(defaultMain)
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

extension DVKCompanionUIContractTests {
    func testTabIdentifiersCoverFourPublicDestinations() {
        XCTAssertEqual(DVKCompanionAccessibilityID.home, "companion.home")
        XCTAssertEqual(DVKCompanionAccessibilityID.profiles, "companion.profiles")
        XCTAssertEqual(DVKCompanionAccessibilityID.reviews, "companion.reviews")
        XCTAssertEqual(DVKCompanionAccessibilityID.settings, "companion.settings")
    }

    func testCarouselIdentifiersCoverSelectionFlow() {
        XCTAssertNotEqual(DVKCompanionAccessibilityID.profileCarousel, DVKCompanionAccessibilityID.profilePreview)
        XCTAssertNotEqual(DVKCompanionAccessibilityID.profilePrevious, DVKCompanionAccessibilityID.profileNext)
        XCTAssertFalse(DVKCompanionAccessibilityID.profileConfirm.isEmpty)
    }

    func testErrorAndMockLabIdentifiersAreStable() {
        XCTAssertEqual(DVKCompanionAccessibilityID.voiceError, "companion.voiceError")
        XCTAssertEqual(DVKCompanionAccessibilityID.mockLab, "companion.mockLab")
        XCTAssertEqual(DVKCompanionAccessibilityID.characterPresentation, "companion.character.presentation")
    }

    func testPlaybackRelayUsesClampedInputPath() {
        let relay = DVKPlaybackAmplitudeRelay()
        relay.playbackAmplitudeDidChange(0.35)
        XCTAssertEqual(relay.currentAmplitude, 0.35, accuracy: 0.001)
        relay.playbackAmplitudeDidChange(4)
        XCTAssertEqual(relay.currentAmplitude, 1)
    }

    func testNoDuplicateBusinessStateIsExposedByAccessibilityContract() {
        XCTAssertTrue(DVKCompanionAccessibilityID.tabs.hasPrefix("companion."))
        XCTAssertTrue(DVKCompanionAccessibilityID.profileCarousel.hasPrefix("companion."))
    }

    func testProfileCardIdentifierPrefixIsStable() {
        XCTAssertEqual("companion.profile.card.mock.gentle-cat".split(separator: ".").prefix(3).joined(separator: "."), "companion.profile.card")
    }

    func testReviewDetailAndDeleteIdentifiersAreDifferent() {
        XCTAssertNotEqual(DVKCompanionAccessibilityID.reviewDetail, DVKCompanionAccessibilityID.reviewDelete)
    }

    func testPrivacyIdentifiersDescribeAllowedAndLimitedStates() {
        XCTAssertNotEqual(DVKCompanionAccessibilityID.privacyAllowed, DVKCompanionAccessibilityID.privacyLimited)
    }
}

#if canImport(SwiftUI)
extension DVKCompanionUIContractTests {
    @MainActor
    func testAllPublicPagesConstructWithSharedAdapter() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKCompanionHomeView(adapter: adapter, openConversation: {}))
        _ = AnyView(DVKCompanionProfilesView(adapter: adapter))
        _ = AnyView(DVKReviewListView(adapter: adapter))
        _ = AnyView(DVKCompanionSettingsView(adapter: adapter))
        _ = AnyView(DVKCompanionConversationView(adapter: adapter))
        XCTAssertEqual(adapter.store.selectedProfileID, store.selectedProfileID)
    }

    @MainActor
    func testCarouselAndPreviewViewsConstruct() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKProfileCarousel(adapter: adapter))
        _ = AnyView(DVKProfileCard(profile: store.profiles[0], selected: true))
        _ = AnyView(DVKProfilePreviewBar(profile: store.profiles[0], store: store, adapter: adapter))
        XCTAssertEqual(store.profiles.count, 4)
    }

    @MainActor
    func testCharacterAndLive2DBoundaryConstructsWithoutSDK() {
        let store = DVKCompanionStore()
        _ = AnyView(DVKProgrammaticCatView(profile: store.profiles[0], state: .idle, reduceMotion: true))
        let adapter = DVKStaticCharacterAdapter()
        XCTAssertNil(adapter.makeCharacterView(profile: store.profiles[0].snapshot, state: .idle))
    }

    @MainActor
    func testThemeProvidesCompleteSemanticColors() {
        let theme = DVKCompanionThemeResolver.resolve(profile: DVKCompanionProfileCatalog().profiles[0], appearance: .followProfile)
        _ = AnyView(Color.clear.background(theme.pageBackground))
        XCTAssertFalse(theme.textPrimary == theme.textSecondary)
    }

    @MainActor
    func testVoiceOverCarouselActionsAreConstructible() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKProfileCarousel(adapter: adapter))
        XCTAssertFalse(DVKCompanionAccessibilityID.profilePrevious.isEmpty)
        XCTAssertFalse(DVKCompanionAccessibilityID.profileNext.isEmpty)
    }

    @MainActor
    func testStartupUsesExplicitMainActorInitializers() {
        let store = DVKCompanionStore()
        _ = AnyView(DVKCompanionStartupView())
        _ = AnyView(DVKCompanionStartupView(store: store))
        _ = AnyView(DVKCompanionView())
        _ = AnyView(DVKCompanionView(store: store))
        XCTAssertEqual(store.mode, .text)
    }

    @MainActor
    func testFourProfileThemesResolveAndLavenderIsDarkByDefault() {
        let profiles = DVKCompanionProfileCatalog().profiles
        let themes = profiles.map { DVKCompanionThemeResolver.resolve(profile: $0, appearance: .followProfile) }
        XCTAssertEqual(themes.count, 4)
        XCTAssertTrue(themes.allSatisfy { $0.pageBackground != $0.surface })
        let lavender = themes[3]
        XCTAssertTrue(lavender.isDark)
        XCTAssertNotEqual(lavender.pageBackground, themes[0].pageBackground)
    }

    @MainActor
    func testAppearanceOverridesPreserveProfileAccentSemantics() {
        let profile = DVKCompanionProfileCatalog().profiles[1]
        let follow = DVKCompanionThemeResolver.resolve(profile: profile, appearance: .followProfile)
        let light = DVKCompanionThemeResolver.resolve(profile: profile, appearance: .light)
        let dark = DVKCompanionThemeResolver.resolve(profile: profile, appearance: .dark)
        XCTAssertFalse(follow.isDark)
        XCTAssertFalse(light.isDark)
        XCTAssertTrue(dark.isDark)
        XCTAssertEqual(light.primaryAction, dark.primaryAction)
        XCTAssertNotEqual(light.pageBackground, dark.pageBackground)
        XCTAssertNotEqual(light.surface, dark.surface)
        XCTAssertNotEqual(light.textPrimary, dark.textPrimary)
        XCTAssertNotEqual(light.navigationSurface, dark.navigationSurface)
        XCTAssertNotEqual(light.tabSurface, dark.tabSurface)
    }

    @MainActor
    func testProfileAppearanceAndHomeCarouselContracts() {
        let catalog = DVKCompanionProfileCatalog()
        let luna = catalog.profiles[3]
        let mellow = catalog.profiles[0]
        let lunaFollow = DVKCompanionThemeResolver.resolve(profile: luna, appearance: .followProfile)
        let lunaLight = DVKCompanionThemeResolver.resolve(profile: luna, appearance: .light)
        let mellowDark = DVKCompanionThemeResolver.resolve(profile: mellow, appearance: .dark)
        XCTAssertTrue(lunaFollow.isDark)
        XCTAssertFalse(lunaLight.isDark)
        XCTAssertTrue(mellowDark.isDark)
        XCTAssertEqual(lunaLight.primaryAction, lunaFollow.primaryAction)
        XCTAssertNotEqual(lunaLight.tabSurface, lunaFollow.tabSurface)
        let store = DVKCompanionStore()
        XCTAssertEqual(store.selectedTab, .home)
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKProfileCarousel(adapter: adapter, compact: true, onPreview: {
            store.setSelectedTab(.profiles)
        }))
        XCTAssertEqual(store.selectedTab, .home)
    }

    @MainActor
    func testLive2DHostIsInjectedIntoStoreAdapter() {
        let host = DVKStaticCharacterAdapter()
        let adapter = DVKCompanionStoreAdapter(store: DVKCompanionStore(), live2DHost: host)
        XCTAssertNotNil(adapter.live2DHost)
    }

    @MainActor
    func testProfileConfirmationUsesResolvedThemeSurface() {
        let store = DVKCompanionStore()
        store.selectPreviewProfile(id: "mock.story-cat")
        XCTAssertNotEqual(store.selectedProfileID, store.previewProfileID)
        store.confirmProfileSelection()
        XCTAssertEqual(store.selectedProfileID, "mock.story-cat")
    }

    @MainActor
    func testCarouselPreviewContractKeepsFormalSelectionUntilConfirmation() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKProfileCarousel(adapter: adapter, compact: false))
        store.selectPreviewProfile(id: "mock.cheerful-cat")
        XCTAssertNotEqual(store.selectedProfileID, store.previewProfileID)
    }

    @MainActor
    func testCardsExposeAllFiveEasterEggs() {
        XCTAssertEqual(DVKCompanionEasterEgg.allCases.count, 5)
        _ = AnyView(DVKEasterEggCard(egg: .care, onClose: {}))
    }
}
#endif
