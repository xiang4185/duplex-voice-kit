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
    private let openConversation: () -> Void

    @State private var appeared = false
    @State private var avatarBreath = false
    @State private var greetingIndex = 0
    @State private var greetingTimer: Timer?
    @State private var showPrivacyConfirm = false

    private let greetings: [(text: String, icon: String)] = [
        ("在呢", "sun.max.fill"),
        ("想你了", "moon.stars.fill"),
        ("一直在", "star.fill")
    ]
    private let heroSize: CGFloat = 200

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
        let style = DVKCatStyle(theme: theme)
        let reduced = systemReduceMotion || store.reduceMotionPreview
        let privacyRevealed = store.privacy == .allowed

        ZStack {
            // 有机渐变背景（参考壳 Mesh，静态：保留颜色渐变，无 KeyframeAnimator）
            DVKBackgroundMeshView(mode: .home, theme: theme, staticMode: true)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶栏：设置按钮（齿轮）
                HStack {
                    Button {
                        DVKCatHaptics.action()
                        store.setSelectedTab(.settings)
                        adapter.refresh()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(style.textSecondary)
                            .frame(width: 40, height: 40)
                            .background(style.surface.opacity(0.7), in: Circle())
                            .overlay(Circle().stroke(style.border, lineWidth: 1))
                    }
                    .accessibilityLabel("设置")
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.homeSettings)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -8)
                .animation(.easeOut(duration: 0.4).delay(0.05), value: appeared)

                Spacer(minLength: 0)

                // 中央：柔光晕 + 完整形象（portrait 2:3 + 底部光斑）
                // halo 直径自适应容器宽度，避免大圆环溢出屏幕形成游离圆环
                GeometryReader { geometry in
                    let haloDiameter = min(380, max(240, geometry.size.width))
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [style.roleGold.opacity(0.30), style.primarySoft.opacity(0.15), .clear],
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 200
                                )
                            )
                            .frame(width: haloDiameter, height: haloDiameter)
                            .accessibilityHidden(true)

                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [style.heroGlow, style.heroGlow.opacity(0.4), .clear],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 140
                                )
                            )
                            .frame(width: min(300, geometry.size.width * 0.92), height: 60)
                            .offset(y: heroSize * 0.55)
                            .blur(radius: 24)
                            .opacity(0.85)
                            .accessibilityHidden(true)

                        if let profile = store.selectedProfile {
                            DVKCatAvatarView(
                                profile: profile,
                                size: heroSize,
                                revealed: privacyRevealed
                            ) {
                                showPrivacyConfirm = true
                            }
                            .scaleEffect(avatarBreath ? 1.012 : 0.988)
                            .offset(y: avatarBreath ? -3 : 0)
                            .animation(
                                reduced ? nil : .easeInOut(duration: DVKCatStyle.avatarBreathDuration).repeatForever(autoreverses: true),
                                value: avatarBreath
                            )
                            .onAppear { avatarBreath = true }
                            .accessibilityIdentifier(DVKCompanionAccessibilityID.characterPresentation)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: heroSize * 3.0 / 2.0 + 40)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.94)
                .animation(.spring(response: DVKCatStyle.entranceDuration, dampingFraction: 0.82).delay(0.15), value: appeared)

                // 状态点（静态）+ 状态文案 + 静态迷你波形（无 Timer 刷新）
                HStack(spacing: 10) {
                    sonarDot(style: style)
                    Text("正在陪你")
                        .font(style.captionFont)
                        .foregroundStyle(style.textSecondary)
                    DVKCompanionMiniWave(
                        active: true,
                        color: theme.primaryAction,
                        reduceMotion: true,
                        barCount: 5
                    )
                    .frame(width: 44, height: 16)
                    .opacity(0.75)
                }
                .padding(.top, 4)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(DVKCompanionAccessibilityID.homeStatus)

                if let profile = store.selectedProfile {
                    // 宋体角色名（静态，跟随预览角色；无 tracking 呼吸动画）
                    Text(DVKCatStyle.displayName(for: profile))
                        .font(style.title1Font)
                        .foregroundStyle(style.textPrimary)
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)

                    // 时段问候文案轮换（9s）
                    HStack(spacing: 6) {
                        Text(greetings[greetingIndex].text)
                            .font(style.subheadFont)
                            .foregroundStyle(style.textSecondary)
                        Image(systemName: greetings[greetingIndex].icon)
                            .font(.system(size: 13))
                            .foregroundStyle(style.roleGold)
                    }
                    .padding(.top, 6)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)
                    .onAppear {
                        guard !reduced else { return }
                        greetingTimer?.invalidate()
                        greetingTimer = Timer.scheduledTimer(withTimeInterval: 9, repeats: true) { _ in
                            withAnimation(.easeInOut(duration: 0.6)) {
                                greetingIndex = (greetingIndex + 1) % greetings.count
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                if let profile = store.selectedProfile {
                    // 唯一主操作：语音聊天（大胶囊 CTA）
                    Button(action: {
                        DVKCatHaptics.comfort()
                        store.setMode(.voice)
                        adapter.refresh()
                        openConversation()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 17, weight: .medium))
                            Text(DVKCatStyle.introCopy(for: profile))
                                .font(style.headlineFont)
                        }
                        .foregroundStyle(style.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .contentShape(Capsule())
                        .background(style.primary, in: Capsule())
                        .shadow(color: style.ctaShadow.opacity(0.35), radius: 18, x: 0, y: 8)
                        .shadow(color: theme.primaryAction.opacity(0.18), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(DVKCatPressableButtonStyle())
                    .padding(.horizontal, 40)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 14)
                    .animation(.spring(response: DVKCatStyle.entranceDuration, dampingFraction: 0.75).delay(0.5), value: appeared)
                    .accessibilityLabel(DVKCatStyle.introCopy(for: profile))
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.homePrimaryCTA)

                    // 文字聊天入口（克制次级卡片，替代原“陪伴记录”卡位置）
                    textChatCard(style: style, theme: theme) {
                        store.setMode(.text)
                        adapter.refresh()
                        openConversation()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.4).delay(0.7), value: appeared)
                }
            }
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .sheet(isPresented: $showPrivacyConfirm) {
            DVKCatPrivacyConfirmView(
                onAgree: { store.reauthorize(); adapter.refresh() },
                onDecline: { store.setPrivacy(.limited); adapter.refresh() }
            )
            .presentationDetents([.medium])
        }
        .onAppear { appeared = true }
        .onDisappear {
            greetingTimer?.invalidate()
            greetingTimer = nil
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier(DVKCompanionAccessibilityID.home)
    }

    // MARK: 静态状态点（无声呐扩散动画，避免游离图层与持续刷新）
    private func sonarDot(style: DVKCatStyle) -> some View {
        ZStack {
            Circle()
                .stroke(style.online.opacity(0.5), lineWidth: 1.5)
                .frame(width: 18, height: 18)
            Circle()
                .fill(style.online)
                .frame(width: 7, height: 7)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    /// 次级文字聊天入口：克制卡片（气泡图标 + 标题 + 副标题 + chevron），
    /// 视觉层级明显低于语音主按钮。
    private func textChatCard(
        style: DVKCatStyle,
        theme: DVKCompanionTheme,
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
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: DVKCatStyle.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DVKCatStyle.Radius.card, style: .continuous).stroke(theme.border, lineWidth: 1))
        .dvkCatCardTopHighlight()
        .shadow(color: theme.shadow.opacity(0.5), radius: 10, x: 0, y: 3)
        .accessibilityLabel("文字聊天，安静地打字聊聊")
        .accessibilityIdentifier("companion.home.textChat")
    }
}

@MainActor
public struct DVKCompanionProfilesView: View {
    @ObservedObject private var adapter: DVKCompanionStoreAdapter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var scrollPosition: String?
    @State private var showPrivacyConfirm = false
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
        let style = DVKCatStyle(theme: theme)
        let reduced = systemReduceMotion || store.reduceMotionPreview

        ZStack {
            DVKBackgroundMeshView(mode: .home, theme: theme, staticMode: true)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 标题区（宋体大标题 + 单行副标题，副标题做最小对比度增强）
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前陪伴角色")
                        .font(style.title1Font)
                        .foregroundStyle(style.textPrimary)
                    Text("左右滑动查看，确认后开始聊天")
                        .font(style.subheadFont)
                        .foregroundStyle(style.textPrimary.opacity(0.85))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // 可左右分页滑动的大角色主卡（原版角色卡结构，外层多卡滑动）
                roleSwipeCarousel(
                    store: store,
                    theme: theme,
                    style: style,
                    reduced: reduced
                )

                // 底部固定角色摘要操作条（原版 startBar）
                roleActionBar(store: store, theme: theme, style: style)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                if !store.canSelectProfiles {
                    Text("会话进行中，暂不能切换角色。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .foregroundStyle(theme.textPrimary)
        .tint(theme.primaryAction)
        .animation(store.reduceMotionPreview ? nil : .easeInOut(duration: 0.25), value: store.previewProfileID)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPrivacyConfirm) {
            DVKCatPrivacyConfirmView(
                onAgree: { store.reauthorize(); adapter.refresh() },
                onDecline: { store.setPrivacy(.limited); adapter.refresh() }
            )
            .presentationDetents([.medium])
        }
        .accessibilityIdentifier(DVKCompanionAccessibilityID.profiles)
    }

    // MARK: 左右滑动角色主卡（分页停靠，相邻轻微露出；滑动只更新预览，不直接确认）
    @MainActor
    private func roleSwipeCarousel(
        store: DVKCompanionStore,
        theme: DVKCompanionTheme,
        style: DVKCatStyle,
        reduced: Bool
    ) -> some View {
        GeometryReader { geometry in
            let cardWidth = max(260, geometry.size.width - 20 * 2 - 28)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(store.profiles) { profile in
                        roleHeroCard(
                            profile: profile,
                            store: store,
                            style: style,
                            isPreview: profile.id == store.previewProfileID
                        )
                        .frame(width: cardWidth)
                        .id(profile.id)
                    }
                }
                .scrollTargetLayout()
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

    // MARK: 大人物主卡（原版角色卡：badge + 渐变 + halo + 大人物 + 名字 + chips + 简介 + 通话胶囊）
    @MainActor
    private func roleHeroCard(
        profile: DVKCompanionProfile,
        store: DVKCompanionStore,
        style: DVKCatStyle,
        isPreview: Bool
    ) -> some View {
        let profileTheme = DVKCompanionThemeResolver.resolve(profile: profile, appearance: store.appearance)
        let profileStyle = DVKCatStyle(theme: profileTheme)
        let privacyRevealed = store.privacy == .allowed
        return VStack(spacing: 12) {
            Text("当前角色")
                .font(style.captionFont)
                .foregroundStyle(profileStyle.primary700)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(profileStyle.primary100, in: Capsule())
                .padding(.top, 14)

            // 大尺寸人物（完整形象；点击：未解锁 → 隐私确认）
            ZStack {
                // 角色渐变背景（上半）
                profileStyle.charWarmGradient
                    .opacity(0.16)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: DVKCatStyle.Radius.characterCard, style: .continuous))

                // 角色卡 halo 光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [profileStyle.roleGold.opacity(0.28), profileStyle.primarySoft.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 110
                        )
                    )
                    .frame(width: 240, height: 240)

                DVKCatAvatarView(
                    profile: profile,
                    size: 190,
                    revealed: privacyRevealed
                ) {
                    if store.privacy == .limited {
                        showPrivacyConfirm = true
                    }
                }
            }
            .padding(.top, 4)

            Text(DVKCatStyle.displayName(for: profile))
                .font(style.title2Font)
                .foregroundStyle(profileStyle.textPrimary)

            HStack(spacing: 6) {
                ForEach(profile.personalityTags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(style.captionFont)
                        .foregroundStyle(profileStyle.primary700)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(profileStyle.primary100, in: Capsule())
                }
            }

            Text(profile.shortSummary)
                .font(style.subheadFont)
                .foregroundStyle(profileStyle.textSecondary)
                .padding(.top, 2)

            // 支持实时通话
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                Text(profile.capabilities.contains(.voice) ? "支持实时通话" : "文字陪伴")
                    .font(style.captionFont)
            }
            .foregroundStyle(profileStyle.primary700)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(profileStyle.primary100.opacity(0.7), in: Capsule())
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
        .background(profileStyle.surface, in: RoundedRectangle(cornerRadius: DVKCatStyle.Radius.characterCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DVKCatStyle.Radius.characterCard, style: .continuous)
                .stroke(isPreview ? profileTheme.primaryAction.opacity(0.7) : profileStyle.border, lineWidth: isPreview ? 2 : 1)
        )
        .dvkCatCardTopHighlight()
        .shadow(color: profileStyle.shadowFloating, radius: 20, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.accessibilityDescription)
        .accessibilityIdentifier("companion.profile.hero.\(profile.id)")
    }

    // MARK: 底部固定角色摘要操作条（原版 startBar：小头像 + 名称/标签 + 主按钮）
    @MainActor
    private func roleActionBar(
        store: DVKCompanionStore,
        theme: DVKCompanionTheme,
        style: DVKCatStyle
    ) -> some View {
        guard let profile = store.previewProfile else {
            return AnyView(EmptyView())
        }
        let profileTheme = DVKCompanionThemeResolver.resolve(profile: profile, appearance: store.appearance)
        let profileStyle = DVKCatStyle(theme: profileTheme)
        let isCurrent = profile.id == store.selectedProfileID
        return AnyView(
            HStack(spacing: 14) {
                // 小头像（52pt 专用：小猫用 AI 缩略图，其他角色用程序化圆形头像，非画布裁切）
                DVKCatCompactAvatar(
                    profile: profile,
                    size: 52,
                    revealed: store.privacy == .allowed
                )
                .frame(width: 52, height: 52)

                // 角色信息：名称单行 + 最多两标签单行
                VStack(alignment: .leading, spacing: 4) {
                    Text(DVKCatStyle.displayName(for: profile))
                        .font(style.headlineFont)
                        .foregroundStyle(profileStyle.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        ForEach(profile.personalityTags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(style.captionFont)
                                .foregroundStyle(profileStyle.primary700)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(profileStyle.primary100, in: Capsule())
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)

                // 主按钮：使用此角色 / 开始聊天
                Button {
                    if isCurrent {
                        openConversation()
                    } else {
                        store.confirmProfileSelection()
                        adapter.refresh()
                    }
                } label: {
                    Text(isCurrent ? "开始聊天" : "使用此角色")
                        .font(style.headlineFont)
                        .foregroundStyle(profileStyle.onPrimary)
                        .padding(.horizontal, 20)
                        .frame(height: 48)
                        .background(profileStyle.primary, in: Capsule())
                        .shadow(color: profileStyle.ctaShadow, radius: 10, x: 0, y: 5)
                }
                .buttonStyle(DVKCatPressableButtonStyle())
                .lineLimit(1)
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
            .padding(14)
            .background(profileTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: DVKCatStyle.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DVKCatStyle.Radius.card, style: .continuous).stroke(profileStyle.border, lineWidth: 1))
            .dvkCatCardTopHighlight()
            .shadow(color: profileStyle.shadowRaised, radius: 12, x: 0, y: 4)
            .accessibilityIdentifier(DVKCompanionAccessibilityID.profilePreview)
        )
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
            // 完整消息滚动区（参考壳聊天页比例：气泡 + 用户右/助手左）
            ScrollView(showsIndicators:false){
                LazyVStack(alignment:.leading,spacing:10){
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
                .padding()
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)

            // 固定底部输入区（参考壳 HStack + 发送按钮）
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

            // 低层级辅助调试区（Mock 失败控制，不抢主界面观感）
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
    @State private var isMuted = false
    @State private var showHangupConfirm = false
    @State private var topicIndex = 0
    private let topics = [
        "今天过得怎么样？",
        "最近有没有什么开心的小事？",
        "周末想怎么安排？",
        "有没有什么想聊又没处说的话题？"
    ]
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
        let style = DVKCatStyle(theme: theme)
        let ripplePresentation = DVKCharacterVoiceRipplePresentation(
            amplitude: store.playbackAmplitude,
            voiceState: store.voiceState,
            reduceMotion: store.reduceMotionPreview,
            staticMode: store.presentationMode == .staticFallback,
            hasError: store.voiceError != nil
        )
        ZStack {
            DVKBackgroundMeshView(mode: .call, theme: theme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部：关闭（xmark → 挂断确认）+ 状态行
                HStack {
                    Button {
                        DVKCatHaptics.action()
                        withAnimation(.easeOut(duration: 0.28)) { showHangupConfirm = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(style.textSecondary)
                            .frame(width: 40, height: 40)
                            .background(style.surface.opacity(0.7), in: Circle())
                            .overlay(Circle().stroke(style.border, lineWidth: 1))
                    }
                    .accessibilityLabel("结束通话")
                    .accessibilityIdentifier("call.close")
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // 状态行（状态点 + 状态文案）
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(callStatusColor(store: store, style: style))
                            .frame(width: 7, height: 7)
                        Text(callStatusText(store: store, style: style))
                            .font(style.captionFont)
                            .foregroundStyle(style.textSecondary)
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)

                Text("直接说话就好，小猫在听")
                    .font(style.captionFont)
                    .foregroundStyle(style.textTertiary)
                    .padding(.top, 6)

                Spacer(minLength: 0)

                if let profile = store.selectedProfile {
                    // 中央形象（halo + 公共波纹 + AI 人物 portrait）
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [style.roleGold.opacity(0.26), style.primarySoft.opacity(0.12), .clear],
                                    center: .center,
                                    startRadius: 40,
                                    endRadius: 150
                                )
                            )
                            .frame(width: 300, height: 300)
                        DVKCharacterVoiceRipple(presentation: ripplePresentation, theme: theme)
                        DVKCatAvatarView(
                            profile: profile,
                            size: 220,
                            revealed: store.privacy == .allowed
                        )
                    }
                    .frame(height: 220 * 3.0 / 2.0 + 16)

                    Text(DVKCatStyle.displayName(for: profile))
                        .font(style.title3Font)
                        .foregroundStyle(style.textPrimary)
                        .padding(.top, 4)

                    // 状态区
                    Text(ripplePresentation.statusText)
                        .font(style.subheadFont)
                        .foregroundStyle(style.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceState)
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
                        .padding(.top, 6)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceError)
                }

                Spacer(minLength: 0)

                // 底部控制区（参考壳：聊天提示 + 波形 + 三按钮：静音 / 挂断 / 换个提示）
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("聊天提示")
                            .font(style.captionFont)
                            .foregroundStyle(style.textTertiary)
                        Text(topics[topicIndex])
                            .font(style.captionFont)
                            .foregroundStyle(style.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(style.surface.opacity(0.6), in: Capsule())

                    // 波形（真实 playbackAmplitude 驱动）
                    DVKCatVoiceWaveform(
                        active: isVoiceActive(store.voiceState),
                        level: Double(store.playbackAmplitude)
                    )
                    .frame(height: 36)
                    .accessibilityHidden(true)

                    // 三按钮
                    HStack(spacing: 36) {
                        controlButton(
                            icon: isMuted ? "mic.slash.fill" : "mic.fill",
                            title: isMuted ? "取消静音" : "静音",
                            color: isMuted ? style.primaryPressed : style.textPrimary,
                            background: style.surface.opacity(0.8),
                            identifier: DVKCompanionAccessibilityID.voiceMute,
                            style: style
                        ) {
                            DVKCatHaptics.action()
                            withAnimation(.easeInOut(duration: 0.2)) { isMuted.toggle() }
                        }

                        controlButton(
                            icon: "phone.down.fill",
                            title: "挂断",
                            color: .white,
                            background: style.danger,
                            identifier: DVKCompanionAccessibilityID.voiceEnd,
                            style: style
                        ) {
                            DVKCatHaptics.action()
                            withAnimation(.easeOut(duration: 0.28)) { showHangupConfirm = true }
                        }

                        controlButton(
                            icon: "lightbulb",
                            title: "换个提示",
                            color: style.textPrimary,
                            background: style.surface.opacity(0.8),
                            identifier: "call.topic",
                            style: style
                        ) {
                            DVKCatHaptics.action()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                topicIndex = (topicIndex + 1) % topics.count
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .layoutPriority(1)

                // 低层级调试区（Mock Start/Advance，不抢产品主界面）
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
        }
        .overlay {
            if showHangupConfirm {
                hangupConfirmOverlay(store: store, style: style)
            }
        }
        .onAppear {
            // Mock 下进入页面自动开始演示（模拟参考壳“进入即连接”的节奏）
            if store.voiceState == .idle {
                Task { await store.beginVoiceDemo(); adapter.refresh() }
            }
        }
    }

    private func isVoiceActive(_ state: DVKCompanionVoiceState) -> Bool {
        switch state {
        case .idle, .ended: return false
        default: return true
        }
    }

    // MARK: 通话状态文案（纯 UI 映射，Mock 状态）
    private func callStatusText(store: DVKCompanionStore, style: DVKCatStyle) -> String {
        switch store.voiceState {
        case .idle: return "等待开始"
        case .connecting: return "正在连接"
        case .listening: return "小猫正在听你说话"
        case .processing: return "小猫正在想"
        case .speaking: return "小猫正在说话"
        case .ended: return "已结束"
        }
    }

    // MARK: 通话状态点颜色
    private func callStatusColor(store: DVKCompanionStore, style: DVKCatStyle) -> Color {
        switch store.voiceState {
        case .idle, .ended: return style.textTertiary
        case .connecting, .processing: return style.textSecondary
        case .listening, .speaking: return style.online
        }
    }

    // MARK: 控制圆钮（参考壳 controlButton）
    private func controlButton(
        icon: String,
        title: String,
        color: Color,
        background: Color,
        identifier: String,
        style: DVKCatStyle,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 60, height: 60)
                    .background(background, in: Circle())
                    .overlay(Circle().stroke(style.border, lineWidth: 1))
                    .shadow(color: style.shadowRaised, radius: 8, x: 0, y: 3)
            }
            .buttonStyle(DVKCatPressableButtonStyle())
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
            Text(title)
                .font(style.captionFont)
                .foregroundStyle(style.textSecondary)
        }
    }

    // MARK: 挂断确认浮层（参考壳视觉：再聊一会儿 / 结束通话）
    private func hangupConfirmOverlay(store: DVKCompanionStore, style: DVKCatStyle) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.2)) { showHangupConfirm = false }
                }
            VStack(spacing: 18) {
                Text("确定要结束这次陪伴吗？")
                    .font(style.title3Font)
                    .foregroundStyle(style.textPrimary)
                Text("今天聊得刚刚好，随时回来找我。")
                    .font(style.subheadFont)
                    .foregroundStyle(style.textSecondary)
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeIn(duration: 0.2)) { showHangupConfirm = false }
                    } label: {
                        Text("再聊一会儿")
                            .font(style.subheadFont)
                            .foregroundStyle(style.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(style.surface, in: Capsule())
                            .overlay(Capsule().stroke(style.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hangup.cancel")

                    Button {
                        DVKCatHaptics.action()
                        withAnimation(.easeIn(duration: 0.2)) { showHangupConfirm = false }
                        Task {
                            await store.endVoiceDemo()
                            adapter.refresh()
                            onEnded()
                        }
                    } label: {
                        Text("结束通话")
                            .font(style.subheadFont)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(style.danger, in: Capsule())
                            .shadow(color: style.danger.opacity(0.30), radius: 14, x: 0, y: 6)
                            .shadow(color: style.danger.opacity(0.15), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hangup.confirm")
                }
            }
            .padding(24)
            .background(style.surface, in: RoundedRectangle(cornerRadius: DVKCatStyle.Radius.card, style: .continuous))
            .dvkCatCardTopHighlight()
            .shadow(color: style.shadowOverlay, radius: 32, x: 0, y: 12)
            .padding(.horizontal, 40)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .transition(.opacity)
        .accessibilityIdentifier("hangup.overlay")
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
    @State private var showAboutSheet = false
    @State private var showHelpSheet = false
    @State private var showPrivacySheet = false

    public init(adapter:DVKCompanionStoreAdapter){self.adapter=adapter}
    public var body: some View {
        let store=adapter.store
        let theme=DVKCompanionThemeResolver.resolve(profile:store.selectedProfile, appearance:store.appearance)
        let style=DVKCatStyle(theme: theme)
        ZStack {
            theme.pageBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators:false){
                VStack(alignment:.leading,spacing:0){
                    // 用户行（参考壳：AI 缩略头像 + 名字 + 副标题）
                    if let profile = store.selectedProfile {
                        HStack(spacing:14){
                            DVKCatAvatarView(
                                profile: profile,
                                size: 56,
                                revealed: store.privacy == .allowed
                            )
                            VStack(alignment:.leading,spacing:4){
                                Text(DVKCatStyle.displayName(for: profile))
                                    .font(style.title3Font)
                                    .foregroundStyle(style.textPrimary)
                                Text("随时回来和小猫说说话")
                                    .font(style.captionFont)
                                    .foregroundStyle(style.textSecondary)
                                    .fixedSize(horizontal:false,vertical:true)
                            }
                            Spacer(minLength:0)
                        }
                        .padding(.horizontal,20)
                        .padding(.top,20)
                    }

                    // 默认角色卡
                    settingsCard(style: style) {
                        settingsRow(icon: "pawprint.fill", title: "默认角色", detail: DVKCatStyle.displayName(for: store.selectedProfile ?? store.previewProfile ?? store.profiles[0]), style: style)
                        Divider().overlay(style.border).padding(.leading, 60)
                        Picker("角色", selection: Binding(get: { store.selectedProfileID ?? "" }, set: { store.selectPreviewProfile(id: $0); store.confirmProfileSelection(); adapter.refresh() })) {
                            ForEach(store.profiles) { Text(DVKCatStyle.displayName(for: $0)).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                        .tint(theme.primaryAction)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 52)
                        .accessibilityIdentifier("settings.defaultRole")
                    }
                    .padding(.top, 20)

                    // 外观卡
                    settingsCard(style: style) {
                        settingsRow(icon: "paintbrush.fill", title: "外观主题", detail: store.appearance.rawValue.capitalized, style: style)
                        Divider().overlay(style.border).padding(.leading, 60)
                        Picker("主题", selection: Binding(get: { store.appearance }, set: { store.setAppearance($0); adapter.refresh() })) {
                            ForEach(DVKCompanionAppearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(theme.primaryAction)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 52)
                        Divider().overlay(style.border).padding(.leading, 60)
                        Toggle("减少动态效果", isOn: Binding(get: { store.reduceMotionPreview }, set: { store.setReduceMotionPreview($0); adapter.refresh() }))
                            .tint(theme.primaryAction)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 52)
                            .accessibilityIdentifier("settings.reduceMotion")
                    }
                    .padding(.top, 16)

                    // 连接卡（参考壳 statsCard 样式 + 公共连接能力）
                    settingsCard(style: style) {
                        VStack(alignment:.leading,spacing:6){
                            HStack(alignment:.top,spacing:12){
                                Image(systemName:"antenna.radiowaves.left.and.right")
                                    .font(.system(size:20))
                                    .foregroundStyle(style.primary)
                                    .padding(.top,2)
                                VStack(alignment:.leading,spacing:6){
                                    Text(adapter.runtimeConfiguration.statusDescription)
                                        .font(style.subheadFont)
                                        .foregroundStyle(style.textPrimary)
                                    Text(adapter.hasLiveToken
                                         ? "安全存储中已有私有令牌。"
                                         : "未存储令牌。实时对话需要令牌与实时构建配置。")
                                        .font(style.captionFont)
                                        .foregroundStyle(style.textSecondary)
                                        .lineSpacing(3)
                                }
                                Spacer(minLength:0)
                            }
                        }
                        .padding(18)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.settingsConnection)
                        Divider().overlay(style.border).padding(.leading, 60)
                        NavigationLink("设备绑定") {
                            DVKDeviceBindingView(
                                configuration: adapter.runtimeConfiguration,
                                tokenStore: adapter.tokenStore
                            )
                        }
                        .foregroundStyle(style.textPrimary)
                        .font(style.bodyFont)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 52)
                        Divider().overlay(style.border).padding(.leading, 60)
                        Button("清除已存令牌") {
                            try? adapter.tokenStore.clear()
                            adapter.refresh()
                        }
                        .disabled(!adapter.hasLiveToken)
                        .foregroundStyle(adapter.hasLiveToken ? style.textPrimary : style.textTertiary)
                        .font(style.bodyFont)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 52)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.settingsTokenClear)
                        if !adapter.runtimeConfiguration.buildSHA.isEmpty {
                            Text("构建 \(adapter.runtimeConfiguration.buildSHA) · \(adapter.runtimeConfiguration.buildTime)")
                                .font(style.captionFont)
                                .foregroundStyle(style.textTertiary)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 14)
                        }
                    }
                    .padding(.top, 16)

                    // 隐私与授权（参考壳 privacyGroup）
                    Text("隐私与授权")
                        .font(style.title3Font)
                        .foregroundStyle(style.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    settingsCard(style: style) {
                        Toggle("显示角色形象", isOn: Binding(
                            get: { store.privacy == .allowed },
                            set: { newValue in
                                if newValue { store.reauthorize() } else { store.setPrivacy(.limited) }
                                adapter.refresh()
                            }
                        ))
                        .tint(theme.primaryAction)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 60)
                        .accessibilityLabel("显示角色形象")
                        .accessibilityIdentifier(store.privacy == .allowed ? DVKCompanionAccessibilityID.privacyAllowed : DVKCompanionAccessibilityID.privacyLimited)
                        Divider().overlay(style.border).padding(.leading, 60)
                        HStack(spacing:14){
                            Image(systemName:"waveform.and.mic")
                                .font(.system(size:20))
                                .foregroundStyle(style.info)
                                .frame(width:36)
                            VStack(alignment:.leading,spacing:3){
                                Text("实时语音服务")
                                    .font(style.bodyFont)
                                    .foregroundStyle(style.textPrimary)
                                Text("关闭形象显示后，所有头像会保持模糊。")
                                    .font(style.captionFont)
                                    .foregroundStyle(style.textSecondary)
                            }
                            Spacer(minLength:0)
                        }
                        .padding(.horizontal,18)
                        .frame(minHeight:60)
                    }
                    .padding(.horizontal,20)
                    .padding(.top,12)

                    // 模拟实验室
                    Text("模拟实验室")
                        .font(style.title3Font)
                        .foregroundStyle(style.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    settingsCard(style: style) {
                        DVKMockLabView(adapter: adapter)
                            .padding(18)
                    }
                    .padding(.horizontal,20)
                    .padding(.top,12)

                    // 关于（参考壳 aboutGroup，接入公共彩蛋卡）
                    Text("关于")
                        .font(style.title3Font)
                        .foregroundStyle(style.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    settingsCard(style: style) {
                        aboutRow(title: "关于本展示", detail: "DVK Companion 版本 1.0 (0)", style: style) { showAboutSheet = true }
                        Divider().overlay(style.border).padding(.leading, 20)
                        aboutRow(title: "帮助与反馈", detail: nil, style: style) { showHelpSheet = true }
                        Divider().overlay(style.border).padding(.leading, 20)
                        aboutRow(title: "隐私政策", detail: nil, style: style) { showPrivacySheet = true }
                    }
                    .padding(.horizontal,20)
                    .padding(.top,12)
                    .padding(.bottom,40)
                }
            }
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .foregroundStyle(theme.textPrimary)
        .tint(theme.primaryAction)
        .dvkIOS26NavigationChrome(theme: theme)
        .navigationTitle("我的")
        .sheet(isPresented: $showAboutSheet) {
            DVKEasterEggCard(egg: .about, onClose: { showAboutSheet = false })
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showHelpSheet) {
            DVKEasterEggCard(egg: .help, onClose: { showHelpSheet = false })
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPrivacySheet) {
            DVKEasterEggCard(egg: .privacy, onClose: { showPrivacySheet = false })
                .presentationDetents([.medium])
        }
        .accessibilityIdentifier(DVKCompanionAccessibilityID.settings)
    }

    // MARK: 通用分组卡片（参考壳卡片质感：圆角 + 顶部高光 + 阴影）
    @ViewBuilder
    private func settingsCard<Content: View>(style: DVKCatStyle, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .background(style.surface, in: RoundedRectangle(cornerRadius: DVKCatStyle.Radius.card, style: .continuous))
            .dvkCatCardTopHighlight()
            .shadow(color: style.shadowRaised, radius: 12, x: 0, y: 3)
            .padding(.horizontal, 20)
    }

    // MARK: 图标 + 标题 + 说明行
    @ViewBuilder
    private func settingsRow(icon: String, title: String, detail: String, style: DVKCatStyle) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(style.info)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(style.bodyFont)
                    .foregroundStyle(style.textPrimary)
                Text(detail)
                    .font(style.captionFont)
                    .foregroundStyle(style.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
    }

    // MARK: 关于行（参考壳 aboutRow）
    @ViewBuilder
    private func aboutRow(title: String, detail: String?, style: DVKCatStyle, action: @escaping () -> Void) -> some View {
        Button {
            DVKCatHaptics.action()
            action()
        } label: {
            HStack {
                Text(title)
                    .font(style.bodyFont)
                    .foregroundStyle(style.textPrimary)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(style.captionFont)
                        .foregroundStyle(style.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style.textTertiary)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
        }
        .buttonStyle(DVKCatPressableCardStyle())
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier("settings.about.\(title)")
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
        let style = DVKCatStyle(theme: theme)
        ZStack {
            theme.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部标题（参考壳 ReviewView：标题 + 副标题）
                VStack(alignment: .leading, spacing: 6) {
                    Text("陪伴回顾")
                        .font(style.title1Font)
                        .foregroundStyle(style.textPrimary)
                    Text("每一次对话，都值得被记住。")
                        .font(style.subheadFont)
                        .foregroundStyle(style.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                if store.reviews.isEmpty {
                    // 诚实空状态（头像 + 标题 + 说明，不伪造聊天/情绪/音频记录）
                    Spacer(minLength: 24)
                    VStack(spacing: 16) {
                        if let profile = store.selectedProfile {
                            DVKCatAvatarView(
                                profile: profile,
                                size: 96,
                                revealed: store.privacy == .allowed
                            )
                        }
                        Text("陪伴记录尚未开放")
                            .font(style.title3Font)
                            .foregroundStyle(style.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("当前版本暂不展示聊天或录音历史。")
                            .font(style.subheadFont)
                            .foregroundStyle(style.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 280)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
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
        }
        .safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .scrollContentBackground(.hidden)
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
        .accessibilityIdentifier(DVKCompanionAccessibilityID.reviews)
    }
}
@MainActor
public struct DVKReviewDetailView: View { public let review:DVKCompanionReview; let onDelete:()->Void;let onClose:()->Void; public init(review:DVKCompanionReview,onDelete:@escaping()->Void,onClose:@escaping()->Void){self.review=review;self.onDelete=onDelete;self.onClose=onClose}; public var body:some View{let theme=DVKCompanionThemeResolver.resolve(themeKey:review.profileSnapshot?.themeKey, appearance:.followProfile);NavigationStack{VStack(alignment:.leading,spacing:14){Text(review.title).font(.largeTitle.bold());Text(review.profileSnapshot?.displayName ?? "Mock cat").font(.headline);Text(review.summary);Text(review.source.rawValue.capitalized);Spacer();Button("Delete review",role:.destructive,action:onDelete).accessibilityIdentifier(DVKCompanionAccessibilityID.reviewDelete);Button("Close",action:onClose)}.padding().foregroundStyle(theme.textPrimary).background(theme.pageBackground.ignoresSafeArea()).tint(theme.primaryAction).dvkIOS26NavigationChrome(theme: theme).navigationTitle("Review detail").accessibilityIdentifier(DVKCompanionAccessibilityID.reviewDetail)}}}
#endif
