import Foundation
import XCTest
@testable import XiaomaoApp

final class RuntimeConnectionBundleTests: XCTestCase {
    func testDeveloperTargetRoundTrips() throws {
        let configuration = RuntimeConfiguration(
            apiBaseURL: URL(string: "https://api.example.test")!,
            voiceWebSocketURL: URL(string: "wss://voice.example.test/v1/voice/ws")!,
            deviceID: "developer-device",
            chatTargetDeviceID: "user-device"
        )

        let encoded = try RuntimeConnectionBundle.encode(configuration: configuration, token: "token")
        let decoded = try RuntimeConnectionBundle.decode(encoded)

        XCTAssertEqual(decoded.configuration, configuration)
        XCTAssertEqual(decoded.token, "token")
    }

    func testLegacyBundleWithoutTargetRemainsOrdinaryUser() throws {
        let legacyJSON = #"{"backend":"https://api.example.test","voice":"wss://voice.example.test/v1/voice/ws","device":"user-device","token":"token"}"#
        let encoded = Data(legacyJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let decoded = try RuntimeConnectionBundle.decode("XM1." + encoded)

        XCTAssertEqual(decoded.configuration.deviceID, "user-device")
        XCTAssertNil(decoded.configuration.chatTargetDeviceID)
    }

    func testSelfTargetIsDroppedToAvoidDeveloperForbidden() {
        let configuration = RuntimeConfiguration(
            apiBaseURL: URL(string: "https://api.example.test")!,
            voiceWebSocketURL: URL(string: "wss://voice.example.test/v1/voice/ws")!,
            deviceID: "user-device",
            chatTargetDeviceID: "user-device"
        )

        XCTAssertNil(configuration.chatTargetDeviceID)
    }
}
