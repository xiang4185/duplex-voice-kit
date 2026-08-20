import Foundation
import XCTest
@testable import XiaomaoApp

final class ChatUIContractTests: XCTestCase {
    func testChatTabOrderAndInjectedServiceBoundaryRemainStable() throws {
        let main = try source("XiaomaoApp/App/MainTabView.swift")
        let companion = try XCTUnwrap(main.range(of: "CompanionHomeView("))
        let chat = try XCTUnwrap(main.range(of: "ChatView("))
        let smallThings = try XCTUnwrap(main.range(of: "SmallThingsRootView(store:"))
        let settings = try XCTUnwrap(main.range(of: "SettingsView("))

        XCTAssertLessThan(companion.lowerBound, chat.lowerBound)
        XCTAssertLessThan(chat.lowerBound, smallThings.lowerBound)
        XCTAssertLessThan(smallThings.lowerBound, settings.lowerBound)
        XCTAssertTrue(main.contains("chatService: any ChatServicing"))
        let preview = try XCTUnwrap(main.range(of: "private struct MainTabPreview"))
        let runtimeSource = String(main[..<preview.lowerBound])
        let previewSource = String(main[preview.lowerBound...])
        XCTAssertFalse(runtimeSource.contains("MockChatService()"))
        XCTAssertTrue(previewSource.contains("MockChatService()"))
        XCTAssertFalse(main.contains("isChatConfigurationReady"))
        XCTAssertFalse(main.contains("APIClient("))
    }

    func testChatContainsStableEmptyTypingClearAndDegradedStates() throws {
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let typing = try source("XiaomaoApp/Chat/ChatTypingIndicator.swift")

        XCTAssertTrue(chat.contains("还没有聊天记录"))
        XCTAssertTrue(chat.contains("confirmationDialog("))
        XCTAssertTrue(chat.contains("清空聊天记录"))
        XCTAssertTrue(chat.contains("刚才的回复由服务端安全降级生成"))
        XCTAssertTrue(chat.contains("ChatTypingIndicator()"))
        XCTAssertTrue(typing.contains("正在等待回复"))
        XCTAssertFalse(typing.contains("小猫正在回复"))
        XCTAssertTrue(chat.contains("refreshHistorySilently"))
        XCTAssertTrue(chat.contains("Task.sleep(for: .seconds(4))"))
    }

    func testCoreAccessibilityIdentifiersRemainStable() throws {
        let files = try [
            "XiaomaoApp/Chat/ChatView.swift",
            "XiaomaoApp/Chat/ChatMessageBubble.swift",
            "XiaomaoApp/Chat/ChatComposerView.swift",
            "XiaomaoApp/Chat/ChatTypingIndicator.swift"
        ].map(source).joined(separator: "\n")

        for identifier in [
            "chat.root",
            "chat.header",
            "chat.mode.mock",
            "chat.messages",
            "chat.empty",
            "chat.loading",
            "chat.error",
            "chat.retry",
            "chat.degraded",
            "chat.typing",
            "chat.input",
            "chat.send",
            "chat.clear",
            "chat.xiaomao.retry.",
            "chat.message."
        ] {
            XCTAssertTrue(files.contains(identifier), "Missing identifier: \(identifier)")
        }
    }

    func testComposerUsesFiveLinesAndMinimumFortyFourPointControls() throws {
        let composer = try source("XiaomaoApp/Chat/ChatComposerView.swift")
        let theme = try source("XiaomaoApp/Design/Theme.swift")

        XCTAssertTrue(composer.contains(".lineLimit(1...5)"))
        XCTAssertTrue(composer.contains(".frame(maxWidth: .infinity, minHeight: Theme.controlMinimumSize)"))
        XCTAssertTrue(composer.contains(".contentShape("))
        XCTAssertTrue(composer.contains("inputFocused = true"))
        XCTAssertTrue(composer.contains("minWidth: Theme.controlMinimumSize"))
        XCTAssertTrue(composer.contains("minHeight: Theme.controlMinimumSize"))
        XCTAssertTrue(composer.contains("visual.textSecondary.opacity(0.78)"),
                      "空输入时发送箭头仍必须在浅色玻璃上清晰可见")
        XCTAssertTrue(composer.contains("visual.textSecondary.opacity(0.13)"),
                      "禁用发送按钮必须保留可辨认的圆形底座")
        XCTAssertTrue(composer.contains("WarmHaptics.action()"),
                      "发送动作必须保留真机触感反馈")
        XCTAssertTrue(theme.contains("static let controlMinimumSize: CGFloat = 44"))
    }

    func testPrimaryButtonSurfacesKeepImmediateHapticFeedback() throws {
        let expectedActionCounts: [String: Int] = [
            "XiaomaoApp/Chat/ChatView.swift": 8,
            "XiaomaoApp/Call/VoiceCallView.swift": 13,
            "XiaomaoApp/Settings/SettingsView.swift": 5,
            "XiaomaoApp/App/DeviceBindingView.swift": 2,
            "XiaomaoApp/SmallThings/SmallThingsRootView.swift": 2,
            "XiaomaoApp/SmallThings/SmallThingsLedgerCard.swift": 5,
            "XiaomaoApp/SmallThings/SmallThingsBindingView.swift": 5,
            "XiaomaoApp/SmallThings/SmallThingsApprovalView.swift": 4,
            "XiaomaoApp/SmallThings/SmallThingComposerView.swift": 5,
            "XiaomaoApp/SmallThings/SmallThingsImagePreview.swift": 1,
            "XiaomaoApp/Design/Components/VisualComponents.swift": 2
        ]

        for (path, minimumCount) in expectedActionCounts {
            let contents = try source(path)
            let count = contents.components(separatedBy: "WarmHaptics.action()").count - 1
            XCTAssertGreaterThanOrEqual(
                count,
                minimumCount,
                "\(path) 的点击触感入口被删除或绕过"
            )
        }

        let entryCard = try source("XiaomaoApp/SmallThings/SmallThingEntryCard.swift")
        XCTAssertTrue(entryCard.contains(".sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)"))
        XCTAssertGreaterThanOrEqual(
            entryCard.components(separatedBy: "hapticTrigger += 1").count - 1,
            9,
            "小事卡片的点击触感入口被删除或延后到异步结果"
        )
    }

    func testVoiceAudioSessionAllowsHapticsWhileRecording() throws {
        let audioSession = try source("../../Sources/DuplexVoiceKit/DVKAudioSession.swift")

        XCTAssertTrue(
            audioSession.contains("setAllowHapticsAndSystemSoundsDuringRecording(true)"),
            "全双工录音会话必须显式允许系统触觉，否则所有 UIImpactFeedbackGenerator 会在录音期间被系统压制"
        )
    }

    func testTappingOrScrollingConversationDismissesKeyboard() throws {
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let app = try source("XiaomaoApp/App/XiaomaoApp.swift")

        XCTAssertTrue(chat.contains(".scrollDismissesKeyboard(.interactively)"))
        XCTAssertTrue(chat.contains("TapGesture().onEnded { _ in inputFocused = false }"))
        XCTAssertTrue(chat.contains("chatNavigationTitle"))
        XCTAssertFalse(chat.contains("modeFooter"), "底部参与模式条会抢占聊天主内容，不应回归")
        XCTAssertTrue(chat.contains("Text(companionStore.current.displayName)"),
                      "紧凑导航仍必须保留当前陪伴身份")
        XCTAssertFalse(chat.contains("CONVERSATION"), "聊天页不得再使用占据首屏的大型编辑式标题")
        XCTAssertTrue(chat.contains(".navigationBarTitleDisplayMode(.inline)"),
                      "聊天页应使用紧凑的系统导航栏")
        XCTAssertGreaterThanOrEqual(
            chat.components(separatedBy: ".onTapGesture { inputFocused = false }").count - 1,
            1,
            "顶部非输入区域必须可主动收起键盘"
        )
        XCTAssertTrue(chat.contains(".defaultScrollAnchor(.bottom)"),
                      "聊天记录默认必须锚定最新消息")
        XCTAssertTrue(chat.contains("followsLatestMessage ? .bottom : nil"))
        XCTAssertTrue(chat.contains("for: .sizeChanges"),
                      "原生 viewport 改变消息容器高度时，最新消息必须随键盘同步上移")
        XCTAssertTrue(chat.contains(".defaultScrollAnchor(.top, for: .alignment)"),
                      "短消息必须始终顶部对齐，键盘出现不得把整组消息切到底部")
        XCTAssertFalse(chat.contains("keyboardWillChangeFrameNotification"),
                       "聊天不得再监听键盘事件驱动第二套滚动")
        XCTAssertFalse(chat.contains("keyboardAnimationDurationUserInfoKey"))
        XCTAssertFalse(chat.contains("keyboardAnimationCurveUserInfoKey"))
        XCTAssertTrue(chat.contains(".onScrollGeometryChange(for: ChatScrollGeometry.self)"),
                      "阅读位置只能由消息滚动容器自身的几何变化驱动")
        XCTAssertTrue(chat.contains("oldGeometry.viewportHeight - newGeometry.viewportHeight"),
                      "viewport 尺寸变化不得被误判为用户离开最新消息")
        XCTAssertTrue(chat.contains("guard followsLatestMessage else { return }"),
                      "浏览历史时新消息和轮询不得强制锚底")
        XCTAssertFalse(chat.contains("keyboardDidShowNotification"),
                       "不得等键盘完全出现后再补一次跳跃式锚底")
        XCTAssertFalse(chat.contains("keyboardDidHideNotification"),
                       "不得等键盘完全收回后再补一次跳跃式锚底")
        XCTAssertFalse(chat.contains("keyboardVisible ? .bottom : .top"),
                       "键盘状态不得切换短消息整体 alignment")
        XCTAssertFalse(chat.contains("scrollToBottomWithoutAnimation"),
                       "不得保留键盘结束后的无动画纠偏滚动")
        XCTAssertFalse(chat.contains(".ignoresSafeArea(.keyboard"),
                       "聊天页必须交回系统键盘 safe-area，不能让 Tab Bar 留在键盘下方形成空白")
        XCTAssertFalse(chat.contains("keyboardOverlap"),
                       "不得再手工维护第二套键盘高度")
        XCTAssertFalse(chat.contains("GeometryReader"),
                       "键盘布局不得依赖手工屏幕/容器高度推算")
        XCTAssertFalse(chat.contains("UIScreen.main.bounds.height"),
                       "不得按整屏高度计算键盘覆盖")
        XCTAssertFalse(chat.contains("Task.sleep(for: .milliseconds(120))"),
                       "不得再延迟等待键盘后补滚动")

        let viewport = try source("XiaomaoApp/App/KeyboardViewportContainer.swift")
        XCTAssertTrue(viewport.contains("view.keyboardLayoutGuide"))
        XCTAssertTrue(viewport.contains("keyboardGuide.usesBottomSafeArea = false"))
        XCTAssertTrue(viewport.contains("contentView.bottomAnchor.constraint(equalTo: keyboardGuide.topAnchor)"))
        XCTAssertTrue(app.contains(".ignoresSafeArea(.container, edges: .all)"),
                      "原生 viewport 必须铺满窗口，不能在状态栏和 Home Indicator 外露白底")
        XCTAssertTrue(app.contains(".ignoresSafeArea(.keyboard)"),
                      "SwiftUI 不得叠加第二套键盘 safe-area resize")
    }

    func testMessageBubbleUsesServerIdentityAndVoiceOverSpeakerLabels() throws {
        let bubble = try source("XiaomaoApp/Chat/ChatMessageBubble.swift")

        XCTAssertTrue(bubble.contains("chat.message.\\(message.id)"))
        XCTAssertTrue(bubble.contains("private var participantDisplayName: String"))
        XCTAssertTrue(bubble.contains("case .user: return \"客户\""))
        XCTAssertTrue(bubble.contains("\\(participantDisplayName)：\\(message.content)"))
        XCTAssertFalse(bubble.contains("Text(participantDisplayName)"),
                       "聊天区不得显示客户/开发者/小猫姓名，身份只用头像和左右位置区分")
        XCTAssertTrue(bubble.contains("switch message.participant"))
        XCTAssertTrue(bubble.contains("case .xiaomao:"))
        XCTAssertTrue(bubble.contains("ChatParticipantAvatar("), "聊天消息必须使用统一参与者头像组件")
        XCTAssertFalse(bubble.contains("Text(\"🐱\")"), "小猫消息不得继续使用固定 emoji 头像")
        XCTAssertTrue(bubble.contains("message.participant == localParticipant"))
        XCTAssertTrue(bubble.contains("Text(message.createdAt, style: .time)"))
        XCTAssertFalse(bubble.contains("showsTimestamp"), "重新进入聊天后时间不得恢复为隐藏")
        XCTAssertTrue(bubble.contains("else if !groupedWithNext"), "每组连续消息末尾必须稳定显示时间")
        XCTAssertTrue(bubble.contains("ChatParticipantAvatar("), "聊天气泡必须读取共享参与者头像")
        XCTAssertTrue(bubble.contains("每条远端消息都保留头像"), "聊天身份识别应遵循微信式逐条头像")
        XCTAssertFalse(bubble.contains("Color.clear.frame(width: 34"), "连续消息不得再用空白头像占位")
        XCTAssertTrue(bubble.contains("size: 32"), "三方头像应使用统一尺寸和轨道")
        XCTAssertTrue(bubble.contains("HStack(alignment: .top, spacing: 10)"),
                      "长消息头像必须从气泡顶部开始对齐，不得掉到消息末尾")
        XCTAssertTrue(bubble.contains("bubble\n                avatar"), "本地消息也必须保留右侧头像")
        XCTAssertTrue(bubble.contains(".frame(maxWidth: 278"), "长消息必须限制行宽，避免铺满屏幕")
        XCTAssertTrue(bubble.contains("isLocalMessage { return Theme.v2InkSurface }"), "自己的消息必须建立稳定的高识别度视觉锚点")
        XCTAssertFalse(bubble.contains(".shadow("), "聊天气泡不得堆叠卡片阴影制造视觉噪声")
        XCTAssertTrue(bubble.contains(".textSelection(.enabled)"))
    }

    func testChatParticipantsCanPersistAndShareTheirOwnAvatar() throws {
        let avatars = try source("XiaomaoApp/Chat/ChatAvatarStore.swift")
        let settings = try source("XiaomaoApp/Settings/SettingsView.swift")
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")

        XCTAssertTrue(avatars.contains("/v1/chat/avatars"))
        XCTAssertTrue(avatars.contains("/v1/chat/avatar/update"))
        XCTAssertTrue(avatars.contains("preparedJPEG"), "头像上传前必须裁剪压缩")
        XCTAssertTrue(avatars.contains("UserDefaults"), "网络波动时必须保留本地头像缓存")
        XCTAssertTrue(avatars.contains("PrivacyAvatar(size: size, tappable: false, style: .thumbnail)"), "小猫消息头像必须继续跟随角色形象")
        XCTAssertTrue(settings.contains("PhotosPicker"), "我的页面必须提供系统照片选择器")
        XCTAssertTrue(settings.contains("settings.chatAvatar"))
        XCTAssertTrue(chat.contains("await avatarStore.load()"), "进入聊天必须刷新双方头像")
    }

    func testConversationUsesSpeakerBasedVerticalRhythm() throws {
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")

        XCTAssertTrue(chat.contains("LazyVStack(spacing: 4)"))
        XCTAssertTrue(chat.contains("messageSpacingBefore(message)"))
        XCTAssertTrue(chat.contains("previous.participant == message.participant ? 2 : 10"),
                      "连续发言应收紧，换人发言才拉开段落")
    }

    func testSharedChatBubbleAlignmentUsesLocalParticipantIdentity() throws {
        let mainTab = try source("XiaomaoApp/App/MainTabView.swift")
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let bubble = try source("XiaomaoApp/Chat/ChatMessageBubble.swift")
        let avatars = try source("XiaomaoApp/Chat/ChatAvatarStore.swift")

        XCTAssertTrue(mainTab.contains("environment.chatTargetDeviceID == nil ? .user : .developer"))
        XCTAssertTrue(chat.contains("localParticipant: localParticipant"))
        XCTAssertTrue(bubble.contains("private var isLocalMessage: Bool { message.participant == localParticipant }"))
        XCTAssertTrue(bubble.contains("case .user: return \"客户\""),
                      "开发者视角中的客户消息不得仍显示成‘你’")
        XCTAssertTrue(bubble.contains("ChatParticipantAvatar("),
                      "聊天气泡应统一读取可同步的参与者头像")
        XCTAssertTrue(avatars.contains("Image(systemName: \"person.fill\")"),
                      "远端真人参与者应使用克制的人物剪影头像")
        XCTAssertFalse(bubble.contains("Text(\"客\")"),
                       "聊天头像不得使用破坏陪伴氛围的后台身份缩写")
        XCTAssertFalse(bubble.contains("Text(\"开\")"),
                       "聊天头像不得使用破坏陪伴氛围的后台身份缩写")
        XCTAssertFalse(bubble.contains("if message.role == .user"))
    }

    func testSendDismissesKeyboardBeforeAsyncRequestAndNeverRestoresFocus() throws {
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let sendRange = try XCTUnwrap(chat.range(of: "send:"))
        let focusBindingRange = try XCTUnwrap(
            chat.range(of: "inputFocused:", range: sendRange.upperBound..<chat.endIndex)
        )
        let sendBlock = String(chat[sendRange.lowerBound..<focusBindingRange.lowerBound])

        let dismiss = try XCTUnwrap(sendBlock.range(of: "inputFocused = false"))
        let request = try XCTUnwrap(sendBlock.range(of: "await viewModel.send("))
        XCTAssertLessThan(dismiss.lowerBound, request.lowerBound)
        XCTAssertTrue(sendBlock.contains("await Task.yield()"))
        XCTAssertTrue(sendBlock.contains("companionTypeID: companionStore.current.rawValue"))
        XCTAssertFalse(chat.contains("inputFocused = true"))
    }

    func testThreePartyHeaderUsesHumanDeveloperAndSoleAIIdentity() throws {
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let model = try source("XiaomaoApp/Models/ChatMessage.swift")

        XCTAssertFalse(chat.contains("开发者和小猫都在"), "极简头部不得重复说明参与者")
        XCTAssertTrue(chat.contains("private var chatNavigationTitle"))
        XCTAssertTrue(chat.contains("Text(\"小猫\")"))
        XCTAssertTrue(chat.contains("Text(companionStore.current.displayName)"))
        XCTAssertTrue(model.contains("case developer"))
        XCTAssertTrue(model.contains("case xiaomao"))
        XCTAssertFalse(model.contains("case companion"))
        XCTAssertTrue(model.contains("case .developer: \"开发者\""))
    }

    func testV21RestoresNativeIOSHierarchyWithoutLosingBrandTokens() throws {
        let theme = try source("XiaomaoApp/Design/Theme.swift")
        let tabs = try source("XiaomaoApp/App/MainTabView.swift")
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let smallThings = try source("XiaomaoApp/SmallThings/SmallThingsRootView.swift")
        let ledger = try source("XiaomaoApp/SmallThings/SmallThingsLedgerCard.swift")
        let settings = try source("XiaomaoApp/Settings/SettingsView.swift")

        for token in ["v2InkSurface", "v2Paper", "v2Coral", "v2Lavender"] {
            XCTAssertTrue(theme.contains(token), "V2 缺少共享视觉令牌：\(token)")
        }
        XCTAssertTrue(tabs.contains("TabView(selection:"))
        XCTAssertTrue(tabs.contains(".tabItem"))
        XCTAssertFalse(tabs.contains("main.v2TabBar"), "不得再叠加第二层自绘 Dock")
        XCTAssertFalse(tabs.contains("matchedGeometryEffect"), "系统 Tab Bar 不需要复制选中滑块")
        XCTAssertFalse(tabs.contains(".toolbar(.hidden, for: .tabBar)"), "根 Tab 必须交回 iOS 26 原生 Tab Bar")
        XCTAssertTrue(tabs.contains("WarmHaptics.prepareAction()"),
                      "系统 Tab 出现时必须预热轻击反馈，减少首次触感延迟")
        XCTAssertTrue(tabs.contains("TabView(selection: tabSelection)"),
                      "原生 Tab selection 必须经由即时触感 Binding 提交")
        XCTAssertTrue(tabs.contains("WarmHaptics.action()"),
                      "系统 Tab 切换必须保留即时轻击反馈")
        XCTAssertFalse(tabs.contains(".sensoryFeedback(.selection, trigger: selectedTab)"),
                       "Tab 反馈不得等 selection 状态提交后才触发")
        XCTAssertTrue(home.contains("LIVE COMPANION"))
        XCTAssertFalse(home.contains("LIVE COMPANION  /"), "正式界面不得保留设计稿序号")
        XCTAssertTrue(home.contains("homeControlDeck"))
        XCTAssertTrue(home.contains("visual.primarySoft.opacity(0.28)"), "首页主控应恢复轻量玻璃而非整块实色")
        XCTAssertFalse(chat.contains("CONVERSATION"))
        XCTAssertTrue(chat.contains("chatNavigationTitle"))
        XCTAssertTrue(chat.contains("NavigationStack"))
        XCTAssertTrue(chat.contains("chatBackdrop"))
        XCTAssertFalse(smallThings.contains("SHARED ARCHIVE"))
        XCTAssertFalse(smallThings.contains("v2Masthead"))
        XCTAssertTrue(smallThings.contains(".navigationTitle(\"小事本\")"))
        XCTAssertFalse(ledger.contains("Theme.v2InkSurface"), "账本内容卡不得继续铺大面积深色")
        XCTAssertTrue(ledger.contains("Theme.v2PaperMuted"))
        XCTAssertTrue(settings.contains("CHAT PROFILE"))
        XCTAssertTrue(settings.contains("settingsBackdrop"), "我的页必须进入同一套 V2 视觉语言")
    }

    func testV22MotionHierarchyKeepsNativeStructureAndReduceMotionFallbacks() throws {
        let tabs = try source("XiaomaoApp/App/MainTabView.swift")
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let composer = try source("XiaomaoApp/Chat/ChatComposerView.swift")

        XCTAssertTrue(tabs.contains("V2TabSceneMotion"))
        XCTAssertTrue(tabs.contains("accessibilityReduceMotion"))
        XCTAssertTrue(tabs.contains(".bounce,"))
        XCTAssertTrue(tabs.contains("value: !reduceMotion && selectedTab"))
        XCTAssertFalse(tabs.contains("main.v2TabBar"), "动效增强不得重新引入自绘 Dock")

        for token in ["livePulse", "callPulse", "repeatForever", "accessibilityReduceMotion"] {
            XCTAssertTrue(home.contains(token), "首页缺少动态生命感：\(token)")
        }
        for token in ["ambientMotion", "onlinePulse", "repeatForever", "allowsHitTesting(false)"] {
            XCTAssertTrue(chat.contains(token), "聊天页缺少环境动效：\(token)")
        }
        XCTAssertTrue(composer.contains("V2ComposerSendButtonStyle"))
        XCTAssertTrue(composer.contains("value: inputFocused"))
        XCTAssertTrue(composer.contains("accessibilityReduceMotion"))
    }

    func testV23CharacterPresenceUsesRealStateAndContinuousTransitions() throws {
        let presence = try source("XiaomaoApp/Design/Components/CharacterPresenceMotion.swift")
        let root = try source("XiaomaoApp/App/XiaomaoApp.swift")
        let home = try source("XiaomaoApp/App/CompanionHomeView.swift")
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let typing = try source("XiaomaoApp/Chat/ChatTypingIndicator.swift")
        let call = try source("XiaomaoApp/Call/VoiceCallView.swift")

        for token in [
            "case idle", "case connecting", "case listening", "case thinking",
            "case speaking", "case reconnecting", "init(voiceState: VoiceSessionState"
        ] {
            XCTAssertTrue(presence.contains(token), "角色存在状态缺少：\(token)")
        }
        XCTAssertTrue(presence.contains("case .ready, .listening, .endpointing:"))
        XCTAssertTrue(presence.contains("case .processing:"))
        XCTAssertTrue(presence.contains("case .speaking, .interrupting:"))
        XCTAssertTrue(presence.contains("accessibilityReduceMotion"))
        XCTAssertTrue(presence.contains("guard !reduceMotion"))
        XCTAssertTrue(presence.contains("matchedTransitionSource"))
        XCTAssertFalse(presence.contains("Timer"), "角色生命感不得依赖常驻 Timer")

        XCTAssertTrue(root.contains(".navigationTransition("))
        XCTAssertTrue(root.contains(".zoom(sourceID: CharacterTransitionID.call"))
        XCTAssertTrue(root.contains("if reduceMotion"),
                      "Reduce Motion 必须绕过角色 zoom 转场")
        XCTAssertFalse(root.contains(".navigationTransition(.crossFade)"),
                       "Xcode 26 NavigationTransition 不提供 crossFade 成员")
        XCTAssertTrue(home.contains("CharacterPresencePhase("))
        XCTAssertTrue(home.contains("characterCallTransitionSource"))
        XCTAssertTrue(chat.contains("viewModel.isSending ? .thinking : .idle"))
        XCTAssertTrue(try source("XiaomaoApp/App/MainTabView.swift").contains("characterRelayOverlay"))
        XCTAssertTrue(try source("XiaomaoApp/App/MainTabView.swift").contains("beginCharacterRelay"))
        XCTAssertTrue(try source("XiaomaoApp/App/MainTabView.swift").contains("selectWithReducedMotion"))
        XCTAssertTrue(try source("XiaomaoApp/App/MainTabView.swift").contains("reducedTabFade"))
        XCTAssertTrue(typing.contains(".characterAlive(phase: .thinking"))
        XCTAssertTrue(call.contains("CharacterPresencePhase(voiceState: viewModel.controller.state)"))
        XCTAssertTrue(call.contains("vadNormalizedRMS"), "讲话/聆听光感必须继续复用真实音量")
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
