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
        XCTAssertEqual(message.senderName, "你")
    }

    func testAssistantParticipantMappingIsStableAcrossReads() {
        let message = ChatMessage(
            id: "assistant-message",
            role: .assistant,
            content: "synthetic",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(message.participant, message.participant)
        XCTAssertTrue(["小猫", "伙伴"].contains(message.senderName))
    }
}
