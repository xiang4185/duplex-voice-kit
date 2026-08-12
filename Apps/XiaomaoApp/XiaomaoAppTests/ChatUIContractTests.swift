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
        let preview = try XCTUnwrap(main.range(of: "#Preview"))
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
        XCTAssertTrue(typing.contains("正在发送消息"))
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
        XCTAssertTrue(theme.contains("static let controlMinimumSize: CGFloat = 44"))
    }

    func testTappingOrScrollingConversationDismissesKeyboard() throws {
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")

        XCTAssertTrue(chat.contains(".scrollDismissesKeyboard(.immediately)"))
        XCTAssertTrue(chat.contains("TapGesture().onEnded { _ in inputFocused = false }"))
        XCTAssertTrue(chat.contains("header"))
        XCTAssertFalse(chat.contains("modeFooter"), "底部参与模式条会抢占聊天主内容，不应回归")
        XCTAssertTrue(chat.contains("subtitle: companionStore.current.displayName"),
                      "聊天头部只保留当前陪伴类型，不叠加第二层说明")
        XCTAssertGreaterThanOrEqual(
            chat.components(separatedBy: ".onTapGesture { inputFocused = false }").count - 1,
            1,
            "顶部非输入区域必须可主动收起键盘"
        )
        XCTAssertTrue(chat.contains(".defaultScrollAnchor(.bottom)"),
                      "聊天记录默认必须锚定最新消息")
        XCTAssertTrue(chat.contains(".defaultScrollAnchor(.top, for: .alignment)"),
                      "消息不足一屏时必须从顶部开始，不得沉到底部")
        XCTAssertTrue(chat.contains("keyboardDidShowNotification"),
                      "键盘最终布局完成后只能做一次锚底")
        XCTAssertTrue(chat.contains("keyboardDidHideNotification"),
                      "键盘完全收回、Tab Bar 恢复后必须再次锚定最新消息")
        XCTAssertTrue(chat.contains("scrollToBottomWithoutAnimation(proxy)"),
                      "键盘稳定后的锚底不得再叠加第二套滚动动画")
        XCTAssertTrue(chat.contains("transaction.disablesAnimations = true"),
                      "键盘锚底必须禁用额外 SwiftUI 动画")
        XCTAssertFalse(chat.contains("keyboardWillChangeFrameNotification"),
                       "不得监听输入法 frame 连续变化，否则候选栏会反复推动页面")
        XCTAssertFalse(chat.contains("keyboardAnimation(from:"),
                       "不得复制系统键盘动画驱动 ScrollView")
        XCTAssertTrue(chat.contains("DispatchQueue.main.async"),
                      "收键盘后的滚动必须等最终 safe-area 布局落定")
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
    }

    func testMessageBubbleUsesServerIdentityAndVoiceOverSpeakerLabels() throws {
        let bubble = try source("XiaomaoApp/Chat/ChatMessageBubble.swift")

        XCTAssertTrue(bubble.contains("chat.message.\\(message.id)"))
        XCTAssertTrue(bubble.contains("private var participantDisplayName: String"))
        XCTAssertTrue(bubble.contains("case .user: return \"客户\""))
        XCTAssertTrue(bubble.contains("\\(participantDisplayName)：\\(message.content)"))
        XCTAssertTrue(bubble.contains("switch message.participant"))
        XCTAssertTrue(bubble.contains("case .xiaomao:"))
        XCTAssertTrue(bubble.contains("PrivacyAvatar("), "小猫消息头像必须跟随当前陪伴角色")
        XCTAssertTrue(bubble.contains("style: .thumbnail"), "聊天头像必须使用缩略图构图")
        XCTAssertFalse(bubble.contains("Text(\"🐱\")"), "小猫消息不得继续使用固定 emoji 头像")
        XCTAssertTrue(bubble.contains("message.participant == localParticipant"))
        XCTAssertTrue(bubble.contains("Text(message.createdAt, style: .time)"))
        XCTAssertTrue(bubble.contains(".textSelection(.enabled)"))
    }

    func testSharedChatBubbleAlignmentUsesLocalParticipantIdentity() throws {
        let mainTab = try source("XiaomaoApp/App/MainTabView.swift")
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let bubble = try source("XiaomaoApp/Chat/ChatMessageBubble.swift")

        XCTAssertTrue(mainTab.contains("environment.chatTargetDeviceID == nil ? .user : .developer"))
        XCTAssertTrue(chat.contains("localParticipant: localParticipant"))
        XCTAssertTrue(bubble.contains("private var isLocalMessage: Bool { message.participant == localParticipant }"))
        XCTAssertTrue(bubble.contains("case .user: return \"客户\""),
                      "开发者视角中的客户消息不得仍显示成‘你’")
        XCTAssertTrue(bubble.contains("Text(\"客\")"),
                      "开发者视角中的客户消息必须有可区分的远端头像")
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
        XCTAssertTrue(chat.contains("subtitle: companionStore.current.displayName"))
        XCTAssertTrue(model.contains("case developer"))
        XCTAssertTrue(model.contains("case xiaomao"))
        XCTAssertFalse(model.contains("case companion"))
        XCTAssertTrue(model.contains("case .developer: \"开发者\""))
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
