import XCTest
@testable import DuplexVoiceKitCompanion

final class DVKRuntimeConfigurationTests: XCTestCase {

    private func wssURL(_ host: String = "voice.example.test", _ path: String = "/v1/voice/ws") -> URL? {
        URL(string: "wss" + "://" + host + path)
    }

    private func httpsURL(_ host: String = "api.example.test", _ path: String = "/v1") -> URL? {
        URL(string: "https" + "://" + host + path)
    }

    // 14.1: default empty configuration enters mock mode
    func testDefaultEmptyConfigurationEntersMock() {
        let configuration = DVKRuntimeConfiguration.mock
        XCTAssertEqual(configuration.mode, .mock)
        XCTAssertTrue(configuration.isMock)
        XCTAssertNil(configuration.apiBaseURL)
        XCTAssertNil(configuration.voiceWebSocketURL)
        XCTAssertTrue(configuration.deviceID.isEmpty)
    }

    // 14.1: no real default values are present
    func testNoRealDefaultAddresses() {
        let configuration = DVKRuntimeConfiguration.mock
        XCTAssertNil(configuration.apiBaseURL)
        XCTAssertNil(configuration.voiceWebSocketURL)
        XCTAssertEqual(configuration.deviceID, "")
    }

    // 14.1: complete live configuration enters live mode
    func testCompleteLiveConfigurationEntersLive() {
        let configuration = DVKRuntimeConfiguration(
            apiBaseURL: httpsURL(),
            voiceWebSocketURL: wssURL(),
            deviceID: "dvk-demo-device"
        )
        XCTAssertEqual(configuration.mode, .live)
        XCTAssertTrue(configuration.isLive)
    }

    // 14.1: partial configuration enters the error state and must not network
    func testPartialConfigurationIsMisconfigured() {
        let onlyAPI = DVKRuntimeConfiguration(
            apiBaseURL: httpsURL(),
            voiceWebSocketURL: nil,
            deviceID: ""
        )
        XCTAssertEqual(onlyAPI.mode, .misconfigured)

        let onlyVoice = DVKRuntimeConfiguration(
            apiBaseURL: nil,
            voiceWebSocketURL: wssURL(),
            deviceID: "dvk-demo-device"
        )
        XCTAssertEqual(onlyVoice.mode, .misconfigured)

        let onlyDevice = DVKRuntimeConfiguration(
            apiBaseURL: nil,
            voiceWebSocketURL: nil,
            deviceID: "dvk-demo-device"
        )
        XCTAssertEqual(onlyDevice.mode, .misconfigured)
    }

    // 14.1: API scheme must be HTTPS
    func testAPISchemeMustBeHTTPS() {
        let httpAPI = DVKRuntimeConfiguration(
            apiBaseURL: URL(string: "http" + "://" + "api.example.test/v1"),
            voiceWebSocketURL: wssURL(),
            deviceID: "dvk-demo-device"
        )
        XCTAssertEqual(httpAPI.mode, .misconfigured)
    }

    // 14.1: voice scheme must be WSS
    func testVoiceSchemeMustBeWSS() {
        let wsVoice = DVKRuntimeConfiguration(
            apiBaseURL: httpsURL(),
            voiceWebSocketURL: URL(string: "ws" + "://" + "voice.example.test/v1/voice/ws"),
            deviceID: "dvk-demo-device"
        )
        XCTAssertEqual(wsVoice.mode, .misconfigured)
    }

    // 14.1: enableMock forces mock mode even with full values
    func testEnableMockForcesMockMode() {
        let configuration = DVKRuntimeConfiguration(
            apiBaseURL: httpsURL(),
            voiceWebSocketURL: wssURL(),
            deviceID: "dvk-demo-device",
            enableMock: true
        )
        XCTAssertEqual(configuration.mode, .mock)
    }

    func testLiveRequiresNonEmptyHost() {
        XCTAssertFalse(DVKRuntimeConfiguration.isAllowedRemoteURL(
            URL(string: "https" + "://" + "/v1"), scheme: "https"
        ))
        XCTAssertTrue(DVKRuntimeConfiguration.isAllowedRemoteURL(
            httpsURL(), scheme: "https"
        ))
    }

    func testFromInfoDictionaryEmptyDefaultsToMock() {
        let configuration = DVKRuntimeConfiguration.fromInfoDictionary([:])
        XCTAssertEqual(configuration.mode, .mock)
        XCTAssertEqual(configuration.buildSHA, "")
    }

    func testFromInfoDictionaryReadsKeys() {
        let configuration = DVKRuntimeConfiguration.fromInfoDictionary([
            "API_BASE_URL": "https" + "://" + "api.example.test/v1",
            "VOICE_WS_URL": "wss" + "://" + "voice.example.test/v1/voice/ws",
            "DEVICE_ID": "dvk-demo-device",
            "APP_BUILD_SHA": "abcdef",
            "APP_BUILD_TIME": "2026-08-03"
        ])
        XCTAssertEqual(configuration.mode, .live)
        XCTAssertEqual(configuration.buildSHA, "abcdef")
        XCTAssertEqual(configuration.buildTime, "2026-08-03")
    }

    func testFromProcessInfoReadsEnvironment() {
        let configuration = DVKRuntimeConfiguration.fromProcessInfo(environment: [
            "API_BASE_URL": "https" + "://" + "api.example.test/v1",
            "VOICE_WS_URL": "wss" + "://" + "voice.example.test/v1/voice/ws",
            "DEVICE_ID": "dvk-demo-device"
        ])
        XCTAssertEqual(configuration.mode, .live)
    }

    func testStatusDescriptionIsProviderNeutral() {
        XCTAssertEqual(DVKRuntimeConfiguration.mock.mode, .mock)
        XCTAssertFalse(DVKRuntimeConfiguration.mock.statusDescription.isEmpty)
        XCTAssertFalse(DVKRuntimeConfiguration.mock.statusDescription.contains("synthetic-token"))
    }
}
