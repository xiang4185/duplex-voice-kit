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
    public init(store:DVKCompanionStore, live2DHost:(any DVKLive2DCharacterHosting)? = nil){ self.store=store; self.live2DHost=live2DHost; let relay=DVKPlaybackAmplitudeRelay(); playbackAmplitudeRelay=relay; relay.setOnChange{[weak self,weak store] value in Task{@MainActor in store?.receivePlaybackAmplitude(value);self?.refresh()} }; store.setPlaybackAmplitudeInput{[weak relay] value in relay?.playbackAmplitudeDidChange(value)} }
    public convenience init(){ self.init(store:DVKCompanionStore()) }
    public func refresh(){ store.receivePlaybackAmplitude(playbackAmplitudeRelay.currentAmplitude); revision += 1 }
}

@MainActor
public struct DVKCompanionStartupView: View {
    @StateObject private var adapter:DVKCompanionStoreAdapter
    public init(store:DVKCompanionStore){_adapter=StateObject(wrappedValue:DVKCompanionStoreAdapter(store:store))}
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
public struct DVKCompanionHomeView: View {
    @ObservedObject private var adapter:DVKCompanionStoreAdapter
    private let openConversation:()->Void
    public init(adapter:DVKCompanionStoreAdapter,openConversation:@escaping()->Void){self.adapter=adapter;self.openConversation=openConversation}
    public var body:some View {
        let store=adapter.store; let theme=DVKCompanionThemeResolver.resolve(profile:store.selectedProfile, appearance:store.appearance)
        ScrollView {
            VStack(alignment:.leading,spacing:18){
                HStack{VStack(alignment:.leading,spacing:4){Text("A little room for today").font(.system(size:32,weight:.semibold,design:.serif));Text("DVK Companion · Mock only").font(.subheadline).foregroundStyle(.secondary)};Spacer()}.padding(.top,8)
                if let profile=store.selectedProfile {
                    VStack(spacing:8){DVKCharacterPresentationView(profile:profile,state:store.characterState,reduceMotion:store.reduceMotionPreview,staticMode:store.presentationMode == .staticFallback,host:adapter.store.presentationMode == .staticFallback ? nil : adapter.live2DHost).frame(height:230).accessibilityIdentifier(DVKCompanionAccessibilityID.characterPresentation);Text(profile.displayName).font(.title2.bold());Text(profile.personalityTags.joined(separator:"  ·  ")).font(.caption).foregroundStyle(DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).primaryAction);Text(profile.greeting).font(.system(size:18,design:.serif)).multilineTextAlignment(.center).foregroundStyle(.secondary)}
                    .frame(maxWidth:.infinity).padding(18).background(theme.elevatedSurface,in:RoundedRectangle(cornerRadius:28,style:.continuous))
                    DVKIOS26GlassEffectContainer {
                        HStack(spacing:12){homeCTA("Text",icon:"text.bubble.fill"){store.setMode(.text);adapter.refresh();openConversation()};homeCTA("Voice",icon:"waveform"){store.setMode(.voice);adapter.refresh();openConversation()}}
                    }
                    Text(store.lastError ?? "Your selected cat is ready for a gentle mock conversation.").font(.footnote).foregroundStyle(store.lastError == nil ? Color.secondary : Color.red)
                } else { ContentUnavailableView("Choose a cat",systemImage:"pawprint.fill",description:Text("Visit Cats to choose a public mock profile.")) }
                privacyCard(store)
                Text("Quick switch").font(.headline)
                DVKProfileCarousel(adapter:adapter,compact:true,onPreview:{store.setSelectedTab(.profiles);adapter.refresh()})
                VStack(alignment:.leading,spacing:8) {
                    Text("Small public moments").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(DVKCompanionEasterEgg.allCases,id:\.self) { egg in Button(egg.title) { store.presentEasterEgg(egg); adapter.refresh() }.font(.caption).tint(theme.primaryAction).accessibilityLabel(egg.title) } }
                    }
                    if let egg=store.activeEasterEgg { DVKEasterEggCard(egg:egg) { store.dismissEasterEgg(); adapter.refresh() } }
                }.accessibilityIdentifier(DVKCompanionAccessibilityID.cards)
                if let review=store.reviews.first { reviewCard(review) }
            }.padding(20)
        }.safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .background(DVKCompanionThemeResolver.resolve(profile:adapter.store.selectedProfile, appearance:adapter.store.appearance).backgroundGradient.ignoresSafeArea())
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Settings", systemImage: "gearshape") { store.setSelectedTab(.settings); adapter.refresh() }.accessibilityLabel("Open settings") } }
        .accessibilityIdentifier(DVKCompanionAccessibilityID.home)
    }
    private func homeCTA(_ title:String,icon:String,action:@escaping()->Void)->some View { Button(action:action){Label(title,systemImage:icon).frame(maxWidth:.infinity).padding(.vertical,12)}.dvkGlassControl(theme: DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance), prominent: title == "Text") }
    private func privacyCard(_ store:DVKCompanionStore)->some View { let theme=DVKCompanionThemeResolver.resolve(profile:store.selectedProfile, appearance:store.appearance); return HStack{Image(systemName:store.privacy == .allowed ? "checkmark.shield.fill":"lock.shield.fill");Text(store.privacy == .allowed ? "Privacy allowed":"Privacy limited");Spacer();Text("Mock").font(.caption).foregroundStyle(.secondary)}.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:RoundedRectangle(cornerRadius:18)).accessibilityIdentifier(store.privacy == .allowed ? DVKCompanionAccessibilityID.privacyAllowed:DVKCompanionAccessibilityID.privacyLimited) }
    private func reviewCard(_ review:DVKCompanionReview)->some View { let theme=DVKCompanionThemeResolver.resolve(profile:adapter.store.selectedProfile, appearance:adapter.store.appearance); return VStack(alignment:.leading,spacing:6){Text("Latest review").font(.headline);Text(review.title);Text(review.profileSnapshot?.displayName ?? "Mock cat").font(.caption).foregroundStyle(.secondary);Text(review.summary).font(.subheadline).foregroundStyle(.secondary)}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:RoundedRectangle(cornerRadius:20)).accessibilityIdentifier("companion.home.latestReview") }
}

@MainActor
public struct DVKCompanionProfilesView: View {
    @ObservedObject private var adapter:DVKCompanionStoreAdapter
    private let openConversation:()->Void
    public init(adapter:DVKCompanionStoreAdapter, openConversation:@escaping()->Void = {}){self.adapter=adapter;self.openConversation=openConversation}
    public var body:some View {
        let store=adapter.store
        let theme=DVKCompanionThemeResolver.resolve(profile:store.previewProfile, appearance:store.appearance)
        ScrollView {
            VStack(alignment:.leading,spacing:16){
                Text("Choose a cat").font(.system(size:32,weight:.semibold,design:.serif));Text("Four fictional public profiles. The choice is local and reversible.").font(.subheadline).foregroundStyle(.secondary)
                DVKRoleCardCarousel(adapter:adapter, openConversation:openConversation)
                if !store.canSelectProfiles { Text("Profile switching is paused while a message or voice session is active.").font(.footnote).foregroundStyle(.orange) }
                Text("All profiles are mock-only and declare text, voice, and review capabilities.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.safeAreaPadding(.bottom, dvkTabBarBottomContentPadding)
        .foregroundStyle(theme.textPrimary).background(theme.backgroundGradient.ignoresSafeArea()).tint(theme.primaryAction).accessibilityIdentifier(DVKCompanionAccessibilityID.profiles)
    }
}


@MainActor
private struct DVKRoleCardCarousel: View {
    @ObservedObject private var adapter:DVKCompanionStoreAdapter
    let openConversation:()->Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var scrollPosition:String?
    init(adapter:DVKCompanionStoreAdapter, openConversation:@escaping()->Void) {
        self.adapter=adapter
        self.openConversation=openConversation
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
                            DVKRoleLargeCard(profile:profile,selected:profile.id == store.selectedProfileID,isPreview:profile.id == store.previewProfileID,reduced:reduced)
                                .frame(width:width)
                                .scrollTransition(.interactive,axis:.horizontal) { content,phase in
                                    let amount=CGFloat(phase.value)
                                    content.scaleEffect(reduced ? (phase.isIdentity ? 1:0.94):(1-min(abs(amount)*0.06,0.06)))
                                        .opacity(reduced ? (phase.isIdentity ? 1:0.82):(1-min(abs(phase.value)*0.18,0.18)))
                                        .rotation3DEffect(.degrees(reduced ? 0:phase.value * -4),axis:(x:0,y:1,z:0))
                                        .offset(y:reduced ? 0:min(abs(amount)*6,6))
                                }
                                .id(profile.id)
                                .accessibilityIdentifier("companion.profile.card.\(profile.id)")
                                .accessibilityLabel(profile.accessibilityDescription)
                                .onTapGesture {
                                    guard store.canSelectProfiles else { return }
                                    store.selectPreviewProfile(id:profile.id)
                                    scrollPosition=profile.id
                                    adapter.refresh()
                                    if reduced { proxy.scrollTo(profile.id,anchor:.center) }
                                    else { withAnimation(.snappy(duration:0.32)) { proxy.scrollTo(profile.id,anchor:.center) } }
                                }
                        }
                    }.scrollTargetLayout().padding(.vertical,12)
                }
                .scrollTargetBehavior(.viewAligned)
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
            .frame(height:486)
            DVKRoleSelectionBar(adapter:adapter,openConversation:openConversation)
        }
        .accessibilityIdentifier(DVKCompanionAccessibilityID.profilePreview)
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
    let profile:DVKCompanionProfile;let selected:Bool;let isPreview:Bool;let reduced:Bool
    var body:some View {
        let theme=DVKCompanionThemeResolver.resolve(profile:profile,appearance:.followProfile)
        VStack(spacing:10) {
            if selected {Text("Current cat").font(.caption.weight(.semibold)).padding(.horizontal,14).padding(.vertical,6).background(theme.elevatedSurface,in:Capsule()).foregroundStyle(theme.primaryAction)} else {Color.clear.frame(height:28)}
            ZStack {
                RoundedRectangle(cornerRadius:24,style:.continuous).fill(theme.elevatedSurface)
                DVKRoleAvatar(profile:profile,dimension:228,reduced:reduced)
                    .scrollTransition(.interactive,axis:.horizontal) { content,phase in
                        let amount=CGFloat(phase.value)
                        content.offset(x:reduced ? 0:amount * -8)
                    }
            }.frame(height:246)
            Text(profile.displayName).font(.title2.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.82)
            HStack(spacing:6){ForEach(profile.personalityTags,id:\.self){Text($0).font(.caption.weight(.medium)).lineLimit(1).padding(.horizontal,9).padding(.vertical,5).background(theme.elevatedSurface,in:Capsule()).foregroundStyle(theme.primaryAction)}}.frame(maxWidth:.infinity)
            Text(profile.greeting).font(.subheadline).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.86).foregroundStyle(theme.textSecondary)
            HStack(spacing:6){ForEach(profile.capabilities,id:\.self){Text($0.rawValue.capitalized).font(.caption2.weight(.medium)).padding(.horizontal,7).padding(.vertical,4).background(theme.surface,in:Capsule())}}
        }.padding(16).frame(maxWidth:.infinity).background(theme.surface,in:RoundedRectangle(cornerRadius:30,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:30,style:.continuous).stroke(isPreview ? theme.primaryAction:theme.border.opacity(0.4),lineWidth:isPreview ? 2.5:1))
        .shadow(color:theme.shadow.opacity(isPreview ? 0.22:0.1),radius:isPreview ? 16:10,y:8).accessibilityElement(children:.combine)
    }
}
private let dvkRoleAvatarCanvasSize:CGFloat = 250

@MainActor
private struct DVKRoleAvatar:View {
    let profile:DVKCompanionProfile;let dimension:CGFloat;let reduced:Bool
    var body:some View {
        DVKProgrammaticCatView(profile:profile,reduceMotion:reduced)
            .frame(width:dvkRoleAvatarCanvasSize,height:dvkRoleAvatarCanvasSize)
            .scaleEffect(dimension / dvkRoleAvatarCanvasSize)
            .frame(width:dimension,height:dimension)
            .clipShape(RoundedRectangle(cornerRadius:22,style:.continuous))
            .clipped()
            .contentShape(RoundedRectangle(cornerRadius:22,style:.continuous))
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
        ScrollView{VStack(alignment:.leading,spacing:16){if let profile=store.selectedProfile{HStack{DVKCharacterPresentationView(profile:profile,state:store.characterState,reduceMotion:store.reduceMotionPreview,staticMode:store.presentationMode == .staticFallback,host:store.presentationMode == .staticFallback ? nil : adapter.live2DHost).frame(width:54,height:54);VStack(alignment:.leading){Text(profile.displayName).font(.headline);Text(profile.personalityTags.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)}};Text("Switch cat from the Cats tab when this conversation is idle.").font(.caption).foregroundStyle(.secondary)};Picker("Mode",selection:Binding(get:{store.mode},set:{store.setMode($0);adapter.refresh()})){Text("Text").tag(DVKCompanionMode.text);Text("Voice").tag(DVKCompanionMode.voice)}.pickerStyle(.segmented).accessibilityIdentifier(DVKCompanionAccessibilityID.modePicker);if store.mode == .text {DVKTextConversation(adapter:adapter)} else {DVKVoiceConversation(adapter:adapter, onEnded:onClose)}}.padding(20)}.background(DVKCompanionThemeResolver.resolve(profile:adapter.store.selectedProfile, appearance:adapter.store.appearance).backgroundGradient.ignoresSafeArea()).navigationTitle("Conversation")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button(action: onClose) { Image(systemName: store.hasActiveSession ? "chevron.down" : "xmark") }.accessibilityLabel(store.hasActiveSession ? "收起语音会话" : "关闭会话") } }
        .accessibilityIdentifier("companion.conversation")
    }
}

@MainActor
public struct DVKTextConversation: View {
    @ObservedObject var adapter:DVKCompanionStoreAdapter
    public init(adapter:DVKCompanionStoreAdapter){self.adapter=adapter}
    public var body:some View { let store=adapter.store; let theme=DVKCompanionThemeResolver.resolve(profile:store.selectedProfile, appearance:store.appearance); VStack(alignment:.leading,spacing:12){ForEach(store.messages){message in HStack{if message.role == .assistant{bubble(message, theme:theme)};Spacer();if message.role == .user{bubble(message, theme:theme)}}};HStack(alignment:.bottom){TextField("Write a message",text:Binding(get:{store.draft},set:{store.setDraft($0);adapter.refresh()}),axis:.vertical).textFieldStyle(.roundedBorder).accessibilityIdentifier(DVKCompanionAccessibilityID.chatInput);Button("Send"){guard let op=store.beginSendDraft() else{return};adapter.refresh();Task{await op.value;adapter.refresh()}}.dvkGlassControl(theme: theme, prominent: true).disabled(!store.canSend).accessibilityIdentifier(DVKCompanionAccessibilityID.chatSend)};if store.sending{ProgressView("Sending…").accessibilityIdentifier(DVKCompanionAccessibilityID.chatSending)};HStack{Button("Plan next failure"){Task{await store.planNextMockFailure();adapter.refresh()}}.disabled(!store.canPlanMockFailure).accessibilityIdentifier(DVKCompanionAccessibilityID.chatPlanFailure);if store.mockFailurePlanned{Text("Next send fails").font(.caption)}};if store.lastFailure{Button("Retry"){Task{await store.retryFailedMessage();adapter.refresh()}}.buttonStyle(.bordered).accessibilityIdentifier(DVKCompanionAccessibilityID.chatRetry)};if let error=store.lastError{Text(error).font(.footnote).foregroundStyle(.red)}}}
    private func bubble(_ m:DVKCompanionMessage, theme:DVKCompanionTheme)->some View{VStack(alignment:.leading,spacing:4){Text(m.profileSnapshot?.displayName ?? "Mock").font(.caption.bold());Text(m.text);Text(m.deliveryState.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary)}.padding(12).background(m.role == .user ? DVKCompanionThemeResolver.resolve(profile: adapter.store.selectedProfile, appearance: adapter.store.appearance).userMessageSurface:theme.assistantMessageSurface,in:RoundedRectangle(cornerRadius:16))}
}

@MainActor
public struct DVKVoiceConversation: View {
    @ObservedObject var adapter: DVKCompanionStoreAdapter
    private let onEnded: () -> Void
    public init(adapter: DVKCompanionStoreAdapter, onEnded:@escaping () -> Void = {}) { self.adapter = adapter; self.onEnded = onEnded }

    public var body: some View {
        let store = adapter.store
        let theme = DVKCompanionThemeResolver.resolve(profile: store.selectedProfile, appearance: store.appearance)
        let ripplePresentation = DVKCharacterVoiceRipplePresentation(
            amplitude: store.playbackAmplitude,
            voiceState: store.voiceState,
            reduceMotion: store.reduceMotionPreview,
            staticMode: store.presentationMode == .staticFallback,
            hasError: store.voiceError != nil
        )
        VStack(spacing: 16) {
            Text("Mock voice").font(.title2.bold())
            if let profile = store.selectedProfile {
                VStack(spacing: 8) {
                    ZStack {
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
                        .font(.title3.bold())
                        .foregroundStyle(theme.textPrimary)
                    Text(ripplePresentation.statusText)
                        .font(.headline)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceState)
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
            DVKIOS26GlassEffectContainer {
                HStack(spacing: 10) {
                    Button("Start") {
                        adapter.refresh()
                        Task { await store.beginVoiceDemo(); adapter.refresh() }
                    }
                    .disabled(!store.canStartVoice)
                    .accessibilityIdentifier(DVKCompanionAccessibilityID.voiceStart)
                    .dvkGlassControl(theme: theme, prominent: true)

                    Button("Advance") {
                        store.advanceVoiceDemo()
                        adapter.refresh()
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
public struct DVKCompanionSettingsView: View {
    @ObservedObject var adapter:DVKCompanionStoreAdapter
    public init(adapter:DVKCompanionStoreAdapter){self.adapter=adapter}
    public var body:some View{let store=adapter.store;let theme=DVKCompanionThemeResolver.resolve(profile:store.selectedProfile, appearance:store.appearance);Form{Section("Default cat"){Picker("Cat",selection:Binding(get:{store.selectedProfileID ?? ""},set:{store.selectPreviewProfile(id:$0);store.confirmProfileSelection();adapter.refresh()})){ForEach(store.profiles){Text($0.displayName).tag($0.id)}}};Section("Appearance"){Picker("Theme",selection:Binding(get:{store.appearance},set:{store.setAppearance($0);adapter.refresh()})){ForEach(DVKCompanionAppearance.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}};Toggle("Reduce Motion preview",isOn:Binding(get:{store.reduceMotionPreview},set:{store.setReduceMotionPreview($0);adapter.refresh()}));Text("Dynamic Type, VoiceOver and Reduce Motion are supported by the public UI.").font(.footnote)};Section("Privacy"){Button(store.privacy == .allowed ? "Preview limited privacy":"Re-authorize"){if store.privacy == .allowed{store.setPrivacy(.limited)}else{store.reauthorize()};adapter.refresh()}.accessibilityIdentifier(store.privacy == .allowed ? DVKCompanionAccessibilityID.privacyLimited:DVKCompanionAccessibilityID.reauthorize)};Section("Mock Lab"){DVKMockLabView(adapter:adapter)};Section("About"){Text("DVK Companion is local-only, provider-neutral, and uses four fictional mock cats. No production identity, prompt, token, or asset is included.")}}.safeAreaPadding(.bottom, dvkTabBarBottomContentPadding).scrollContentBackground(.hidden).listRowBackground(theme.surface).foregroundStyle(theme.textPrimary).tint(theme.primaryAction).background(theme.pageBackground).dvkIOS26NavigationChrome(theme: theme).navigationTitle("Settings").accessibilityIdentifier(DVKCompanionAccessibilityID.settings)}
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
                ContentUnavailableView(
                    "No reviews yet",
                    systemImage: "waveform",
                    description: Text("Complete a local mock session or seed Mock Lab data")
                )
                .accessibilityIdentifier("companion.reviews.empty")
            } else {
                List(store.reviews) { review in
                    Button {
                        store.selectReview(id: review.id)
                        adapter.refresh()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(review.title).font(.headline)
                            Text(review.profileSnapshot?.displayName ?? "Mock cat").font(.caption)
                            Text(review.source.rawValue.capitalized).font(.caption2)
                        }
                    }
                    .listRowBackground(theme.surface)
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier("companion.review.\(review.id)")
                }
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
