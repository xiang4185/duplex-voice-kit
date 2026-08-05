import Foundation
import XCTest
@testable import XiaomaoApp

final class ChatUIContractTests: XCTestCase {
    func testChatTabOrderAndPublicMockDefaultRemainStable() throws {
        let main = try source("XiaomaoApp/App/MainTabView.swift")
        let companion = try XCTUnwrap(main.range(of: "CompanionHomeView("))
        let chat = try XCTUnwrap(main.range(of: "ChatView(viewModel:"))
        let smallThings = try XCTUnwrap(main.range(of: "SmallThingsRootView()"))
        let settings = try XCTUnwrap(main.range(of: "SettingsView("))

        XCTAssertLessThan(companion.lowerBound, chat.lowerBound)
        XCTAssertLessThan(chat.lowerBound, smallThings.lowerBound)
        XCTAssertLessThan(smallThings.lowerBound, settings.lowerBound)
        XCTAssertTrue(main.contains("MockChatService()"))
        XCTAssertTrue(main.contains("publicDefaultChatService"))
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
        XCTAssertTrue(typing.contains("小猫正在回复"))
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
            "chat.message."
        ] {
            XCTAssertTrue(files.contains(identifier), "Missing identifier: \(identifier)")
        }
    }

    func testComposerUsesFiveLinesAndMinimumFortyFourPointControls() throws {
        let composer = try source("XiaomaoApp/Chat/ChatComposerView.swift")
        let theme = try source("XiaomaoApp/Design/Theme.swift")

        XCTAssertTrue(composer.contains(".lineLimit(1...5)"))
        XCTAssertTrue(composer.contains("minWidth: Theme.controlMinimumSize"))
        XCTAssertTrue(composer.contains("minHeight: Theme.controlMinimumSize"))
        XCTAssertTrue(theme.contains("static let controlMinimumSize: CGFloat = 44"))
    }

    func testMessageBubbleUsesServerIdentityAndVoiceOverSpeakerLabels() throws {
        let bubble = try source("XiaomaoApp/Chat/ChatMessageBubble.swift")

        XCTAssertTrue(bubble.contains("chat.message.\\(message.id)"))
        XCTAssertTrue(bubble.contains("你：\\(message.content)"))
        XCTAssertTrue(bubble.contains("小猫：\\(message.content)"))
        XCTAssertTrue(bubble.contains("Text(message.createdAt, style: .time)"))
        XCTAssertTrue(bubble.contains(".textSelection(.enabled)"))
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
