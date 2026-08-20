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
        XCTAssertFalse(environment.canStartBackendRequest(hasToken: true))
        XCTAssertFalse(environment.canStartVoiceConnection(hasToken: true))
        XCTAssertFalse(environment.runtimeConfigurationMessage.isEmpty)
    }

    func testBackendRequiresHTTPSDeviceAndToken() {
        let environment = makeEnvironment(
            api: "https://api.example.test",
            voice: "wss://voice.example.test/v1/voice/ws",
            deviceID: "test-device"
        )
        XCTAssertFalse(environment.canStartBackendRequest(hasToken: false))
        XCTAssertTrue(environment.canStartBackendRequest(hasToken: true))
    }

    func testVoiceRequiresWSSDeviceAndTokenOutsideMock() {
        let environment = makeEnvironment(
            api: "https://api.example.test",
            voice: "ws://voice.example.test/v1/voice/ws",
            deviceID: "test-device"
        )
        XCTAssertFalse(environment.canStartVoiceConnection(hasToken: true))
    }

    func testMockVoiceNeedsNoProductionConfiguration() {
        let environment = makeEnvironment(
            api: nil,
            voice: nil,
            deviceID: "",
            enableMockVoice: true
        )
        XCTAssertTrue(environment.isRuntimeConfigurationReady)
        XCTAssertTrue(environment.canStartVoiceConnection(hasToken: false))
        XCTAssertFalse(environment.canStartBackendRequest(hasToken: false))
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

    func testRuntimeConfigurationOwnsChatTargetInsteadOfBundleConfiguration() {
        let runtime = RuntimeConfiguration(
            apiBaseURL: URL(string: "https://api.example.test")!,
            voiceWebSocketURL: URL(string: "wss://voice.example.test/v1/voice/ws")!,
            deviceID: "developer-device",
            chatTargetDeviceID: "user-device"
        )
        let environment = AppEnvironment.fromBundle(
            .main,
            runtimeConfigurationStore: StubRuntimeConfigurationStore(configuration: runtime)
        )

        XCTAssertEqual(environment.deviceID, "developer-device")
        XCTAssertEqual(environment.chatTargetDeviceID, "user-device")
    }

    func testRuntimeConfigurationWithoutTargetStaysOrdinaryUser() {
        let runtime = RuntimeConfiguration(
            apiBaseURL: URL(string: "https://api.example.test")!,
            voiceWebSocketURL: URL(string: "wss://voice.example.test/v1/voice/ws")!,
            deviceID: "user-device"
        )
        let environment = AppEnvironment.fromBundle(
            .main,
            runtimeConfigurationStore: StubRuntimeConfigurationStore(configuration: runtime)
        )

        XCTAssertNil(environment.chatTargetDeviceID)
    }

    private func makeEnvironment(
        api: String?,
        voice: String?,
        deviceID: String,
        enableMockVoice: Bool = false
    ) -> AppEnvironment {
        let mode: HostAdapterMode = enableMockVoice ? .mock : .production
        return AppEnvironment(
            apiBaseURL: api.flatMap(URL.init(string:)),
            voiceWebSocketURL: voice.flatMap(URL.init(string:)),
            deviceID: deviceID,
            appEnvironment: "test",
            enableMockVoice: enableMockVoice,
            enableMemory: false,
            defaultVoiceRoute: .b,
            appBuildSHA: "test",
            appBuildTime: "test",
            requestedHostAdapterMode: mode,
            hostAdapters: enableMockVoice
                ? .mock
                : HostAdapterDependencies(mode: .production)
        )
    }
}

private struct StubRuntimeConfigurationStore: RuntimeConfigurationStoring {
    let configuration: RuntimeConfiguration?

    func load() -> RuntimeConfiguration? { configuration }
    func save(_ configuration: RuntimeConfiguration) throws {}
    func clear() throws {}
}
