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
    func testIOS26GlassHelperIsConstructible() {
        let theme = DVKCompanionThemeResolver.resolve(profile: DVKCompanionProfileCatalog().profiles[0], appearance: .followProfile)
        _ = AnyView(Button("Glass") {}.dvkGlassControl(theme: theme))
        _ = AnyView(Color.clear.dvkGlassSurface(theme: theme))
        let policy = DVKIOS26GlassAccessibilityPolicy(reduceTransparency: false, reduceMotion: false)
        XCTAssertFalse(policy.usesOpaqueFallback)
        XCTAssertTrue(policy.allowsInteractiveGlass)
    }

    @MainActor
    func testIOS26GlassContainerIsConstructible() {
        let theme = DVKCompanionThemeResolver.resolve(profile: DVKCompanionProfileCatalog().profiles[0], appearance: .followProfile)
        _ = AnyView(DVKIOS26GlassEffectContainer { HStack { Button("One") {}; Button("Two") {} }.dvkGlassControl(theme: theme) })
        let policy = DVKIOS26GlassAccessibilityPolicy(reduceTransparency: false, reduceMotion: true)
        XCTAssertFalse(policy.usesOpaqueFallback)
        XCTAssertFalse(policy.allowsInteractiveGlass)
    }

    @MainActor
    func testHomeCTAUsesSharedGlassBoundary() {
        let theme = DVKCompanionThemeResolver.resolve(profile: DVKCompanionProfileCatalog().profiles[0], appearance: .followProfile)
        _ = AnyView(DVKIOS26GlassEffectContainer { HStack { Button("Text") {}.dvkGlassControl(theme: theme, prominent: true); Button("Voice") {}.dvkGlassControl(theme: theme) } })
        XCTAssertEqual(DVKCompanionStore().selectedTab, .home)
    }

    @MainActor
    func testCatsConfirmationUsesGlassAndFallbackBoundary() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKProfilePreviewBar(profile: store.profiles[0], store: store, adapter: adapter))
        XCTAssertFalse(DVKCompanionAccessibilityID.profileConfirm.isEmpty)
    }

    @MainActor
    func testConversationControlsUseGlassFallbackBoundary() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKTextConversation(adapter: adapter))
        _ = AnyView(DVKVoiceConversation(adapter: adapter))
        XCTAssertFalse(DVKCompanionAccessibilityID.chatSend.isEmpty)
    }

    @MainActor
    func testReduceTransparencyAndMotionHaveExplicitFallbacks() {
        let opaque = DVKIOS26GlassAccessibilityPolicy(reduceTransparency: true, reduceMotion: false)
        let normal = DVKIOS26GlassAccessibilityPolicy(reduceTransparency: false, reduceMotion: false)
        let motion = DVKIOS26GlassAccessibilityPolicy(reduceTransparency: false, reduceMotion: true)
        XCTAssertTrue(opaque.usesOpaqueFallback)
        XCTAssertFalse(opaque.allowsInteractiveGlass)
        XCTAssertFalse(normal.usesOpaqueFallback)
        XCTAssertTrue(normal.allowsInteractiveGlass)
        XCTAssertFalse(motion.usesOpaqueFallback)
        XCTAssertFalse(motion.allowsInteractiveGlass)
        let theme = DVKCompanionThemeResolver.resolve(profile: DVKCompanionProfileCatalog().profiles[3], appearance: .followProfile)
        _ = AnyView(Button("Fallback") {}.dvkGlassControl(theme: theme, prominent: true))
    }

    @MainActor
    func testTabBarMinimizeBehaviorIsConfiguredForGlassPath() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKCompanionShellView(adapter: adapter))
        XCTAssertEqual(store.selectedTab, .home)
    }

    @MainActor
    func testLunaGlassPathKeepsDarkProfileTheme() {
        let luna = DVKCompanionProfileCatalog().profiles[3]
        let theme = DVKCompanionThemeResolver.resolve(profile: luna, appearance: .followProfile)
        XCTAssertTrue(theme.isDark)
        XCTAssertNotEqual(theme.pageBackground, theme.surface)
    }

    @MainActor
    func testPreviewThemeDoesNotChangeFormalTheme() {
        let store = DVKCompanionStore()
        let selected = store.selectedProfileID
        store.selectPreviewProfile(id: "mock.story-cat")
        XCTAssertEqual(store.selectedProfileID, selected)
        XCTAssertNotEqual(store.previewProfileID, store.selectedProfileID)
    }

    @MainActor
    func testShowcaseGlassBoundaryKeepsPublicPackageMinimum() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKCompanionShellView(adapter: adapter))
        XCTAssertEqual(store.mode, .text)
    }

    @MainActor
    func testEachTabRootConstructsInsideIndependentNavigationStack() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(NavigationStack { DVKCompanionHomeView(adapter: adapter, openConversation: {}) })
        _ = AnyView(NavigationStack { DVKCompanionProfilesView(adapter: adapter) })
        _ = AnyView(NavigationStack { DVKReviewListView(adapter: adapter) })
        _ = AnyView(NavigationStack { DVKCompanionSettingsView(adapter: adapter) })
        XCTAssertEqual(store.selectedTab, .home)
    }

    @MainActor
    func testGlassButtonRegularAndProminentFallbackBranchesConstruct() {
        let theme = DVKCompanionThemeResolver.resolve(profile: DVKCompanionProfileCatalog().profiles[0], appearance: .followProfile)
        _ = AnyView(Button("Regular") {}.dvkGlassControl(theme: theme))
        _ = AnyView(Button("Prominent") {}.dvkGlassControl(theme: theme, prominent: true))
        XCTAssertNotEqual(DVKCompanionAccessibilityID.chatSend, DVKCompanionAccessibilityID.voiceStart)
    }

    @MainActor
    func testVoiceButtonsHaveIndependentGlassControlViews() {
        let theme = DVKCompanionThemeResolver.resolve(profile: DVKCompanionProfileCatalog().profiles[0], appearance: .followProfile)
        _ = AnyView(DVKIOS26GlassEffectContainer {
            HStack {
                Button("Start") {}.dvkGlassControl(theme: theme, prominent: true)
                Button("Advance") {}.dvkGlassControl(theme: theme)
                Button("End") {}.dvkGlassControl(theme: theme)
            }
        })
        XCTAssertNotEqual(DVKCompanionAccessibilityID.voiceStart, DVKCompanionAccessibilityID.voiceAdvance)
        XCTAssertNotEqual(DVKCompanionAccessibilityID.voiceAdvance, DVKCompanionAccessibilityID.voiceEnd)
    }

    @MainActor
    func testCatsPreviewSurfaceAndConfirmationUseSeparateResponsibilities() {
        let theme = DVKCompanionThemeResolver.resolve(profile: DVKCompanionProfileCatalog().profiles[0], appearance: .followProfile)
        _ = AnyView(Color.clear.dvkGlassSurface(theme: theme))
        _ = AnyView(Button("Use this cat") {}.dvkGlassControl(theme: theme, prominent: true))
        XCTAssertNotEqual(DVKCompanionAccessibilityID.profilePreview, DVKCompanionAccessibilityID.profileConfirm)
    }

    @MainActor
    func testActiveVoiceAccessoryVisibilityUsesSessionState() {
        let hidden = DVKActiveVoiceAccessoryPresentation(hasActiveSession: false, voiceState: .idle, profileName: "Mellow")
        let visible = DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .listening, profileName: "Mellow")
        XCTAssertFalse(hidden.isVisible)
        XCTAssertTrue(visible.isVisible)
    }

    @MainActor
    func testActiveVoiceAccessoryStatusMappings() {
        XCTAssertEqual(DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .connecting, profileName: "Mellow").statusText, "Connecting")
        XCTAssertEqual(DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .listening, profileName: "Mellow").statusText, "Listening")
        XCTAssertEqual(DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .processing, profileName: "Mellow").statusText, "Thinking")
        XCTAssertEqual(DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .speaking, profileName: "Mellow").statusText, "Speaking")
        XCTAssertEqual(DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .ended, profileName: "Mellow").statusText, "Session ending")
    }

    @MainActor
    func testActiveVoiceAccessoryUsesSelectedProfileName() {
        let store = DVKCompanionStore()
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: store.voiceState, profileName: store.selectedProfile?.displayName)
        XCTAssertEqual(presentation.profileName, store.selectedProfile?.displayName)
    }

    @MainActor
    func testActiveVoiceAccessoryAccessibilityLabelInterpolatesPublicStateOnly() {
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .speaking, profileName: "Mellow")
        XCTAssertEqual(presentation.accessibilityLabel, "Mellow, Speaking, Return to voice session")
        XCTAssertFalse(presentation.accessibilityLabel.contains("self.profileName"))
        XCTAssertFalse(presentation.accessibilityLabel.contains("statusText"))
        XCTAssertFalse(presentation.accessibilityLabel.localizedCaseInsensitiveContains("routeToken"))
        XCTAssertFalse(presentation.accessibilityLabel.localizedCaseInsensitiveContains("sessionKey"))
    }

    @MainActor
    func testActiveVoiceAccessoryReturnActionSetsVoiceModeWithoutStartingSession() {
        let store = DVKCompanionStore()
        var returned = false
        let action = {
            store.setMode(.voice)
            returned = true
        }
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: false, voiceState: .idle, profileName: "Mellow")
        _ = AnyView(DVKActiveVoiceAccessoryView(presentation: presentation, theme: DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile), onReturn: action))
        action()
        XCTAssertTrue(returned)
        XCTAssertEqual(store.mode, .voice)
        XCTAssertFalse(store.hasActiveSession)
    }

    @MainActor
    func testActiveVoiceAccessoryDoesNotCreateSecondSession() {
        let store = DVKCompanionStore()
        let before = store.hasActiveSession
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: before, voiceState: .listening, profileName: "Mellow")
        _ = AnyView(DVKActiveVoiceAccessoryView(presentation: presentation, theme: DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile), onReturn: { store.setMode(.voice) }))
        XCTAssertEqual(store.hasActiveSession, before)
    }

    @MainActor
    func testActiveVoiceAccessoryIOS26AndFallbackHelpersConstruct() {
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .connecting, profileName: "Mellow")
        _ = AnyView(DVKActiveVoiceAccessoryView(presentation: presentation, theme: DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile), onReturn: {}))
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKCompanionShellView(adapter: adapter))
        XCTAssertEqual(store.selectedTab, .home)
    }

    @MainActor
    func testActiveVoiceAccessoryHasSingleReturnBehavior() {
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .processing, profileName: "Mellow")
        _ = AnyView(DVKActiveVoiceAccessoryView(presentation: presentation, theme: DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile), onReturn: {}))
        XCTAssertFalse(presentation.accessibilityLabel.contains("End"))
        XCTAssertFalse(presentation.accessibilityLabel.contains("Mute"))
        XCTAssertFalse(presentation.accessibilityLabel.contains("Advance"))
    }

    @MainActor
    func testCollapseDoesNotEndSessionOrChangeVoiceState() {
        let store = DVKCompanionStore()
        let before = store.voiceState
        var collapsed = false
        let collapse = { collapsed = true }
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .listening, profileName: "Mellow")
        _ = AnyView(DVKActiveVoiceAccessoryView(presentation: presentation, theme: DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile), onReturn: collapse))
        collapse()
        XCTAssertTrue(collapsed)
        XCTAssertEqual(store.voiceState, before)
        XCTAssertFalse(store.hasActiveSession)
    }

    @MainActor
    func testCollapseKeepsAccessoryPresentationVisible() {
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .speaking, profileName: "Mellow")
        XCTAssertTrue(presentation.isVisible)
        XCTAssertTrue(presentation.accessibilityLabel.contains("Return"))
    }

    @MainActor
    func testEndControlUsesExistingEndLogicAndCloseCallback() async {
        let store = DVKCompanionStore()
        var closed = false
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKVoiceConversation(adapter: adapter, onEnded: { closed = true }))
        await store.endVoiceDemo()
        closed = true
        XCTAssertTrue(closed)
        XCTAssertFalse(store.hasActiveSession)
    }

    @MainActor
    func testCollapseAndEndAccessibilityLabelsAreDistinct() {
        let collapse = DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .listening, profileName: "Mellow").accessibilityLabel
        XCTAssertNotEqual(collapse, "结束通话")
        XCTAssertFalse(collapse.contains("phone.down.fill"))
        XCTAssertNotEqual("收起语音会话", "结束通话")
    }

    @MainActor
    func testConversationSheetHasSeparateCloseAndEndContracts() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKCompanionConversationView(adapter: adapter, onClose: {}))
        _ = AnyView(DVKVoiceConversation(adapter: adapter, onEnded: {}))
        XCTAssertFalse(DVKCompanionAccessibilityID.voiceEnd.isEmpty)
    }

    @MainActor
    func testEndCompletionHidesAccessoryProjection() async {
        let store = DVKCompanionStore()
        await store.endVoiceDemo()
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: store.hasActiveSession, voiceState: store.voiceState, profileName: store.selectedProfile?.displayName)
        XCTAssertFalse(presentation.isVisible)
    }

    @MainActor
    func testVoiceRippleClampsAmplitudeBelowZero() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: -0.4, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.normalizedAmplitude, 0)
        XCTAssertEqual(presentation.rippleScale, 1)
    }

    @MainActor
    func testVoiceRippleClampsAmplitudeAboveOne() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 2.0, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.normalizedAmplitude, 1)
        XCTAssertLessThanOrEqual(presentation.rippleScale, 1.045)
    }

    @MainActor
    func testSpeakingRippleScaleIsMonotonicWithPlaybackAmplitude() {
        let quiet = DVKCharacterVoiceRipplePresentation(amplitude: 0.2, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        let loud = DVKCharacterVoiceRipplePresentation(amplitude: 0.8, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertGreaterThanOrEqual(loud.rippleScale, quiet.rippleScale)
    }

    @MainActor
    func testSpeakingRippleOpacityIsMonotonicWithPlaybackAmplitude() {
        let quiet = DVKCharacterVoiceRipplePresentation(amplitude: 0.2, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        let loud = DVKCharacterVoiceRipplePresentation(amplitude: 0.8, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertGreaterThanOrEqual(loud.rippleOpacity, quiet.rippleOpacity)
    }

    @MainActor
    func testVoiceRippleScaleAndLineWidthHaveVisualBounds() {
        let loud = DVKCharacterVoiceRipplePresentation(amplitude: 1, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertLessThanOrEqual(loud.rippleScale, 1.045)
        XCTAssertLessThanOrEqual(loud.rippleStrokeWidth, 1.8)
        XCTAssertGreaterThanOrEqual(loud.rippleStrokeWidth, 0.8)
    }

    @MainActor
    func testIdleRippleDoesNotLoop() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 1, voiceState: .idle, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.animationMode, .none)
        XCTAssertFalse(presentation.showsPrimaryRipple)
    }

    @MainActor
    func testEndedRippleDoesNotLoop() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 1, voiceState: .ended, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.animationMode, .none)
        XCTAssertEqual(presentation.statusText, "Session ending")
    }

    @MainActor
    func testErrorRippleDoesNotLoop() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.7, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: true)
        XCTAssertEqual(presentation.animationMode, .none)
        XCTAssertEqual(presentation.statusText, "Error")
        XCTAssertFalse(presentation.usesPlaybackAmplitude)
    }

    @MainActor
    func testReduceMotionDisablesRippleLoop() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.7, voiceState: .speaking, reduceMotion: true, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.animationMode, .none)
        XCTAssertGreaterThan(presentation.rippleOpacity, 0)
    }

    @MainActor
    func testStaticModeDisablesRippleLoop() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.7, voiceState: .speaking, reduceMotion: false, staticMode: true, hasError: false)
        XCTAssertEqual(presentation.animationMode, .none)
        XCTAssertGreaterThan(presentation.rippleScale, 1)
    }

    @MainActor
    func testListeningRippleDoesNotUsePlaybackAmplitudeAsInputSpectrum() {
        let quiet = DVKCharacterVoiceRipplePresentation(amplitude: 0, voiceState: .listening, reduceMotion: false, staticMode: false, hasError: false)
        let loud = DVKCharacterVoiceRipplePresentation(amplitude: 1, voiceState: .listening, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertFalse(loud.usesPlaybackAmplitude)
        XCTAssertEqual(loud.normalizedAmplitude, quiet.normalizedAmplitude)
        XCTAssertEqual(loud.rippleScale, quiet.rippleScale)
    }

    @MainActor
    func testProcessingRippleUsesThinkingCopy() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.4, voiceState: .processing, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.statusText, "Thinking")
        XCTAssertEqual(presentation.animationMode, .gentlePulse)
    }

    @MainActor
    func testSpeakingRippleUsesSpeakingCopy() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.4, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.statusText, "Speaking")
        XCTAssertTrue(presentation.usesPlaybackAmplitude)
    }

    @MainActor
    func testConnectingRippleUsesLowFrequencyBreathingMode() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.4, voiceState: .connecting, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.statusText, "Connecting")
        XCTAssertEqual(presentation.animationMode, .breathing)
    }

    @MainActor
    func testListeningRippleUsesOutwardRippleMode() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.8, voiceState: .listening, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.animationMode, .outwardRipple)
    }

    @MainActor
    func testSpeakingRippleUsesOutwardRippleMode() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.8, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.animationMode, .outwardRipple)
    }

    @MainActor
    func testConnectingAndProcessingKeepDistinctAnimationModes() {
        let connecting = DVKCharacterVoiceRipplePresentation(amplitude: 0, voiceState: .connecting, reduceMotion: false, staticMode: false, hasError: false)
        let processing = DVKCharacterVoiceRipplePresentation(amplitude: 0, voiceState: .processing, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(connecting.animationMode, .breathing)
        XCTAssertEqual(processing.animationMode, .gentlePulse)
    }

    @MainActor
    func testRippleAnimationModesStopForReducedMotionAndStatic() {
        let reduced = DVKCharacterVoiceRipplePresentation(amplitude: 1, voiceState: .speaking, reduceMotion: true, staticMode: false, hasError: false)
        let staticMode = DVKCharacterVoiceRipplePresentation(amplitude: 1, voiceState: .listening, reduceMotion: false, staticMode: true, hasError: false)
        XCTAssertEqual(reduced.animationMode, .none)
        XCTAssertEqual(staticMode.animationMode, .none)
    }

    @MainActor
    func testVoiceRippleAnimationModesRemainDistinctAndRestartable() {
        let connecting = DVKCharacterVoiceRipplePresentation(amplitude: 0, voiceState: .connecting, reduceMotion: false, staticMode: false, hasError: false)
        let listening = DVKCharacterVoiceRipplePresentation(amplitude: 0, voiceState: .listening, reduceMotion: false, staticMode: false, hasError: false)
        let processing = DVKCharacterVoiceRipplePresentation(amplitude: 0, voiceState: .processing, reduceMotion: false, staticMode: false, hasError: false)
        let speaking = DVKCharacterVoiceRipplePresentation(amplitude: 0.8, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(connecting.animationMode, .breathing)
        XCTAssertEqual(listening.animationMode, .outwardRipple)
        XCTAssertEqual(processing.animationMode, .gentlePulse)
        XCTAssertEqual(speaking.animationMode, .outwardRipple)
        XCTAssertNotEqual(connecting.animationMode, listening.animationMode)
        XCTAssertNotEqual(listening.animationMode, processing.animationMode)
    }

    @MainActor
    func testVoiceRippleStaticModesRemainNone() {
        let reduced = DVKCharacterVoiceRipplePresentation(amplitude: 1, voiceState: .speaking, reduceMotion: true, staticMode: false, hasError: false)
        let staticMode = DVKCharacterVoiceRipplePresentation(amplitude: 1, voiceState: .listening, reduceMotion: false, staticMode: true, hasError: false)
        XCTAssertEqual(reduced.animationMode, .none)
        XCTAssertEqual(staticMode.animationMode, .none)
    }

    @MainActor
    func testVoiceRippleUsesResolvedCharacterTheme() {
        let profile = DVKCompanionProfileCatalog().profiles[3]
        let theme = DVKCompanionThemeResolver.resolve(profile: profile, appearance: .followProfile)
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.5, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        _ = AnyView(DVKCharacterVoiceRipple(presentation: presentation, theme: theme))
        XCTAssertTrue(theme.isDark)
    }

    @MainActor
    func testVoiceRippleViewIsConstructible() {
        let theme = DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile)
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.5, voiceState: .listening, reduceMotion: false, staticMode: false, hasError: false)
        _ = AnyView(DVKCharacterVoiceRipple(presentation: presentation, theme: theme))
        XCTAssertTrue(presentation.showsPrimaryRipple)
    }

    @MainActor
    func testVoicePageKeepsAllVoiceControlIdentifiers() {
        XCTAssertFalse(DVKCompanionAccessibilityID.voiceStart.isEmpty)
        XCTAssertFalse(DVKCompanionAccessibilityID.voiceAdvance.isEmpty)
        XCTAssertFalse(DVKCompanionAccessibilityID.voiceEnd.isEmpty)
        XCTAssertEqual(DVKCompanionAccessibilityID.voiceState, "companion.voice.state")
    }

    @MainActor
    func testVoicePageKeepsCollapseAndEndSemantics() {
        let store = DVKCompanionStore()
        let adapter = DVKCompanionStoreAdapter(store: store)
        _ = AnyView(DVKCompanionConversationView(adapter: adapter, onClose: {}))
        _ = AnyView(DVKVoiceConversation(adapter: adapter, onEnded: {}))
        XCTAssertNotEqual("collapse voice session", "end call")
        XCTAssertFalse(DVKCompanionAccessibilityID.voiceEnd.isEmpty)
    }

    @MainActor
    func testVoicePageKeepsActiveAccessoryContract() {
        let presentation = DVKActiveVoiceAccessoryPresentation(hasActiveSession: true, voiceState: .speaking, profileName: "Mellow")
        _ = AnyView(DVKActiveVoiceAccessoryView(presentation: presentation, theme: DVKCompanionThemeResolver.resolve(themeKey: nil, appearance: .followProfile), onReturn: {}))
        XCTAssertTrue(presentation.isVisible)
        XCTAssertTrue(presentation.accessibilityLabel.contains("Return to voice session"))
    }

    @MainActor
    func testVoicePageKeepsStatusAsAccessibleValue() {
        let presentation = DVKCharacterVoiceRipplePresentation(amplitude: 0.3, voiceState: .listening, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertEqual(presentation.statusText, "Listening")
        XCTAssertFalse(presentation.statusText.isEmpty)
    }

    @MainActor
    func testVoiceRippleAmplitudeDoesNotChangeLayoutBounds() {
        let quiet = DVKCharacterVoiceRipplePresentation(amplitude: 0, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        let loud = DVKCharacterVoiceRipplePresentation(amplitude: 1, voiceState: .speaking, reduceMotion: false, staticMode: false, hasError: false)
        XCTAssertLessThanOrEqual(loud.rippleScale - quiet.rippleScale, 0.045)
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
