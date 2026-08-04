import Foundation
import XCTest
@testable import XiaomaoApp

final class AppEnvironmentTests: XCTestCase {
    func testReleaseConfigurationRequiresSecureRemoteEndpointsAndDeviceID() {
        let environment = makeEnvironment(
            api: "https://api.example.test",
            voice: "wss://voice.example.test/v1/voice/ws",
            deviceID: "test-device"
        )
        XCTAssertTrue(environment.isRuntimeConfigurationReady)
    }

    func testEmptyReleaseConfigurationStaysBehindBindingGate() {
        let environment = makeEnvironment(api: nil, voice: nil, deviceID: "")
        XCTAssertFalse(environment.isRuntimeConfigurationReady)
        XCTAssertFalse(environment.runtimeConfigurationMessage.isEmpty)
    }

    func testInsecureOrLoopbackEndpointsAreRejected() {
        XCTAssertFalse(makeEnvironment(
            api: "http://api.example.test",
            voice: "wss://voice.example.test/v1/voice/ws",
            deviceID: "test-device"
        ).isRuntimeConfigurationReady)
        XCTAssertFalse(makeEnvironment(
            api: "https://127.0.0.1:18080",
            voice: "ws://127.0.0.1:18881/v1/voice/ws",
            deviceID: "test-device"
        ).isRuntimeConfigurationReady)
    }

    private func makeEnvironment(api: String?, voice: String?, deviceID: String) -> AppEnvironment {
        AppEnvironment(
            apiBaseURL: api.flatMap(URL.init(string:)),
            voiceWebSocketURL: voice.flatMap(URL.init(string:)),
            deviceID: deviceID,
            appEnvironment: "test",
            enableMockVoice: false,
            enableMemory: false,
            defaultVoiceRoute: .b,
            appBuildSHA: "test",
            appBuildTime: "test"
        )
    }
}
