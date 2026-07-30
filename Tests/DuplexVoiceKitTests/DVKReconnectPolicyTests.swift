import XCTest
@testable import DuplexVoiceKit

final class DVKReconnectPolicyTests: XCTestCase {
    func testDefaultBackoffMatchesExtractedPolicy() async {
        let controller = DVKReconnectController()

        let first = await controller.nextDelay()
        let second = await controller.nextDelay()
        let third = await controller.nextDelay()
        let fourth = await controller.nextDelay()
        let fifth = await controller.nextDelay()
        let exhausted = await controller.nextDelay()

        XCTAssertEqual(first, .milliseconds(400))
        XCTAssertEqual(second, .milliseconds(800))
        XCTAssertEqual(third, .milliseconds(1_600))
        XCTAssertEqual(fourth, .milliseconds(3_200))
        XCTAssertEqual(fifth, .milliseconds(6_400))
        XCTAssertNil(exhausted)

        await controller.reset()
        let reset = await controller.nextDelay()
        XCTAssertEqual(reset, .milliseconds(400))
    }
}
