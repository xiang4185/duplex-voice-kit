import DuplexVoiceKit
import DuplexVoiceKitCompanion

public enum DVKCompanionAccessibilityID {
    public static let startupInitializing="companion.startup.initializing"
    public static let tabs="companion.tabs"; public static let home="companion.home"; public static let profiles="companion.profiles"; public static let reviews="companion.reviews"; public static let settings="companion.settings"
    public static let profileCarousel="companion.profile.carousel"; public static let profilePreview="companion.profile.preview"; public static let profileConfirm="companion.profile.confirm"; public static let profilePrevious="companion.profile.previous"; public static let profileNext="companion.profile.next"
    public static let modePicker="companion.modePicker"; public static let chatInput="companion.chatInput"; public static let chatSend="companion.chatSend"; public static let chatSending="companion.chatSending"; public static let chatPlanFailure="companion.chatPlanFailure"; public static let chatRetry="companion.chatRetry"
    public static let voiceState="companion.voiceState"; public static let voiceStart="companion.voiceStart"; public static let voiceAdvance="companion.voiceAdvance"; public static let voiceEnd="companion.voiceEnd"; public static let voiceError="companion.voiceError"
    public static let privacyAllowed="companion.privacyAllowed"; public static let privacyLimited="companion.privacyLimited"; public static let reauthorize="companion.reauthorize"
    public static let cards="companion.cards"; public static let reviewList="companion.reviewList"; public static let reviewDetail="companion.reviewDetail"; public static let reviewDelete="companion.reviewDelete"; public static let mockLab="companion.mockLab"; public static let characterPresentation="companion.character.presentation"
    public static let homeSettings="companion.home.settings"; public static let homeStatus="companion.home.status"; public static let homePrimaryCTA="companion.home.cta"; public static let homeHistory="companion.home.history"
    public static let voiceMute="companion.voiceMute"; public static let voiceInterrupt="companion.voiceInterrupt"; public static let conversationReply="companion.conversation.reply"
    public static let settingsConnection="companion.settings.connection"; public static let settingsTokenClear="companion.settings.tokenClear"
}

#if canImport(SwiftUI)
import SwiftUI
import Combine

private let dvkTabBarBottomContentPadding: CGFloat = 96


@MainActor
public final class DVKCompanionStoreAdapter: ObservableObject {
    @Published public private(set) var revision=0
    public let store: DVKCompanionStore
    public let playbackAmplitudeRelay: DVKPlaybackAmplitudeRelay
    public let live2DHost: (any DVKLive2DCharacterHosting)?
    public let runtimeConfiguration: DVKRuntimeConfiguration
    public let tokenStore: any DVKTokenStoring
    public init(store:DVKCompanionStore, live2DHost:(any DVKLive2DCharacterHosting)? = nil, runtimeConfiguration:DVKRuntimeConfiguration = .mock, tokenStore:any DVKTokenStoring = DVKMemoryTokenStore()){ self.store=store; self.live2DHost=live2DHost; self.runtimeConfiguration=runtimeConfiguration; self.tokenStore=tokenStore; let relay=DVKPlaybackAmplitudeRelay(); playbackAmplitudeRelay=relay; relay.setOnChange{[weak self,weak store] value in Task{@MainActor in store?.receivePlaybackAmplitude(value);self?.refresh()} }; store.setPlaybackAmplitudeInput{[weak relay] value in relay?.playbackAmplitudeDidChange(value)} }
    public convenience init(){ self.init(store:DVKCompanionStore()) }
    public func refresh(){ store.receivePlaybackAmplitude(playbackAmplitudeRelay.currentAmplitude); revision += 1 }
    public var usesLiveConnection: Bool { runtimeConfiguration.mode == .live }
    public var hasLiveToken: Bool { !(tokenStore.load() ?? "").isEmpty }
}

@MainActor
public struct DVKCompanionStartupView: View {
    @StateObject private var adapter:DVKCompanionStoreAdapter
    public init(store:DVKCompanionStore){_adapter=StateObject(wrappedValue:DVKCompanionStoreAdapter(store:store))}
    public init(store:DVKCompanionStore, runtimeConfiguration:DVKRuntimeConfiguration, tokenStore:any DVKTokenStoring){_adapter=StateObject(wrappedValue:DVKCompanionStoreAdapter(store:store,runtimeConfiguration:runtimeConfiguration,tokenStore:tokenStore))}
    public init(){self.init(store:DVKCompanionStore())}
    public var body:some View {
        Group {
            if adapter.store.initializationState == .ready { DVKCompanionShellView(adapter:adapter) }
            else { VStack(spacing:16){ ProgressView(); Text("Preparing your local cat room").font(.headline); Text("A private, mock-only welcome.").font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityIdentifier(DVKCompanionAccessibilityID.startupInitializing).task{adapter.store.initializeLocally();adapter.refresh()} }
        }.foregroundStyle(DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).textPrimary)
        .background(DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).pageBackground.ignoresSafeArea())
        .preferredColorScheme(DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).isDark ? .dark : .light)
        .accessibilityIdentifier("companion.startup")
    }
}

@MainActor
public struct DVKCompanionView: View {
    @StateObject private var adapter: DVKCompanionStoreAdapter
    public init(store: DVKCompanionStore) { _adapter=StateObject(wrappedValue:DVKCompanionStoreAdapter(store:store)) }
    public init() { self.init(store:DVKCompanionStore()) }
    public var body: some View { DVKCompanionShellView(adapter:adapter) }
}

@MainActor
public struct DVKCompanionShellView: View {
    @ObservedObject private var adapter:DVKCompanionStoreAdapter
    @State private var conversation=false
    public init(adapter:DVKCompanionStoreAdapter){self.adapter=adapter}
    public var body:some View {
        let store = adapter.store
        let activeTheme = DVKCompanionThemeResolver.resolve(profile: store.selectedProfile, appearance: store.appearance)
        let activeVoiceAccessory = DVKActiveVoiceAccessoryPresentation(
            hasActiveSession: store.hasActiveSession,
            voiceState: store.voiceState,
            profileName: store.selectedProfile?.displayName
        )
        TabView(selection:Binding(get:{store.selectedTab},set:{store.setSelectedTab($0);adapter.refresh()})){
            NavigationStack {
                DVKCompanionHomeView(adapter:adapter,openConversation:{conversation=true})
                    .navigationTitle("Home")
            }.dvkIOS26NavigationChrome(theme: activeTheme).tabItem{Label("Home",systemImage:"house.fill")}.tag(DVKCompanionTab.home).accessibilityIdentifier(DVKCompanionAccessibilityID.home)
            NavigationStack {
                DVKCompanionProfilesView(adapter:adapter, openConversation:{conversation=true})
                    .navigationTitle("Cats")
            }.dvkIOS26NavigationChrome(theme: activeTheme).tabItem{Label("Cats",systemImage:"pawprint.fill")}.tag(DVKCompanionTab.profiles).accessibilityIdentifier(DVKCompanionAccessibilityID.profiles)
            NavigationStack {
                DVKReviewListView(adapter:adapter)
            }.dvkIOS26NavigationChrome(theme: activeTheme).tabItem{Label("Reviews",systemImage:"clock.arrow.circlepath")}.tag(DVKCompanionTab.reviews).accessibilityIdentifier(DVKCompanionAccessibilityID.reviews)
            NavigationStack {
                DVKCompanionSettingsView(adapter:adapter)
            }.dvkIOS26NavigationChrome(theme: activeTheme).tabItem{Label("Settings",systemImage:"slider.horizontal.3")}.tag(DVKCompanionTab.settings).accessibilityIdentifier(DVKCompanionAccessibilityID.settings)
        }.tint(DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).primaryAction)
        .foregroundStyle(DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).textPrimary)
        .background(DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).pageBackground.ignoresSafeArea())
        .dvkIOS26TabBar(theme: activeTheme)
        .preferredColorScheme(DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).isDark ? .dark : .light)
        .animation(store.reduceMotionPreview ? nil : .easeInOut(duration: 0.2), value: store.selectedProfileID)
        .dvkActiveVoiceAccessory(presentation: activeVoiceAccessory, theme: activeTheme) {
            store.setMode(.voice)
            conversation = true
            adapter.refresh()
        }
        .accessibilityIdentifier(DVKCompanionAccessibilityID.tabs)
        .sheet(isPresented:$conversation){NavigationStack{DVKCompanionConversationView(adapter:adapter, onClose: { conversation = false })}}
    }
}

@MainActor
enum DVKHomePresentation {
    static func primaryCTATitle(profileName: String?, hasActiveSession: Bool) -> String {
        if hasActiveSession { return "Return to conversation" }
        guard let name = profileName, !name.isEmpty else { return "Talk with your cat" }
        return "Talk with \(name)"
    }
}

@MainActor
private struct DVKHomeSettingsButton: View {
    let theme: DVKCompanionTheme
    let height: CGFloat
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .imageScale(.medium)
                .frame(width: height, height: height)
                .contentShape(Rectangle())
        }
        .dvkGlassControl(theme: theme)
        .frame(height: height)
        .accessibilityLabel("Open settings")
        .accessibilityIdentifier(DVKCompanionAccessibilityID.homeSettings)
    }
}

@MainActor
private struct DVKHomeCharacterCanvas: View {
    let profile: DVKCompanionProfile
    let state: DVKCompanionCharacterPresentationState
    let dimension: CGFloat
    let reduceMotion: Bool
    let staticMode: Bool
    let host: (any DVKLive2DCharacterHosting)?

    var body: some View {
        DVKCharacterPresentationView(
            profile: profile,
            state: state,
            reduceMotion: reduceMotion,
            staticMode: staticMode,
            host: staticMode ? nil : host
        )
        .frame(width: 250, height: 250)
        .scaleEffect(dimension / 250)
        .frame(width: dimension, height: dimension)
        .contentShape(Rectangle())
    }
}

@MainActor
private struct DVKHomeHistoryEntry: View {
    let profile: DVKCompanionProfile?
    let theme: DVKCompanionTheme
    let height: CGFloat
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let profile {
                    DVKHomeCharacterCanvas(
                        profile: profile,
                        state: .idle,
                        dimension: 40,
                        reduceMotion: true,
                        staticMode: true,
                        host: nil
                    )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversation history")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("Open public mock reviews")
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dvkGlassSurface(theme: theme)
        .dvkCardTopHighlight()
        .accessibilityLabel("Conversation history, Open public mock reviews")
        .accessibilityIdentifier(DVKCompanionAccessibilityID.homeHistory)
    }
}

@MainActor
public struct DVKCompanionHomeView: View {
    @ObservedObject private var adapter: DVKCompanionStoreAdapter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private let openConversation: () -> Void

    public init(
        adapter: DVKCompanionStoreAdapter,
        openConversation: @escaping () -> Void
    ) {
        self.adapter = adapter
        self.openConversation = openConversation
    }

    public var body: some View {
        let store = adapter.store
        let theme = DVKCompanionThemeResolver.resolve(
            profile: store.selectedProfile,
            appearance: store.appearance
        )

        GeometryReader { geometry in
            let availableHeight = geometry.size.height
            let compact = store.hasActiveSession || availableHeight < 580
            let topPadding: CGFloat = compact ? 8 : 16
            let settingsHeight: CGFloat = compact ? 40 : 44
            let settingsGap: CGFloat = compact ? 4 : 8
            let statusHeight: CGFloat = compact ? 18 : 22
            let nameHeight: CGFloat = compact ? 26 : 30
            let readyHeight: CGFloat = compact ? 16 : 18
            let ctaHeight: CGFloat = compact ? 48 : 54
            let textEntryHeight: CGFloat = compact ? 34 : 40
            let historyHeight: CGFloat = compact ? 52 : 60
            let innerSpacing: CGFloat = compact ? 8 : 12
            let nonCharacterBudget = statusHeight
                + nameHeight
                + readyHeight
                + ctaHeight
                + textEntryHeight
                + historyHeight
            let characterMaxHeight: CGFloat = compact ? 190 : 280
            let characterHeight = min(
                characterMaxHeight,
                max(0, availableHeight - topPadding - settingsHeight - settingsGap - nonCharacterBudget - innerSpacing * 5)
            )

            VStack(spacing: 0) {
                HStack {
                    DVKHomeSettingsButton(
                        theme: theme,
                        height: settingsHeight
                    ) {
                        store.setSelectedTab(.settings)
                        adapter.refresh()
                    }
                    Spacer()
                }
                .frame(height: settingsHeight)

                Spacer(minLength: settingsGap)

                VStack(spacing: innerSpacing) {
                    if let profile = store.selectedProfile {
                        // 中央大人物 Hero：halo 光晕 + 呼吸人物（尺寸/光晕/留白层级来自参考壳）
                        ZStack {
                            DVKCompanionHeroHalo(
                                color: theme.halo,
                                diameter: characterHeight,
                                reduceMotion: systemReduceMotion || store.reduceMotionPreview
                            )
                            DVKHomeCharacterCanvas(
                                profile: profile,
                                state: store.characterState,
                                dimension: characterHeight,
                                reduceMotion: systemReduceMotion || store.reduceMotionPreview,
                                staticMode: store.presentationMode == .staticFallback,
                                host: adapter.live2DHost
                            )
                        }
                        .frame(width: characterHeight, height: characterHeight)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.characterPresentation)

                        // 顶部轻量状态区：声呐点 + 迷你波形 + 在场文案
                        HStack(spacing: 8) {
                            DVKCompanionSonarDot(
                                color: theme.activeStatus,
                                diameter: 18,
                                reduceMotion: systemReduceMotion || store.reduceMotionPreview
                            )
                            Text("Here with you")
                                .font(.footnote)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(theme.textSecondary)
                            DVKCompanionMiniWave(
                                active: true,
                                color: theme.primaryAction,
                                reduceMotion: systemReduceMotion || store.reduceMotionPreview,
                                barCount: 5
                            )
                            .frame(width: 44, height: 14)
                            .opacity(0.75)
                        }
                        .frame(height: statusHeight)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.homeStatus)

                        // 宋体角色名 + 简短问候
                        Text(profile.displayName)
                            .font(DVKCompanionTypography.serifName(compact ? 26 : 30))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(theme.textPrimary)
                            .frame(height: nameHeight)

                        Text(profile.greeting)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(theme.textSecondary)
                            .frame(height: readyHeight)

                        // 主要对话入口（Voice）
                        primaryCTA(
                            title: DVKHomePresentation.primaryCTATitle(
                                profileName: profile.displayName,
                                hasActiveSession: store.hasActiveSession
                            ),
                            theme: theme,
                            height: ctaHeight
                        ) {
                            store.setMode(.voice)
                            adapter.refresh()
                            openConversation()
                        }

                        // 次要对话入口（Text）— 保留公共 Text 与 Voice 两条入口
                        textEntryButton(
                            theme: theme,
                            height: textEntryHeight
                        ) {
                            store.setMode(.text)
                            adapter.refresh()
                            openConversation()
                        }

                        // 回顾入口
                        DVKHomeHistoryEntry(
                            profile: profile,
                            theme: theme,
                            height: historyHeight
                        ) {
                            store.setSelectedTab(.reviews)
                            adapter.refresh()
                        }
                    } else {
                        ContentUnavailableView(
                            "Choose a cat",
                            systemImage: "pawprint.fill",
                            description: Text("Visit Cats to choose a public mock profile.")
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .background(DVKBackgroundMeshView(mode: .home, theme: theme))
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier(DVKCompanionAccessibilityID.home)
    }

    private func primaryCTA(
        title: String,
        theme: DVKCompanionTheme,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .dvkGlassControl(theme: theme, prominent: true)
        .accessibilityLabel(title)
        .accessibilityIdentifier(DVKCompanionAccessibilityID.homePrimaryCTA)
    }

    private func textEntryButton(
        theme: DVKCompanionTheme,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 14, weight: .medium))
                Text("Send a message")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Capsule())
        }
        .buttonStyle(DVKPressableButtonStyle())
        .dvkGlassControl(theme: theme)
        .accessibilityLabel("Send a message")
        .accessibilityIdentifier("companion.home.textEntry")
    }
}

@MainActor
public struct DVKCompanionProfilesView: View {
    @ObservedObject private var adapter: DVKCompanionStoreAdapter
    private let openConversation: () -> Void

    public init(
        adapter: DVKCompanionStoreAdapter,
        openConversation: @escaping () -> Void = {}
    ) {
        self.adapter = adapter
        self.openConversation = openConversation
    }

    public var body: some View {
        let store = adapter.store
        let theme = DVKCompanionThemeResolver.resolve(
            profile: store.previewProfile,
            appearance: store.appearance
        )

        GeometryReader { geometry in
            let usableHeight = max(
                0,
                geometry.size.height - dvkTabBarBottomContentPadding
            )
            let regularHeaderBudget: CGFloat = 96
            let regularFooterBudget: CGFloat = store.canSelectProfiles ? 56 : 88
            let regularSpacingBudget: CGFloat = 56
            let regularFixedBudget = regularHeaderBudget
                + regularFooterBudget
                + regularSpacingBudget
            let regularAvailableCarouselHeight = max(
                0,
                usableHeight - regularFixedBudget
            )
            let compact = regularAvailableCarouselHeight < 486
            let headerBudget: CGFloat = compact ? 80 : regularHeaderBudget
            let footerBudget: CGFloat = compact
                ? (store.canSelectProfiles ? 56 : 84)
                : regularFooterBudget
            let spacingBudget: CGFloat = compact ? 32 : regularSpacingBudget
            let fixedBudget = headerBudget + footerBudget + spacingBudget
            let availableCarouselHeight = max(
                0,
                usableHeight - fixedBudget
            )
            let carouselHeight = min(486, availableCarouselHeight)

            VStack(alignment: .leading, spacing: compact ? 8 : 14) {
                Text("Choose a cat")
                    .font(.system(
                        size: compact ? 28 : 32,
                        weight: .semibold,
                        design: .serif
                    ))
                Text("Four fictional public profiles. The choice is local and reversible.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)

                DVKRoleCardCarousel(
                    adapter: adapter,
                    carouselHeight: carouselHeight,
                    compact: compact
                )

                rolePrimaryAction(store: store, theme: theme)

                if !store.canSelectProfiles {
                    Text("Profile switching is paused while a message or voice session is active.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, compact ? 8 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .foregroundStyle(theme.textPrimary)
        .background(DVKBackgroundMeshView(mode: .home, theme: theme))
        .tint(theme.primaryAction)
        .accessibilityIdentifier(DVKCompanionAccessibilityID.profiles)
    }

    @ViewBuilder
    private func rolePrimaryAction(
        store: DVKCompanionStore,
        theme: DVKCompanionTheme
    ) -> some View {
        if let profile = store.previewProfile {
            let current = profile.id == store.selectedProfileID
            Button(
                DVKRoleSelectionActionPresentation.title(
                    previewProfileID: profile.id,
                    selectedProfileID: store.selectedProfileID
                )
            ) {
                if current {
                    openConversation()
                } else {
                    store.confirmProfileSelection()
                    adapter.refresh()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .dvkGlassControl(theme: theme, prominent: true)
            .disabled(
                current
                    ? store.selectedProfile == nil
                    : !store.canConfirmProfileSelection
            )
            .accessibilityIdentifier(DVKCompanionAccessibilityID.profileConfirm)
        }
    }
}

@MainActor
private struct DVKRoleCardCarouselItem: View {
    let profile: DVKCompanionProfile
    let selected: Bool
    let isPreview: Bool
    let reduced: Bool
    let width: CGFloat
    let canSelectProfiles: Bool
    let compact: Bool
    let onSelect: (String) -> Void

    var body: some View {
        DVKRoleLargeCard(
            profile: profile,
            selected: selected,
            isPreview: isPreview,
            reduced: reduced,
            compact: compact
        )
        .frame(width: width)
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            let amount = CGFloat(phase.value)
            let scale: CGFloat = reduced
                ? (phase.isIdentity ? 1 : 0.94)
                : 1 - min(abs(amount) * 0.06, 0.06)
            let opacity: Double = reduced
                ? (phase.isIdentity ? 1 : 0.82)
                : 1 - min(abs(phase.value) * 0.18, 0.18)
            let rotation: Double = reduced ? 0 : phase.value * -4
            let verticalOffset: CGFloat = reduced
                ? 0
                : min(abs(amount) * 6, 6)

            let scaledContent = content.scaleEffect(scale)
            let fadedContent = scaledContent.opacity(opacity)
            let rotatedContent = fadedContent.rotation3DEffect(
                .degrees(rotation),
                axis: (x: 0, y: 1, z: 0)
            )
            return rotatedContent.offset(y: verticalOffset)
        }
        .id(profile.id)
        .accessibilityIdentifier("companion.profile.card.\(profile.id)")
        .accessibilityLabel(profile.accessibilityDescription)
        .onTapGesture {
            guard canSelectProfiles else { return }
            onSelect(profile.id)
        }
    }
}

@MainActor
private struct DVKRoleCardCarousel: View {
    @ObservedObject private var adapter:DVKCompanionStoreAdapter
    let carouselHeight: CGFloat
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var scrollPosition:String?
    init(
        adapter: DVKCompanionStoreAdapter,
        carouselHeight: CGFloat,
        compact: Bool
    ) {
        self.adapter = adapter
        self.carouselHeight = carouselHeight
        self.compact = compact
    }
    var body:some View {
        let store=adapter.store
        let reduced=systemReduceMotion || store.reduceMotionPreview
        VStack(spacing:8) {
            GeometryReader { geometry in
            let width=min(geometry.size.width * 0.78,320)
            ScrollViewReader { proxy in
                ScrollView(.horizontal,showsIndicators:false) {
                    LazyHStack(spacing:16) {
                        ForEach(store.profiles) { profile in
                            DVKRoleCardCarouselItem(
                                profile: profile,
                                selected: profile.id == store.selectedProfileID,
                                isPreview: profile.id == store.previewProfileID,
                                reduced: reduced,
                                width: width,
                                canSelectProfiles: store.canSelectProfiles,
                                compact: compact
                            ) { id in
                                select(
                                    id,
                                    store: store,
                                    proxy: proxy,
                                    reduced: reduced
                                )
                            }
                        }
                    }.scrollTargetLayout().padding(.vertical,12)
                }
                .scrollTargetBehavior(.viewAligned)
                .coordinateSpace(name:"dvkRoleCarousel")
                .scrollPosition(id:$scrollPosition)
                .contentMargins(.horizontal,max((geometry.size.width-width)/2,0))
                .scrollDisabled(!store.canSelectProfiles)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.profileCarousel)
                .accessibilityActions {
                    Button("Previous cat"){move(-1,store,proxy)}
                    Button("Next cat"){move(1,store,proxy)}
                }
                .onAppear{scrollPosition=store.previewProfileID}
                .onChange(of:scrollPosition){_,id in
                    guard store.canSelectProfiles,let id else{return}
                    store.selectPreviewProfile(id:id);adapter.refresh()
                }
            }
            }
            .frame(height: carouselHeight)
        }
        .accessibilityIdentifier(DVKCompanionAccessibilityID.profilePreview)
    }
    private func select(
        _ id: String,
        store: DVKCompanionStore,
        proxy: ScrollViewProxy,
        reduced: Bool
    ) {
        guard store.canSelectProfiles else { return }
        store.selectPreviewProfile(id: id)
        scrollPosition = id
        adapter.refresh()

        if reduced {
            proxy.scrollTo(id, anchor: .center)
        } else {
            let animation: Animation = .snappy(duration: 0.32)
            withAnimation(animation) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func move(_ offset:Int,_ store:DVKCompanionStore,_ proxy:ScrollViewProxy) {
        guard store.canSelectProfiles,let index=store.profiles.firstIndex(where:{$0.id == store.previewProfileID}) else{return}
        let destination=index+offset
        guard store.profiles.indices.contains(destination) else{return}
        let id=store.profiles[destination].id
        store.selectPreviewProfile(id:id);scrollPosition=id;adapter.refresh()
        if systemReduceMotion || store.reduceMotionPreview {proxy.scrollTo(id,anchor:.center)}
        else {withAnimation(.snappy(duration:0.32)){proxy.scrollTo(id,anchor:.center)}}
    }
}
@MainActor
private struct DVKRoleLargeCard:View {
    let profile:DVKCompanionProfile
    let selected:Bool
    let isPreview:Bool
    let reduced:Bool
    let compact:Bool

    var body:some View {
        let theme=DVKCompanionThemeResolver.resolve(profile:profile,appearance:.followProfile)
        let avatarDimension: CGFloat = compact ? 154 : 228
        let characterAreaHeight: CGFloat = compact ? 170 : 246
        let cardPadding: CGFloat = compact ? 10 : 16
        let verticalSpacing: CGFloat = compact ? 6 : 10
        let markerHeight: CGFloat = compact ? 24 : 28

        VStack(spacing: verticalSpacing) {
            if selected {
                Text("Current cat")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, compact ? 11 : 14)
                    .padding(.vertical, compact ? 4 : 6)
                    .background(theme.elevatedSurface,in:Capsule())
                    .foregroundStyle(theme.primaryAction)
            } else {
                Color.clear.frame(height: markerHeight)
            }
            ZStack {
                // 角色渐变背景（上半，参考壳的卡片视觉语言）
                theme.primaryAction.opacity(0.10)
                    .frame(height: characterAreaHeight * 0.62)
                    .frame(maxWidth:.infinity)
                    .frame(maxHeight:.infinity,alignment:.top)
                    .clipShape(RoundedRectangle(cornerRadius:26,style:.continuous))
                // 角色 halo 光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors:[theme.primaryAction.opacity(0.26),theme.halo.opacity(0.14),.clear],
                            center:.center,
                            startRadius:40,
                            endRadius:130
                        )
                    )
                    .frame(width:characterAreaHeight * 1.15,height:characterAreaHeight * 1.15)
                RoundedRectangle(cornerRadius:24,style:.continuous)
                    .fill(theme.elevatedSurface)
                    .opacity(0.55)
                DVKRoleAvatar(
                    profile:profile,
                    dimension:avatarDimension,
                    reduced:reduced
                )
            }
            .frame(height: characterAreaHeight)
            Text(profile.displayName)
                .font(DVKCompanionTypography.serifName(compact ? 24 : 28))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            HStack(spacing:6) {
                ForEach(profile.personalityTags,id:\.self) {
                    Text($0)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, compact ? 7 : 9)
                        .padding(.vertical, compact ? 4 : 5)
                        .background(theme.primaryAction.opacity(0.10),in:Capsule())
                        .foregroundStyle(theme.primaryAction)
                }
            }
            .frame(maxWidth:.infinity)
            Text(profile.greeting)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing:6) {
                ForEach(profile.capabilities,id:\.self) {
                    Text($0.rawValue.capitalized)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, compact ? 6 : 7)
                        .padding(.vertical, compact ? 3 : 4)
                        .background(theme.surface,in:Capsule())
                }
            }
        }
        .padding(cardPadding)
        .frame(maxWidth:.infinity)
        .background(theme.surface,in:RoundedRectangle(cornerRadius:30,style:.continuous))
        .overlay(
            RoundedRectangle(cornerRadius:30,style:.continuous)
                .stroke(
                    isPreview ? theme.primaryAction : theme.border.opacity(0.4),
                    lineWidth:isPreview ? 2.5 : 1
                )
        )
        .dvkCardTopHighlight()
        .shadow(
            color:theme.shadow.opacity(isPreview ? 0.22 : 0.1),
            radius:isPreview ? 16 : 10,
            y:8
        )
        .accessibilityElement(children:.combine)
    }
}
private let dvkRoleAvatarCanvasSize:CGFloat = 250

@MainActor
private struct DVKRoleAvatar:View {
    let profile:DVKCompanionProfile;let dimension:CGFloat;let reduced:Bool
    var body:some View {
        GeometryReader { geometry in
            let center=geometry.frame(in:.named("dvkRoleCarousel")).midX
            let localCenter=geometry.size.width / 2
            let parallax:CGFloat=reduced ? 0:max(-8,min(8,(localCenter-center) * 0.08))
            DVKProgrammaticCatView(profile:profile,reduceMotion:reduced)
                .frame(width:dvkRoleAvatarCanvasSize,height:dvkRoleAvatarCanvasSize)
                .scaleEffect(dimension / dvkRoleAvatarCanvasSize)
                .frame(width:dimension,height:dimension)
                .offset(x:parallax)
                .clipShape(RoundedRectangle(cornerRadius:22,style:.continuous))
                .clipped()
                .contentShape(RoundedRectangle(cornerRadius:22,style:.continuous))
        }
        .frame(width:dimension,height:dimension)
    }
}
enum DVKRoleSelectionActionPresentation {
    static func title(previewProfileID:String?,selectedProfileID:String?)->String {
        previewProfileID == selectedProfileID ? "Start chat":"Use this cat"
    }
}

@MainActor
private struct DVKRoleSelectionBar:View {
    @ObservedObject var adapter:DVKCompanionStoreAdapter
    let openConversation:()->Void
    var body:some View {
        let store=adapter.store
        if let profile=store.previewProfile {
            let theme=DVKCompanionThemeResolver.resolve(profile:profile,appearance:store.appearance)
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12){DVKRoleAvatar(profile:profile,dimension:54,reduced:true);VStack(alignment:.leading,spacing:3){Text(profile.displayName).font(.headline).lineLimit(1);Text(profile.personalityTags.joined(separator:" · ")).font(.caption).lineLimit(1).foregroundStyle(theme.textSecondary)};Spacer(minLength:4);action(profile,store,theme)}.fixedSize(horizontal:true,vertical:false)
                VStack(alignment:.leading,spacing:10){HStack{DVKRoleAvatar(profile:profile,dimension:48,reduced:true);Text(profile.shortSummary).font(.caption).lineLimit(2).foregroundStyle(theme.textSecondary)};action(profile,store,theme).frame(maxWidth:.infinity)}
            }.padding(12).background(theme.elevatedSurface,in:RoundedRectangle(cornerRadius:22,style:.continuous)).overlay(RoundedRectangle(cornerRadius:22,style:.continuous).stroke(theme.border.opacity(0.5)))
        }
    }
    private func action(_ profile:DVKCompanionProfile,_ store:DVKCompanionStore,_ theme:DVKCompanionTheme)->some View {
        let current=profile.id == store.selectedProfileID
        return Button(DVKRoleSelectionActionPresentation.title(previewProfileID:profile.id,selectedProfileID:store.selectedProfileID)){if current{openConversation()}else{store.confirmProfileSelection();adapter.refresh()}}.lineLimit(1).fixedSize(horizontal:true,vertical:false).dvkGlassControl(theme:theme,prominent:true).disabled(current ? store.selectedProfile == nil:!store.canConfirmProfileSelection).accessibilityIdentifier(DVKCompanionAccessibilityID.profileConfirm)
    }
}
@MainActor
public struct DVKProfileCarousel: View {
    @ObservedObject private var adapter:DVKCompanionStoreAdapter
    private let compact:Bool
    private let onPreview:(()->Void)?
    @State private var scrollPosition:String?
    public init(adapter:DVKCompanionStoreAdapter,compact:Bool=false,onPreview:(()->Void)?=nil){self.adapter=adapter;self.compact=compact;self.onPreview=onPreview}
    public var body: some View {
        let store = adapter.store
        let theme = DVKCompanionThemeResolver.resolve(profile: store.previewProfile, appearance: store.appearance)
        let selectedIndex = store.profiles.firstIndex(where: { $0.id == store.previewProfileID }) ?? 0
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(store.profiles) { profile in
                            let selected = profile.id == store.previewProfileID
                            Button {
                                store.selectPreviewProfile(id: profile.id)
                                scrollPosition = profile.id
                                adapter.refresh()
                                onPreview?()
                                if !store.reduceMotionPreview {
                                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(profile.id, anchor: .center) }
                                } else {
                                    proxy.scrollTo(profile.id, anchor: .center)
                                }
                            } label: {
                                DVKProfileCard(profile: profile, selected: selected, compact: compact)
                            }
                            .id(profile.id)
                            .buttonStyle(.plain)
                            .disabled(!store.canSelectProfiles)
                            .accessibilityIdentifier("companion.profile.card.\(profile.id)")
                            .accessibilityLabel(profile.accessibilityDescription)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 8)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .scrollPosition(id: $scrollPosition)
                .contentMargins(.horizontal, compact ? 20 : 32)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.profileCarousel)
                .onAppear { scrollPosition = store.previewProfileID }
                .onChange(of: scrollPosition) { _, id in
                    if let id {
                        store.selectPreviewProfile(id: id)
                        adapter.refresh()
                    }
                }
                HStack {
                    Button("Previous cat") {
                        guard selectedIndex > 0 else { return }
                        let id = store.profiles[selectedIndex - 1].id
                        store.selectPreviewProfile(id: id)
                        scrollPosition = id
                        adapter.refresh()
                        onPreview?()
                        proxy.scrollTo(id, anchor: .center)
                    }
                    .disabled(!store.canSelectProfiles || selectedIndex == 0)
                    .dvkGlassControl(theme: theme)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.profilePrevious)
                    Spacer()
                    Button("Next cat") {
                        guard selectedIndex + 1 < store.profiles.count else { return }
                        let id = store.profiles[selectedIndex + 1].id
                        store.selectPreviewProfile(id: id)
                        scrollPosition = id
                        adapter.refresh()
                        onPreview?()
                        proxy.scrollTo(id, anchor: .center)
                    }
                    .disabled(!store.canSelectProfiles || selectedIndex + 1 >= store.profiles.count)
                    .dvkGlassControl(theme: theme)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.profileNext)
                }
                .font(.caption)
            }
        }
    }
}

@MainActor
public struct DVKProfileCard: View {
    public let profile:DVKCompanionProfile; public let selected:Bool; public let compact:Bool
    public init(profile:DVKCompanionProfile,selected:Bool,compact:Bool=false){self.profile=profile;self.selected=selected;self.compact=compact}
    public var body:some View { let theme=DVKCompanionThemeResolver.resolve(profile:profile, appearance:.followProfile)
        VStack(spacing:8){DVKProgrammaticCatView(profile:profile,reduceMotion:true).frame(height:compact ? 94:112);Text(profile.displayName).font(.headline).lineLimit(2).minimumScaleFactor(0.8);Text(profile.personalityTags.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2);HStack{ForEach(profile.capabilities,id:\.self){Text($0.rawValue.capitalized).font(.caption2).padding(.horizontal,6).padding(.vertical,3).background(.thinMaterial,in:Capsule())}}.lineLimit(1);if profile.availability != .available {Text("Unavailable").font(.caption2).foregroundStyle(.orange)}}.frame(width:compact ? 140:156,height:compact ? 160:190).padding(10).background(theme.surface,in:RoundedRectangle(cornerRadius:22,style:.continuous)).overlay(RoundedRectangle(cornerRadius:22).stroke(selected ? theme.primaryAction:.clear,lineWidth:selected ? 3:0)).scaleEffect(selected ? 1.02:0.96).shadow(color:selected ? theme.primaryAction.opacity(0.18):.clear,radius:14,y:6)
    }
}

@MainActor
public struct DVKProfilePreviewBar: View {
    let profile:DVKCompanionProfile; let store:DVKCompanionStore; @ObservedObject var adapter:DVKCompanionStoreAdapter
    public init(profile:DVKCompanionProfile,store:DVKCompanionStore,adapter:DVKCompanionStoreAdapter){self.profile=profile;self.store=store;self.adapter=adapter}
    public var body: some View {
        let theme = DVKCompanionThemeResolver.resolve(profile: profile, appearance: store.appearance)
        ViewThatFits(in: .horizontal) {
            previewWideLayout(theme: theme)
                .fixedSize(horizontal: true, vertical: false)
            previewCompactLayout(theme: theme)
        }
        .padding(12)
        .dvkGlassSurface(theme: theme)
        .accessibilityIdentifier(DVKCompanionAccessibilityID.profilePreview)
    }

    @ViewBuilder
    private func previewWideLayout(theme: DVKCompanionTheme) -> some View {
        HStack(spacing: 12) {
            DVKProgrammaticCatView(profile: profile, reduceMotion: true)
                .frame(width: 64, height: 64)
            previewSummary
            Spacer(minLength: 8)
            confirmButton(theme: theme)
        }
    }

    @ViewBuilder
    private func previewCompactLayout(theme: DVKCompanionTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DVKProgrammaticCatView(profile: profile, reduceMotion: true)
                    .frame(width: 56, height: 56)
                previewSummary
            }
            confirmButton(theme: theme)
                .frame(maxWidth: .infinity)
        }
    }

    private var previewSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Previewing \(profile.displayName)").font(.headline)
            Text(profile.shortSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func confirmButton(theme: DVKCompanionTheme) -> some View {
        Button("Use this cat") {
            store.confirmProfileSelection()
            adapter.refresh()
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .dvkGlassControl(theme: theme, prominent: true)
        .disabled(!store.canConfirmProfileSelection)
        .accessibilityIdentifier(DVKCompanionAccessibilityID.profileConfirm)
    }
}

@MainActor
public struct DVKCompanionConversationView: View {
    @ObservedObject private var adapter:DVKCompanionStoreAdapter
    private let onClose: () -> Void
    public init(adapter:DVKCompanionStoreAdapter, onClose:@escaping () -> Void = {}) { self.adapter=adapter; self.onClose=onClose }
    public var body:some View {
        let store=adapter.store
        let theme=DVKCompanionThemeResolver.resolve(profile:store.selectedProfile, appearance:store.appearance)
        ScrollView{VStack(alignment:.leading,spacing:16){if let profile=store.selectedProfile{HStack{DVKCharacterPresentationView(profile:profile,state:store.characterState,reduceMotion:store.reduceMotionPreview,staticMode:store.presentationMode == .staticFallback,host:store.presentationMode == .staticFallback ? nil : adapter.live2DHost).frame(width:54,height:54);VStack(alignment:.leading){Text(profile.displayName).font(.headline);Text(profile.personalityTags.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)}};Text("Switch cat from the Cats tab when this conversation is idle.").font(.caption).foregroundStyle(.secondary)};Picker("Mode",selection:Binding(get:{store.mode},set:{store.setMode($0);adapter.refresh()})){Text("Text").tag(DVKCompanionMode.text);Text("Voice").tag(DVKCompanionMode.voice)}.pickerStyle(.segmented).accessibilityIdentifier(DVKCompanionAccessibilityID.modePicker);if store.mode == .text {DVKTextConversation(adapter:adapter)} else {DVKVoiceConversation(adapter:adapter, onEnded:onClose)}}.padding(20)}.background(DVKBackgroundMeshView(mode: .call, theme: theme)).navigationTitle("Conversation")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button(action: onClose) { Image(systemName: store.hasActiveSession ? "chevron.down" : "xmark") }.accessibilityLabel(store.hasActiveSession ? "收起语音会话" : "关闭会话") } }
        .accessibilityIdentifier("companion.conversation")
    }
}

@MainActor
public struct DVKTextConversation: View {
    @ObservedObject var adapter:DVKCompanionStoreAdapter
    public init(adapter:DVKCompanionStoreAdapter){self.adapter=adapter}
    public var body:some View {
        let store=adapter.store
        let theme=DVKCompanionThemeResolver.resolve(profile:store.selectedProfile, appearance:store.appearance)
        VStack(alignment:.leading,spacing:12){
            // 顶部轻量状态区（mock 离线提示）
            HStack(spacing:6){
                DVKCompanionSonarDot(
                    color: theme.activeStatus,
                    diameter: 12,
                    reduceMotion: store.reduceMotionPreview
                )
                Text("Local mock text · offline")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal,12)
            .padding(.vertical,6)
            .background(theme.surface.opacity(0.55),in:Capsule())
            .accessibilityElement(children:.combine)
            ForEach(store.messages){message in
                HStack(alignment:.bottom){
                    if message.role == .assistant{bubble(message, theme:theme)}
                    Spacer(minLength:12)
                    if message.role == .user{bubble(message, theme:theme)}
                }
            }
            HStack(alignment:.bottom){
                TextField("Write a message",text:Binding(get:{store.draft},set:{store.setDraft($0);adapter.refresh()}),axis:.vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal,4)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.chatInput)
                Button{
                    guard let op=store.beginSendDraft() else{return}
                    adapter.refresh()
                    Task{await op.value;adapter.refresh()}
                } label:{
                    Label("Send",systemImage:"arrow.up.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .dvkGlassControl(theme: theme, prominent: true)
                .disabled(!store.canSend)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.chatSend)
            }
            if store.sending{
                HStack(spacing:8){
                    ProgressView().controlSize(.small)
                    Text("Sending…")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                }
                .accessibilityIdentifier(DVKCompanionAccessibilityID.chatSending)
            }
            HStack{
                Button("Plan next failure"){Task{await store.planNextMockFailure();adapter.refresh()}}
                    .disabled(!store.canPlanMockFailure)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.chatPlanFailure)
                if store.mockFailurePlanned{Text("Next send fails").font(.caption)}
            }
            if store.lastFailure{
                Button("Retry"){Task{await store.retryFailedMessage();adapter.refresh()}}
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.chatRetry)
            }
            if let error=store.lastError{
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("companion.chat.error")
            }
        }
    }
    private func bubble(_ m:DVKCompanionMessage, theme:DVKCompanionTheme)->some View{
        let user=m.role == .user
        return VStack(alignment:.leading,spacing:4){
            if !user{Text(m.profileSnapshot?.displayName ?? "Mock").font(.caption.bold())}
            Text(m.text)
                .font(.body)
                .fixedSize(horizontal:false,vertical:true)
            Text(m.deliveryState.rawValue.capitalized)
                .font(.caption2)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal,14)
        .padding(.vertical,10)
        .frame(maxWidth:280,alignment:.leading)
        .background(
            user
                ? DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).userMessageSurface
                : theme.assistantMessageSurface,
            in:RoundedRectangle(cornerRadius:18,style:.continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius:18,style:.continuous)
                .stroke(user ? theme.primaryAction.opacity(0.18) : theme.border.opacity(0.5),lineWidth:1)
        )
    }
}

@MainActor
public struct DVKVoiceConversation: View {
    @ObservedObject var adapter: DVKCompanionStoreAdapter
    private let onEnded: () -> Void
    public init(adapter: DVKCompanionStoreAdapter, onEnded:@escaping () -> Void = {}) { self.adapter = adapter; self.onEnded = onEnded }

    public var body: some View {
        let store = adapter.store
        let theme = DVKCompanionThemeResolver.resolve(profile: store.selectedProfile, appearance: store.appearance)
        if adapter.usesLiveConnection, adapter.hasLiveToken {
            DVKLiveVoiceConversation(adapter: adapter, onEnded: onEnded)
        } else {
            mockPane(store: store, theme: theme)
        }
    }

    @ViewBuilder
    private func mockPane(store: DVKCompanionStore, theme: DVKCompanionTheme) -> some View {
        let ripplePresentation = DVKCharacterVoiceRipplePresentation(
            amplitude: store.playbackAmplitude,
            voiceState: store.voiceState,
            reduceMotion: store.reduceMotionPreview,
            staticMode: store.presentationMode == .staticFallback,
            hasError: store.voiceError != nil
        )
        VStack(spacing: 16) {
            // 顶部状态区
            HStack(spacing: 6) {
                DVKCompanionSonarDot(
                    color: theme.activeStatus,
                    diameter: 12,
                    reduceMotion: store.reduceMotionPreview
                )
                Text("Mock voice · offline demo")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.surface.opacity(0.55), in: Capsule())
            .accessibilityElement(children: .combine)

            if let profile = store.selectedProfile {
                // 中央大人物 Hero（占比 + 波纹 + halo）
                VStack(spacing: 8) {
                    ZStack {
                        DVKCompanionHeroHalo(
                            color: theme.halo,
                            diameter: 220,
                            reduceMotion: store.reduceMotionPreview
                        )
                        DVKCharacterVoiceRipple(presentation: ripplePresentation, theme: theme)
                        DVKCharacterPresentationView(
                            profile: profile,
                            state: store.characterState,
                            reduceMotion: store.reduceMotionPreview,
                            staticMode: store.presentationMode == .staticFallback,
                            host: store.presentationMode == .staticFallback ? nil : adapter.live2DHost
                        )
                        .frame(height: 220)
                    }
                    .frame(height: 286)
                    Text(profile.displayName)
                        .font(DVKCompanionTypography.serifName(26))
                        .foregroundStyle(theme.textPrimary)
                    // 状态区
                    Text(ripplePresentation.statusText)
                        .font(.headline)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceState)
                    // 波纹（播放振幅驱动）
                    DVKCompanionMiniWave(
                        active: store.voiceState == .speaking,
                        color: theme.primaryAction,
                        reduceMotion: store.reduceMotionPreview,
                        barCount: 7
                    )
                    .frame(width: 96, height: 16)
                    .opacity(0.8)
                }
            } else {
                Text(ripplePresentation.statusText)
                    .font(.headline)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceState)
            }
            if let error = store.voiceError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceError)
            }
            // 控制区：开始 / 推进 / 结束（Mock 必需行为）
            DVKIOS26GlassEffectContainer {
                HStack(spacing: 10) {
                    Button {
                        adapter.refresh()
                        Task { await store.beginVoiceDemo(); adapter.refresh() }
                    } label: {
                        Label("Start", systemImage: "mic.fill")
                    }
                    .disabled(!store.canStartVoice)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceStart)
                    .dvkGlassControl(theme: theme, prominent: true)

                    Button {
                        store.advanceVoiceDemo()
                        adapter.refresh()
                    } label: {
                        Label("Advance", systemImage: "arrow.right.circle.fill")
                    }
                    .disabled(store.voiceState == .idle || store.voiceState == .ended)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceAdvance)
                    .dvkGlassControl(theme: theme)

                    Button(role: .destructive) {
                        Task {
                            await store.endVoiceDemo()
                            adapter.refresh()
                            onEnded()
                        }
                    } label: {
                        Label("结束通话", systemImage: "phone.down.fill")
                    }
                    .disabled(!store.canEndVoice)
                    .accessibilityLabel("结束通话")
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceEnd)
                    .dvkGlassControl(theme: theme)
                }
            }
            if store.generating == .failed {
                Button("Retry review") {
                    Task { await store.retryReviewGeneration(); adapter.refresh() }
                }
                .dvkGlassControl(theme: theme)
            }
        }
    }
}

@MainActor
public struct DVKLiveVoiceConversation: View {
    @ObservedObject var adapter: DVKCompanionStoreAdapter
    private let onEnded: () -> Void
    @StateObject private var controller: DVKCompanionVoiceSessionController

    public init(adapter: DVKCompanionStoreAdapter, onEnded: @escaping () -> Void = {}) {
        self.adapter = adapter
        self.onEnded = onEnded
        _controller = StateObject(wrappedValue: DVKCompanionVoiceSessionController(
            configuration: adapter.runtimeConfiguration,
            tokenStore: adapter.tokenStore
        ))
    }

    public var body: some View {
        let store = adapter.store
        let theme = DVKCompanionThemeResolver.resolve(profile: store.selectedProfile, appearance: store.appearance)
        let ripplePresentation = DVKCharacterVoiceRipplePresentation(
            amplitude: controller.playbackAmplitude,
            voiceState: controller.companionVoiceState,
            reduceMotion: store.reduceMotionPreview,
            staticMode: store.presentationMode == .staticFallback,
            hasError: !controller.errorMessage.isEmpty
        )
        VStack(spacing: 16) {
            if let profile = store.selectedProfile {
                VStack(spacing: 8) {
                    ZStack {
                        DVKCharacterVoiceRipple(presentation: ripplePresentation, theme: theme)
                        DVKCharacterPresentationView(
                            profile: profile,
                            state: liveCharacterState,
                            reduceMotion: store.reduceMotionPreview,
                            staticMode: store.presentationMode == .staticFallback,
                            host: store.presentationMode == .staticFallback ? nil : adapter.live2DHost
                        )
                        .frame(height: 220)
                    }
                    .frame(height: 286)
                    Text(profile.displayName)
                        .font(.title3.bold())
                        .foregroundStyle(theme.textPrimary)
                    Text(controller.errorMessage.isEmpty ? ripplePresentation.statusText : controller.errorMessage)
                        .font(.headline)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceState)
                }
            }
            if !controller.responseText.isEmpty {
                Text(controller.responseText)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.conversationReply)
            }
            DVKIOS26GlassEffectContainer {
                HStack(spacing: 10) {
                    Button(controller.isMuted ? "Unmute" : "Mute") {
                        Task { await controller.setMuted(!controller.isMuted) }
                    }
                    .disabled(!controller.canMute)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceMute)
                    .dvkGlassControl(theme: theme)

                    Button("Interrupt") {
                        Task { await controller.interrupt() }
                    }
                    .disabled(!controller.canInterrupt)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceInterrupt)
                    .dvkGlassControl(theme: theme)

                    Button(role: .destructive) {
                        Task {
                            await controller.endCurrentCall()
                            adapter.refresh()
                            onEnded()
                        }
                    } label: {
                        Label("结束通话", systemImage: "phone.down.fill")
                    }
                    .disabled(!controller.canEndVoice)
                    .accessibilityLabel("结束通话")
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceEnd)
                    .dvkGlassControl(theme: theme)
                }
            }
        }
        .task { await controller.startNewCall() }
        .onDisappear { Task { await controller.endCurrentCall() } }
    }

    private var liveCharacterState: DVKCompanionCharacterPresentationState {
        switch controller.companionVoiceState {
        case .speaking: return .speaking(amplitude: controller.playbackAmplitude)
        case .listening: return .listening
        case .processing: return .thinking
        default: return controller.errorMessage.isEmpty ? .idle : .error
        }
    }
}

@MainActor
public struct DVKCompanionSettingsView: View {
    @ObservedObject var adapter:DVKCompanionStoreAdapter
    public init(adapter:DVKCompanionStoreAdapter){self.adapter=adapter}
    public var body: some View {
        let store=adapter.store
        let theme=DVKCompanionThemeResolver.resolve(profile:store.selectedProfile, appearance:store.appearance)
        Form {
            // 用户行（程序化猫头像 + 名字 + 副标题）
            Section {
                if let profile = store.selectedProfile {
                    HStack(spacing: 14) {
                        DVKCharacterPresentationView(
                            profile: profile,
                            state: .idle,
                            reduceMotion: true,
                            staticMode: true,
                            host: nil
                        )
                        .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName)
                                .font(DVKCompanionTypography.serifName(20))
                                .foregroundStyle(theme.textPrimary)
                            Text("Your local companion")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Default cat") {
                Picker("Cat", selection: Binding(get: { store.selectedProfileID ?? "" }, set: { store.selectPreviewProfile(id: $0); store.confirmProfileSelection(); adapter.refresh() })) {
                    ForEach(store.profiles) { Text($0.displayName).tag($0.id) }
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: Binding(get: { store.appearance }, set: { store.setAppearance($0); adapter.refresh() })) {
                    ForEach(DVKCompanionAppearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("Reduce Motion preview", isOn: Binding(get: { store.reduceMotionPreview }, set: { store.setReduceMotionPreview($0); adapter.refresh() }))
                Text("Dynamic Type, VoiceOver and Reduce Motion are supported by the public UI.").font(.footnote)
            }
            Section("Connection") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(adapter.runtimeConfiguration.statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(theme.textPrimary)
                    Text(adapter.hasLiveToken
                         ? "A private token is stored in the secure store."
                         : "No token stored. Live chat and voice need a token plus a live build configuration.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.settingsConnection)
                NavigationLink("Device binding") {
                    DVKDeviceBindingView(
                        configuration: adapter.runtimeConfiguration,
                        tokenStore: adapter.tokenStore
                    )
                }
                Button("Clear saved token") {
                    try? adapter.tokenStore.clear()
                    adapter.refresh()
                }
                .disabled(!adapter.hasLiveToken)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.settingsTokenClear)
                if !adapter.runtimeConfiguration.buildSHA.isEmpty {
                    Text("Build \(adapter.runtimeConfiguration.buildSHA) · \(adapter.runtimeConfiguration.buildTime)")
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Section("Privacy") {
                Button(store.privacy == .allowed ? "Preview limited privacy" : "Re-authorize") {
                    if store.privacy == .allowed { store.setPrivacy(.limited) } else { store.reauthorize() }
                    adapter.refresh()
                }
                .accessibilityIdentifier(store.privacy == .allowed ? DVKCompanionAccessibilityID.privacyLimited : DVKCompanionAccessibilityID.reauthorize)
            }
            Section("Mock Lab") {
                DVKMockLabView(adapter: adapter)
            }
            Section("About") {
                Text("DVK Companion is local-only, provider-neutral, and uses four fictional mock cats. No production identity, prompt, token, or asset is included.")
            }
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .scrollContentBackground(.hidden)
        .listRowBackground(theme.surface)
        .foregroundStyle(theme.textPrimary)
        .tint(theme.primaryAction)
        .background(theme.pageBackground)
        .dvkIOS26NavigationChrome(theme: theme)
        .navigationTitle("Settings")
        .accessibilityIdentifier(DVKCompanionAccessibilityID.settings)
    }
}

@MainActor
public struct DVKMockLabView: View {
    @ObservedObject var adapter:DVKCompanionStoreAdapter
    public init(adapter:DVKCompanionStoreAdapter){self.adapter=adapter}
    public var body: some View {
        let store=adapter.store
        VStack(alignment:.leading,spacing:10) {
            Text("Deterministic local scenarios").font(.subheadline)
            ForEach(DVKCompanionMockScenario.allCases,id:\.self) { scenario in
                Button(scenario.rawValue.replacingOccurrences(of:"Text",with:" text ")) { store.setScenario(scenario); adapter.refresh() }
                    .buttonStyle(.bordered).accessibilityIdentifier("companion.mock.\(scenario.rawValue)")
            }
            Divider()
            Text("Character state").font(.headline)
            Picker("Character state",selection:Binding(get:{stateName(store.characterState)},set:{store.setMockCharacterState(stateFrom($0));adapter.refresh()})) {
                ForEach(["idle","listening","thinking","speaking","celebrating","unavailable","error"],id:\.self) { Text($0.capitalized).tag($0) }
            }
            Slider(value:Binding(get:{Double(store.playbackAmplitude)},set:{store.setMockPlaybackAmplitude(Float($0));adapter.refresh()}),in:0...1).accessibilityIdentifier("companion.mock.amplitude")
            Picker("Presentation",selection:Binding(get:{store.presentationMode},set:{store.setPresentationMode($0);adapter.refresh()})) {
                ForEach(DVKCompanionPresentationMode.allCases,id:\.self) { Text($0 == .staticFallback ? "Static" : "Programmatic").tag($0) }
            }
            Toggle("Reduce Motion preview",isOn:Binding(get:{store.reduceMotionPreview},set:{store.setReduceMotionPreview($0);adapter.refresh()}))
            Text("Amplitude is assistant playback only; input text never drives it.").font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier(DVKCompanionAccessibilityID.mockLab)
    }
    private func stateName(_ state:DVKCompanionCharacterPresentationState)->String {
        switch state { case .idle:return "idle"; case .listening:return "listening"; case .thinking:return "thinking"; case .speaking:return "speaking"; case .celebrating:return "celebrating"; case .unavailable:return "unavailable"; case .error:return "error" }
    }
    private func stateFrom(_ name:String)->DVKCompanionCharacterPresentationState? {
        switch name { case "listening":return .listening; case "thinking":return .thinking; case "speaking":return .speaking(amplitude:adapter.store.playbackAmplitude); case "celebrating":return .celebrating; case "unavailable":return .unavailable; case "error":return .error; default:return .idle }
    }
}

@MainActor
public struct DVKPrivacyLimitedView: View { let onReauthorize:()->Void; public init(onReauthorize:@escaping()->Void){self.onReauthorize=onReauthorize}; public var body:some View{VStack(alignment:.leading,spacing:8){Label("Privacy limited",systemImage:"lock.shield");Text("Browsing and configured text demos remain available; voice stays paused.");Button("Re-authorize",action:onReauthorize).buttonStyle(.borderedProminent).accessibilityIdentifier(DVKCompanionAccessibilityID.reauthorize)}.padding().background(.thinMaterial,in:RoundedRectangle(cornerRadius:18)).accessibilityIdentifier(DVKCompanionAccessibilityID.privacyLimited)} }

@MainActor
public struct DVKEasterEggCard: View { public let egg:DVKCompanionEasterEgg; let onClose:()->Void; public init(egg:DVKCompanionEasterEgg,onClose:@escaping()->Void){self.egg=egg;self.onClose=onClose}; public var body:some View{VStack(alignment:.leading){HStack{Text(egg.title).font(.headline);Spacer();Button("Close",action:onClose)};Text(egg.detail)}.padding().background(.thinMaterial,in:RoundedRectangle(cornerRadius:18))} }

@MainActor
public struct DVKReviewListView: View {
    @ObservedObject var adapter:DVKCompanionStoreAdapter
    public init(adapter:DVKCompanionStoreAdapter){self.adapter=adapter}
    public var body: some View {
        let store = adapter.store
        let theme = DVKCompanionThemeResolver.resolve(profile: store.selectedProfile, appearance: store.appearance)
        Group {
            if store.reviews.isEmpty {
                // 诚实空状态（卡片质感，不伪造聊天/情绪/音频记录）
                VStack(spacing: 16) {
                    if let profile = store.selectedProfile {
                        DVKCharacterPresentationView(
                            profile: profile,
                            state: .idle,
                            reduceMotion: true,
                            staticMode: true,
                            host: nil
                        )
                        .frame(width: 96, height: 96)
                    }
                    Text("No reviews yet")
                        .font(DVKCompanionTypography.serifDisplay(22))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Complete a local mock session or seed Mock Lab data")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("companion.reviews.empty")
            } else {
                List(store.reviews) { review in
                    Button {
                        store.selectReview(id: review.id)
                        adapter.refresh()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: review.source == .voice ? "waveform" : "bubble.left.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(theme.primaryAction)
                                .frame(width: 36, height: 36)
                                .background(theme.primaryAction.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(review.title).font(.headline).lineLimit(2)
                                Text(review.profileSnapshot?.displayName ?? "Mock cat").font(.caption)
                                Text(review.source.rawValue.capitalized).font(.caption2)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(theme.surface)
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier("companion.review.\(review.id)")
                }
                .listStyle(.plain)
            }
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .scrollContentBackground(.hidden)
        .background(theme.pageBackground)
        .foregroundStyle(theme.textPrimary)
        .dvkIOS26NavigationChrome(theme: theme)
        .navigationTitle("Reviews")
        .sheet(
            isPresented: Binding(
                get: { store.selectedReview() != nil },
                set: {
                    if !$0 {
                        store.clearSelectedReview()
                        adapter.refresh()
                    }
                }
            )
        ) {
            if let review = store.selectedReview() {
                DVKReviewDetailView(
                    review: review,
                    onDelete: {
                        store.deleteReview(id: review.id)
                        adapter.refresh()
                    },
                    onClose: {
                        store.clearSelectedReview()
                        adapter.refresh()
                    }
                )
            }
        }
    }
}
@MainActor
public struct DVKReviewDetailView: View { public let review:DVKCompanionReview; let onDelete:()->Void;let onClose:()->Void; public init(review:DVKCompanionReview,onDelete:@escaping()->Void,onClose:@escaping()->Void){self.review=review;self.onDelete=onDelete;self.onClose=onClose}; public var body:some View{let theme=DVKCompanionThemeResolver.resolve(themeKey:review.profileSnapshot?.themeKey, appearance:.followProfile);NavigationStack{VStack(alignment:.leading,spacing:14){Text(review.title).font(.largeTitle.bold());Text(review.profileSnapshot?.displayName ?? "Mock cat").font(.headline);Text(review.summary);Text(review.source.rawValue.capitalized);Spacer();Button("Delete review",role:.destructive,action:onDelete).accessibilityIdentifier(DVKCompanionAccessibilityID.reviewDelete);Button("Close",action:onClose)}.padding().foregroundStyle(theme.textPrimary).background(theme.pageBackground.ignoresSafeArea()).tint(theme.primaryAction).dvkIOS26NavigationChrome(theme: theme).navigationTitle("Review detail").accessibilityIdentifier(DVKCompanionAccessibilityID.reviewDetail)}}}
#endif
