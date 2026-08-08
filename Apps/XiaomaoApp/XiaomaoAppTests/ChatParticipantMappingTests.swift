import Foundation
import XCTest
@testable import XiaomaoApp

final class ChatParticipantMappingTests: XCTestCase {
    func testUserMessageMapsToUserParticipant() {
        let message = ChatMessage(
            id: "user-message",
            role: .user,
            content: "synthetic",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(message.participant, .user)
        XCTAssertEqual(message.participant.displayName, "你")
    }

    func testAssistantDefaultsToDeveloperWithoutIDGuessing() {
        let first = ChatMessage(
            id: "assistant-message-1",
            role: .assistant,
            content: "synthetic",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let second = ChatMessage(
            id: "assistant-message-2",
            role: .assistant,
            content: "synthetic",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(first.participant, .developer)
        XCTAssertEqual(second.participant, .developer)
        XCTAssertEqual(first.participant.displayName, "开发者")
    }

    func testServerProvidedXiaomaoIdentityIsPreserved() {
        let message = ChatMessage(
            id: "opaque-message",
            role: .assistant,
            content: "synthetic",
            createdAt: Date(timeIntervalSince1970: 0),
            participant: .xiaomao,
            turnID: "opaque-turn",
            status: .completed
        )
        XCTAssertEqual(message.participant, .xiaomao)
        XCTAssertEqual(message.participant.displayName, "小猫")
        XCTAssertEqual(message.turnID, "opaque-turn")
        XCTAssertEqual(message.status, .completed)
    }
}
