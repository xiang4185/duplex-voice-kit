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
            "chat.xiaomao.mode",
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
        XCTAssertTrue(chat.contains("header\n                    .onTapGesture { inputFocused = false }"))
        XCTAssertTrue(chat.contains("modeFooter"))
        XCTAssertGreaterThanOrEqual(
            chat.components(separatedBy: ".onTapGesture { inputFocused = false }").count - 1,
            2,
            "顶部与底部非输入区域都必须可主动收起键盘"
        )
        XCTAssertTrue(chat.contains(".ignoresSafeArea(.keyboard, edges: .bottom)"),
                      "聊天页必须关闭系统二次键盘 safe-area 推动，改为单一页面动画")
        XCTAssertTrue(chat.contains(".padding(.bottom, keyboardOverlap)"),
                      "消息区和输入区必须作为同一页面跟随键盘上移")
        XCTAssertTrue(chat.contains("GeometryReader"),
                      "键盘覆盖必须基于聊天容器自身坐标，而不是整块屏幕")
        XCTAssertTrue(chat.contains("keyboardWillChangeFrameNotification"),
                      "消息偏移必须跟随系统键盘 frame 动画")
        XCTAssertTrue(chat.contains("keyboardAnimation(from: notification)"),
                      "消息滚动必须与键盘使用同一时长/曲线")
        XCTAssertTrue(chat.contains("containerBottom: geometry.frame(in: .global).maxY"),
                      "键盘 frame 必须驱动同一页面的 bottom overlap")
        XCTAssertFalse(chat.contains("UIScreen.main.bounds.height"),
                       "TabView 内不得再用整屏高度计算键盘覆盖，否则会保留 tab bar 空白")
        XCTAssertFalse(chat.contains("Task.sleep(for: .milliseconds(120))"),
                       "不得再延迟等待键盘后补滚动")
    }

    func testMessageBubbleUsesServerIdentityAndVoiceOverSpeakerLabels() throws {
        let bubble = try source("XiaomaoApp/Chat/ChatMessageBubble.swift")

        XCTAssertTrue(bubble.contains("chat.message.\\(message.id)"))
        XCTAssertTrue(bubble.contains("message.participant.displayName"))
        XCTAssertTrue(bubble.contains("\\(message.participant.displayName)：\\(message.content)"))
        XCTAssertTrue(bubble.contains("switch message.participant"))
        XCTAssertTrue(bubble.contains("case .xiaomao:"))
        XCTAssertTrue(bubble.contains("message.participant == .user"))
        XCTAssertTrue(bubble.contains("Text(message.createdAt, style: .time)"))
        XCTAssertTrue(bubble.contains(".textSelection(.enabled)"))
    }

    func testSendDismissesKeyboardBeforeAsyncRequestAndNeverRestoresFocus() throws {
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let sendRange = try XCTUnwrap(chat.range(of: "send:"))
        let focusBindingRange = try XCTUnwrap(
            chat.range(of: "inputFocused:", range: sendRange.upperBound..<chat.endIndex)
        )
        let sendBlock = String(chat[sendRange.lowerBound..<focusBindingRange.lowerBound])

        let dismiss = try XCTUnwrap(sendBlock.range(of: "inputFocused = false"))
        let request = try XCTUnwrap(sendBlock.range(of: "await viewModel.send()"))
        XCTAssertLessThan(dismiss.lowerBound, request.lowerBound)
        XCTAssertTrue(sendBlock.contains("await Task.yield()"))
        XCTAssertFalse(chat.contains("inputFocused = true"))
    }

    func testThreePartyHeaderUsesHumanDeveloperAndSoleAIIdentity() throws {
        let chat = try source("XiaomaoApp/Chat/ChatView.swift")
        let model = try source("XiaomaoApp/Models/ChatMessage.swift")

        XCTAssertTrue(chat.contains("开发者和小猫都在"))
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
