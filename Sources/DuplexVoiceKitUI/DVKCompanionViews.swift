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
                    .navigationTitle("陪伴")
            }.dvkIOS26NavigationChrome(theme: activeTheme).tabItem{Label("陪伴",systemImage:"mic.fill")}.tag(DVKCompanionTab.home).accessibilityIdentifier(DVKCompanionAccessibilityID.home)
            NavigationStack {
                DVKCompanionProfilesView(adapter:adapter, openConversation:{conversation=true})
                    .navigationTitle("角色")
            }.dvkIOS26NavigationChrome(theme: activeTheme).tabItem{Label("角色",systemImage:"person.2.fill")}.tag(DVKCompanionTab.profiles).accessibilityIdentifier(DVKCompanionAccessibilityID.profiles)
            NavigationStack {
                DVKReviewListView(adapter:adapter)
            }.dvkIOS26NavigationChrome(theme: activeTheme).tabItem{Label("回顾",systemImage:"clock.arrow.circlepath")}.tag(DVKCompanionTab.reviews).accessibilityIdentifier(DVKCompanionAccessibilityID.reviews)
            NavigationStack {
                DVKCompanionSettingsView(adapter:adapter)
            }.dvkIOS26NavigationChrome(theme: activeTheme).tabItem{Label("我的",systemImage:"person.crop.circle")}.tag(DVKCompanionTab.settings).accessibilityIdentifier(DVKCompanionAccessibilityID.settings)
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
public struct DVKCompanionHomeView: View {
    @ObservedObject private var adapter: DVKCompanionStoreAdapter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var nameBreath = false
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
            let textCardHeight: CGFloat = compact ? 52 : 60
            let innerSpacing: CGFloat = compact ? 8 : 12
            let nonCharacterBudget = statusHeight
                + nameHeight
                + readyHeight
                + ctaHeight
                + textCardHeight
            let characterMaxHeight: CGFloat = compact ? 200 : 290
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
                        // 中央大人物 Hero：halo 光晕 + 呼吸人物（绝对主体）
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

                        // 状态点声呐 + 在场文案 + 迷你波形
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

                        // 宋体角色名（呼吸）
                        Text(profile.displayName)
                            .font(DVKCompanionTypography.serifName(compact ? 26 : 30))
                            .tracking(nameBreath ? 2.0 : 0.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(theme.textPrimary)
                            .animation(
                                (systemReduceMotion || store.reduceMotionPreview)
                                    ? nil
                                    : .easeInOut(duration: 8).repeatForever(autoreverses: true),
                                value: nameBreath
                            )
                            .frame(height: nameHeight)

                        // 简短问候
                        Text(profile.greeting)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(theme.textSecondary)
                            .frame(height: readyHeight)

                        // 唯一主操作：语音聊天
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

                        // 次级文字聊天入口（克制卡片，视觉层级低于语音主按钮）
                        textChatCard(theme: theme, height: textCardHeight) {
                            store.setMode(.text)
                            adapter.refresh()
                            openConversation()
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
        .onAppear { nameBreath = true }
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

    /// 次级文字聊天入口：克制卡片（气泡图标 + 标题 + 副标题 + chevron），
    /// 视觉层级明显低于语音主按钮。
    private func textChatCard(
        theme: DVKCompanionTheme,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.primaryAction.opacity(0.75))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("文字聊天")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text("安静地打字聊聊")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dvkGlassSurface(theme: theme)
        .dvkCardTopHighlight()
        .accessibilityLabel("文字聊天，安静地打字聊聊")
        .accessibilityIdentifier("companion.home.textChat")
    }
}

@MainActor
public struct DVKCompanionProfilesView: View {
    @ObservedObject private var adapter: DVKCompanionStoreAdapter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var scrollPosition: String?
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
            let headerBudget: CGFloat = 84
            let footerBudget: CGFloat = store.canSelectProfiles ? 112 : 142
            let availableHeroHeight = max(
                0,
                usableHeight - headerBudget - footerBudget
            )
            let cardHeight = max(250, min(400, availableHeroHeight * 0.86))
            // 卡片宽度：屏幕宽度 - 左右页边距 - 相邻轻微露出
            let cardWidth = max(
                260,
                geometry.size.width - 20 * 2 - 28
            )

            VStack(spacing: 0) {
                // 页面主标题 + 简短副标题（单行，不抢主标题）
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前陪伴角色")
                        .font(DVKCompanionTypography.serifDisplay(32))
                        .foregroundStyle(theme.textPrimary)
                    Text("左右滑动查看，确认后开始聊天")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // 可左右分页滑动的大角色主卡
                roleSwipeCarousel(
                    store: store,
                    theme: theme,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight
                )

                // 底部固定角色操作条（头像 + 名称 + 标签 + 主按钮）
                roleActionBar(store: store, theme: theme)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                if !store.canSelectProfiles {
                    Text("会话进行中，暂不能切换角色。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .foregroundStyle(theme.textPrimary)
        .background(DVKBackgroundMeshView(mode: .home, theme: theme))
        .tint(theme.primaryAction)
        .animation(store.reduceMotionPreview ? nil : .easeInOut(duration: 0.25), value: store.previewProfileID)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier(DVKCompanionAccessibilityID.profiles)
    }

    // MARK: 左右滑动角色主卡（分页停靠，相邻轻微露出）
    @MainActor
    private func roleSwipeCarousel(
        store: DVKCompanionStore,
        theme: DVKCompanionTheme,
        cardWidth: CGFloat,
        cardHeight: CGFloat
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(store.profiles) { profile in
                    roleHeroCard(
                        profile: profile,
                        store: store,
                        theme: theme,
                        isPreview: profile.id == store.previewProfileID
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .id(profile.id)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 12)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollPosition(id: $scrollPosition)
        .accessibilityIdentifier(DVKCompanionAccessibilityID.profileCarousel)
        .accessibilityActions {
            Button("上一位角色") { movePreview(offset: -1, store: store) }
            Button("下一位角色") { movePreview(offset: 1, store: store) }
        }
        .onAppear { scrollPosition = store.previewProfileID }
        .onChange(of: scrollPosition) { _, id in
            guard store.canSelectProfiles, let id else { return }
            store.selectPreviewProfile(id: id)
            adapter.refresh()
        }
    }

    // MARK: 无障碍 / 自动滑动切换（仅 VoiceOver 动作，不显示可见按钮）
    private func movePreview(offset: Int, store: DVKCompanionStore) {
        guard store.canSelectProfiles,
              let index = store.profiles.firstIndex(where: { $0.id == store.previewProfileID }) else { return }
        let destination = index + offset
        guard store.profiles.indices.contains(destination) else { return }
        let id = store.profiles[destination].id
        store.selectPreviewProfile(id: id)
        scrollPosition = id
        adapter.refresh()
    }

    // MARK: 大人物主卡（当前预览角色：badge + 渐变 + halo + 大人物 + 名字 + chips + 通话胶囊）
    @MainActor
    private func roleHeroCard(
        profile: DVKCompanionProfile,
        store: DVKCompanionStore,
        theme: DVKCompanionTheme,
        isPreview: Bool
    ) -> some View {
        let profileTheme = DVKCompanionThemeResolver.resolve(profile: profile, appearance: store.appearance)
        let reduced = systemReduceMotion || store.reduceMotionPreview
        let avatarDimension: CGFloat = 190
        return VStack(spacing: 10) {
            Text("当前角色")
                .font(.caption.weight(.semibold))
                .foregroundStyle(profileTheme.primaryAction)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(profileTheme.primaryAction.opacity(0.10), in: Capsule())
                .padding(.top, 12)

            ZStack {
                // 角色渐变背景（上半）
                profileTheme.primaryAction.opacity(0.12)
                    .frame(height: avatarDimension * 0.62)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                // halo 光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [profileTheme.primaryAction.opacity(0.26), profileTheme.halo.opacity(0.14), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 130
                        )
                    )
                    .frame(width: avatarDimension * 1.2, height: avatarDimension * 1.2)
                // 程序化 Mock 猫（固定容器内，不裁切不溢出）
                DVKCharacterPresentationView(
                    profile: profile,
                    state: .idle,
                    reduceMotion: reduced,
                    staticMode: true,
                    host: nil
                )
                .frame(width: avatarDimension, height: avatarDimension)
            }
            .frame(height: avatarDimension * 1.02)
            .padding(.top, 2)

            Text(profile.displayName)
                .font(DVKCompanionTypography.serifName(25))
                .foregroundStyle(profileTheme.textPrimary)
                .lineLimit(1)

            // 标签：最多两个，单行，不逐字断行
            HStack(spacing: 6) {
                ForEach(profile.personalityTags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(profileTheme.primaryAction.opacity(0.10), in: Capsule())
                        .foregroundStyle(profileTheme.primaryAction)
                }
            }
            .frame(maxWidth: .infinity)

            Text(profile.shortSummary)
                .font(.subheadline)
                .foregroundStyle(profileTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                Text(profile.capabilities.contains(.voice) ? "支持实时通话" : "文字陪伴")
                    .font(.caption)
            }
            .foregroundStyle(profileTheme.primaryAction)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(profileTheme.primaryAction.opacity(0.10), in: Capsule())
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(profileTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(isPreview ? profileTheme.primaryAction.opacity(0.7) : profileTheme.border.opacity(0.5), lineWidth: isPreview ? 2 : 1)
        )
        .dvkCardTopHighlight()
        .shadow(color: profileTheme.shadow.opacity(0.16), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("companion.profile.hero.\(profile.id)")
    }

    // MARK: 底部固定角色操作条（小头像 + 名称 + 最多两标签 + 主按钮，无可见切换按钮）
    @MainActor
    private func roleActionBar(
        store: DVKCompanionStore,
        theme: DVKCompanionTheme
    ) -> some View {
        guard let profile = store.previewProfile else {
            return AnyView(EmptyView())
        }
        let profileTheme = DVKCompanionThemeResolver.resolve(profile: profile, appearance: store.appearance)
        let isCurrent = profile.id == store.selectedProfileID
        return AnyView(
            HStack(spacing: 12) {
                // 小头像（48–56 pt 固定 Frame + clipped，不溢出）
                DVKCharacterPresentationView(
                    profile: profile,
                    state: .idle,
                    reduceMotion: true,
                    staticMode: true,
                    host: nil
                )
                .frame(width: 52, height: 52)
                .clipped()

                // 角色信息：名称单行 + 最多两标签单行
                ViewThatFits(in: .horizontal) {
                    // 宽屏：头像 + 名称/标签 + 主按钮
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.displayName)
                                .font(.headline)
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                ForEach(profile.personalityTags.prefix(2), id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(profileTheme.primaryAction.opacity(0.10), in: Capsule())
                                        .foregroundStyle(profileTheme.primaryAction)
                                }
                            }
                        }
                        Spacer(minLength: 4)
                        primaryBarButton(store: store, profile: profile, isCurrent: isCurrent, theme: theme, profileTheme: profileTheme)
                    }
                    // 窄屏：头像 + 名称 + 主按钮（省略标签）
                    HStack(spacing: 10) {
                        Text(profile.displayName)
                            .font(.headline)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        primaryBarButton(store: store, profile: profile, isCurrent: isCurrent, theme: theme, profileTheme: profileTheme)
                    }
                }
            }
            .padding(12)
            .background(profileTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(profileTheme.border.opacity(0.5), lineWidth: 1)
            )
            .dvkCardTopHighlight()
            .accessibilityIdentifier(DVKCompanionAccessibilityID.profilePreview)
        )
    }

    @MainActor
    private func primaryBarButton(
        store: DVKCompanionStore,
        profile: DVKCompanionProfile,
        isCurrent: Bool,
        theme: DVKCompanionTheme,
        profileTheme: DVKCompanionTheme
    ) -> some View {
        Button {
            if isCurrent {
                openConversation()
            } else {
                store.confirmProfileSelection()
                adapter.refresh()
            }
        } label: {
            Text(isCurrent ? "开始聊天" : "使用此角色")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .dvkGlassControl(theme: profileTheme, prominent: true)
        .disabled(
            isCurrent
                ? store.selectedProfile == nil
                : !store.canConfirmProfileSelection
        )
        .accessibilityLabel(
            DVKRoleSelectionActionPresentation.title(
                previewProfileID: profile.id,
                selectedProfileID: store.selectedProfileID
            )
        )
        .accessibilityIdentifier(DVKCompanionAccessibilityID.profileConfirm)
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
        VStack(spacing:0){
            // 顶部：当前角色 + 模式切换
            VStack(spacing:10){
                if let profile=store.selectedProfile{
                    HStack{
                        DVKCharacterPresentationView(
                            profile:profile,
                            state:store.characterState,
                            reduceMotion:store.reduceMotionPreview,
                            staticMode:store.presentationMode == .staticFallback,
                            host:store.presentationMode == .staticFallback ? nil : adapter.live2DHost
                        )
                        .frame(width:48,height:48)
                        VStack(alignment:.leading,spacing:2){
                            Text(profile.displayName).font(.headline)
                            Text(profile.personalityTags.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength:0)
                    }
                }
                Picker("Mode",selection:Binding(get:{store.mode},set:{store.setMode($0);adapter.refresh()})){
                    Text("文字").tag(DVKCompanionMode.text)
                    Text("语音").tag(DVKCompanionMode.voice)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.modePicker)
            }
            .padding(.horizontal,20)
            .padding(.top,12)
            .padding(.bottom,8)

            if store.mode == .text {
                DVKTextConversation(adapter:adapter)
            } else {
                DVKVoiceConversation(adapter:adapter, onEnded:onClose)
            }
        }
        .background(DVKBackgroundMeshView(mode: .call, theme: theme))
        .navigationTitle("陪伴")
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
        VStack(spacing:0){
            // 顶部轻量状态区（mock 离线提示）
            HStack(spacing:6){
                DVKCompanionSonarDot(
                    color: theme.activeStatus,
                    diameter: 12,
                    reduceMotion: store.reduceMotionPreview
                )
                Text("本地文字陪伴 · 离线")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal,12)
            .padding(.vertical,6)
            .background(theme.surface.opacity(0.55),in:Capsule())
            .accessibilityElement(children:.combine)
            .padding(.top,8)

            // 完整消息滚动区
            ScrollView(showsIndicators:false){
                LazyVStack(spacing:12){
                    if store.messages.isEmpty{
                        // 诚实空状态
                        VStack(spacing:10){
                            Image(systemName:"bubble.left.and.bubble.right")
                                .font(.system(size:26,weight:.medium))
                                .foregroundStyle(theme.primaryAction.opacity(0.7))
                            Text("说点什么，开始本地陪伴")
                                .font(.subheadline)
                                .foregroundStyle(theme.textSecondary)
                        }
                        .frame(maxWidth:.infinity)
                        .padding(.top,48)
                        .accessibilityIdentifier("companion.chat.empty")
                    }
                    ForEach(store.messages){message in
                        HStack(alignment:.bottom){
                            if message.role == .assistant{bubble(message, theme:theme)}
                            Spacer(minLength:12)
                            if message.role == .user{bubble(message, theme:theme)}
                        }
                    }
                }
                .padding(.horizontal,20)
                .padding(.top,12)
                .padding(.bottom,12)
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)

            // 固定底部输入区
            HStack(alignment:.bottom){
                TextField("说点什么",text:Binding(get:{store.draft},set:{store.setDraft($0);adapter.refresh()}),axis:.vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal,4)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.chatInput)
                Button{
                    guard let op=store.beginSendDraft() else{return}
                    adapter.refresh()
                    Task{await op.value;adapter.refresh()}
                } label:{
                    Label("发送",systemImage:"arrow.up.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .dvkGlassControl(theme: theme, prominent: true)
                .disabled(!store.canSend)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.chatSend)
            }
            .padding(.horizontal,16)
            .padding(.top,10)
            .padding(.bottom,10)
            .background(theme.navigationSurface.opacity(0.9))

            // 辅助调试区（弱化，不抢主界面）
            if store.sending{
                HStack(spacing:8){
                    ProgressView().controlSize(.small)
                    Text("发送中…")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.bottom,6)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.chatSending)
            }
            HStack(spacing:14){
                Button("模拟下次失败"){Task{await store.planNextMockFailure();adapter.refresh()}}
                    .font(.caption)
                    .disabled(!store.canPlanMockFailure)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.chatPlanFailure)
                if store.mockFailurePlanned{Text("下次发送将失败").font(.caption)}
                if store.lastFailure{
                    Button("重试"){Task{await store.retryFailedMessage();adapter.refresh()}}
                        .font(.caption)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.chatRetry)
                }
            }
            .padding(.bottom,8)
            .opacity(0.75)
            if let error=store.lastError{
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.bottom,8)
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
        VStack(spacing: 12) {
            // 顶部状态区
            HStack(spacing: 6) {
                DVKCompanionSonarDot(
                    color: theme.activeStatus,
                    diameter: 12,
                    reduceMotion: store.reduceMotionPreview
                )
                Text("语音陪伴 · 本地演示")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.surface.opacity(0.55), in: Capsule())
            .accessibilityElement(children: .combine)
            .padding(.top, 4)

            Spacer(minLength: 0)

            if let profile = store.selectedProfile {
                // 中央大人物 Hero（呼吸辉光 + 波纹 + 人物占比）
                VStack(spacing: 6) {
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
                    // 名字（宋体）
                    Text(profile.displayName)
                        .font(DVKCompanionTypography.serifName(26))
                        .foregroundStyle(theme.textPrimary)
                    // 状态区
                    Text(ripplePresentation.statusText)
                        .font(.headline)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceState)
                    // 波形（播放振幅驱动）
                    DVKCompanionMiniWave(
                        active: store.voiceState == .speaking,
                        color: theme.primaryAction,
                        reduceMotion: store.reduceMotionPreview,
                        barCount: 7
                    )
                    .frame(width: 120, height: 20)
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

            Spacer(minLength: 0)

            // 底部控制区：结束通话（产品主按钮）
            DVKIOS26GlassEffectContainer {
                HStack(spacing: 14) {
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
                    .dvkGlassControl(theme: theme, prominent: true)
                }
            }

            // 调试区（Start / Advance 不抢产品主界面）
            HStack(spacing: 10) {
                Button {
                    adapter.refresh()
                    Task { await store.beginVoiceDemo(); adapter.refresh() }
                } label: {
                    Label("开始", systemImage: "mic.fill")
                }
                .disabled(!store.canStartVoice)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceStart)
                .dvkGlassControl(theme: theme)

                Button {
                    store.advanceVoiceDemo()
                    adapter.refresh()
                } label: {
                    Label("推进状态", systemImage: "arrow.right.circle.fill")
                }
                .disabled(store.voiceState == .idle || store.voiceState == .ended)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceAdvance)
                .dvkGlassControl(theme: theme)

                if store.generating == .failed {
                    Button("重试回顾") {
                        Task { await store.retryReviewGeneration(); adapter.refresh() }
                    }
                    .dvkGlassControl(theme: theme)
                }
            }
            .font(.caption)
            .opacity(0.85)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
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
                            Text("你的本地陪伴角色")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
            // 分组卡片：默认角色
            Section("默认角色") {
                Picker("角色", selection: Binding(get: { store.selectedProfileID ?? "" }, set: { store.selectPreviewProfile(id: $0); store.confirmProfileSelection(); adapter.refresh() })) {
                    ForEach(store.profiles) { Text($0.displayName).tag($0.id) }
                }
            }
            // 分组卡片：外观
            Section("外观") {
                Picker("主题", selection: Binding(get: { store.appearance }, set: { store.setAppearance($0); adapter.refresh() })) {
                    ForEach(DVKCompanionAppearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("减少动态效果", isOn: Binding(get: { store.reduceMotionPreview }, set: { store.setReduceMotionPreview($0); adapter.refresh() }))
                Text("支持动态字体、旁白与减少动态效果。").font(.footnote)
            }
            // 分组卡片：连接
            Section("连接") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(adapter.runtimeConfiguration.statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(theme.textPrimary)
                    Text(adapter.hasLiveToken
                         ? "安全存储中已有私有令牌。"
                         : "未存储令牌。实时对话需要令牌与实时构建配置。")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.settingsConnection)
                NavigationLink("设备绑定") {
                    DVKDeviceBindingView(
                        configuration: adapter.runtimeConfiguration,
                        tokenStore: adapter.tokenStore
                    )
                }
                Button("清除已存令牌") {
                    try? adapter.tokenStore.clear()
                    adapter.refresh()
                }
                .disabled(!adapter.hasLiveToken)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.settingsTokenClear)
                if !adapter.runtimeConfiguration.buildSHA.isEmpty {
                    Text("构建 \(adapter.runtimeConfiguration.buildSHA) · \(adapter.runtimeConfiguration.buildTime)")
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            // 分组卡片：隐私
            Section("隐私") {
                Button(store.privacy == .allowed ? "预览受限隐私" : "重新授权") {
                    if store.privacy == .allowed { store.setPrivacy(.limited) } else { store.reauthorize() }
                    adapter.refresh()
                }
                .accessibilityIdentifier(store.privacy == .allowed ? DVKCompanionAccessibilityID.privacyLimited : DVKCompanionAccessibilityID.reauthorize)
            }
            // 分组卡片：模拟实验室
            Section("模拟实验室") {
                DVKMockLabView(adapter: adapter)
            }
            // 分组卡片：关于
            Section("关于") {
                Text("DVK Companion 仅本地运行、与供应商无关，使用四只虚构的公共角色。不含任何生产身份、提示词、令牌或资源。")
            }
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .scrollContentBackground(.hidden)
        .listRowBackground(theme.surface)
        .foregroundStyle(theme.textPrimary)
        .tint(theme.primaryAction)
        .background(theme.pageBackground)
        .dvkIOS26NavigationChrome(theme: theme)
        .navigationTitle("我的")
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
        VStack(spacing: 0) {
            // 页面标题区（宋体大标题 + 副标题）
            VStack(alignment: .leading, spacing: 6) {
                Text("陪伴回顾")
                    .font(DVKCompanionTypography.serifDisplay(32))
                    .foregroundStyle(theme.textPrimary)
                Text("每一次对话，都值得被记住。")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if store.reviews.isEmpty {
                // 诚实空状态（程序化头像 + 标题 + 说明，不伪造记录）
                Spacer(minLength: 24)
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
                    Text("陪伴记录尚未开放")
                        .font(DVKCompanionTypography.serifName(22))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("完成一次本地会话后，回顾会显示在这里。")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("companion.reviews.empty")
                Spacer(minLength: 80)
            } else {
                // 回顾卡片列表
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
        .navigationTitle("回顾")
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
