import Foundation
import XCTest
@testable import XiaomaoApp

final class RuntimeConnectionBundleTests: XCTestCase {
    func testRoundTripPreservesSharedChatTarget() throws {
        let configuration = RuntimeConfiguration(
            apiBaseURL: try XCTUnwrap(URL(string: "https://api.example.test")),
            voiceWebSocketURL: try XCTUnwrap(URL(string: "wss://voice.example.test/ws")),
            deviceID: "developer-device",
            chatTargetDeviceID: "user-device"
        )

        let encoded = try RuntimeConnectionBundle.encode(
            configuration: configuration,
            token: "secret-token"
        )
        let decoded = try RuntimeConnectionBundle.decode(encoded)

        XCTAssertEqual(decoded.configuration, configuration)
        XCTAssertEqual(decoded.token, "secret-token")
    }

    func testLegacyBundleWithoutTargetRemainsValid() throws {
        let json = """
        {"backend":"https://api.example.test","voice":"wss://voice.example.test/ws","device":"user-device","token":"secret-token"}
        """
        let payload = try XCTUnwrap(json.data(using: .utf8))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let decoded = try RuntimeConnectionBundle.decode("XM1." + payload)

        XCTAssertNil(decoded.configuration.chatTargetDeviceID)
    }

    func testSelfTargetIsDropped() throws {
        let configuration = RuntimeConfiguration(
            apiBaseURL: try XCTUnwrap(URL(string: "https://api.example.test")),
            voiceWebSocketURL: try XCTUnwrap(URL(string: "wss://voice.example.test/ws")),
            deviceID: "user-device",
            chatTargetDeviceID: "user-device"
        )

        XCTAssertNil(configuration.chatTargetDeviceID)
    }

    @MainActor
    func testBundledTargetAndTokenSurviveStoreReload() throws {
        let configuration = RuntimeConfiguration(
            apiBaseURL: try XCTUnwrap(URL(string: "https://api.example.test")),
            voiceWebSocketURL: try XCTUnwrap(URL(string: "wss://voice.example.test/ws")),
            deviceID: "developer-device",
            chatTargetDeviceID: "user-device"
        )
        let rawBundle = try RuntimeConnectionBundle.encode(
            configuration: configuration,
            token: "secret-token"
        )
        let configurationStore = MemoryRuntimeConfigurationStore()
        let tokenStore = MemoryAuthTokenStore()

        AppCoordinator.installBundledRuntimeConfiguration(
            rawBundle,
            configurationStore: configurationStore,
            tokenStore: tokenStore
        )

        XCTAssertEqual(configurationStore.load()?.chatTargetDeviceID, "user-device")
        XCTAssertEqual(tokenStore.load(), "secret-token")

        AppCoordinator.installBundledRuntimeConfiguration(
            rawBundle,
            configurationStore: configurationStore,
            tokenStore: tokenStore
        )
        XCTAssertEqual(configurationStore.load(), configuration)
    }

    @MainActor
    func testBundledDeveloperTargetDoesNotLeakIntoDifferentExistingDevice() throws {
        let developerConfiguration = RuntimeConfiguration(
            apiBaseURL: try XCTUnwrap(URL(string: "https://api.example.test")),
            voiceWebSocketURL: try XCTUnwrap(URL(string: "wss://voice.example.test/ws")),
            deviceID: "developer-device",
            chatTargetDeviceID: "user-device"
        )
        let rawBundle = try RuntimeConnectionBundle.encode(
            configuration: developerConfiguration,
            token: "developer-token"
        )
        let existingUserConfiguration = RuntimeConfiguration(
            apiBaseURL: try XCTUnwrap(URL(string: "https://api.example.test")),
            voiceWebSocketURL: try XCTUnwrap(URL(string: "wss://voice.example.test/ws")),
            deviceID: "user-device"
        )
        let configurationStore = MemoryRuntimeConfigurationStore(
            configuration: existingUserConfiguration
        )
        let tokenStore = MemoryAuthTokenStore()
        try tokenStore.save("user-token")

        AppCoordinator.installBundledRuntimeConfiguration(
            rawBundle,
            configurationStore: configurationStore,
            tokenStore: tokenStore
        )

        XCTAssertEqual(configurationStore.load()?.deviceID, "user-device")
        XCTAssertNil(configurationStore.load()?.chatTargetDeviceID)
        XCTAssertEqual(tokenStore.load(), "user-token")
    }
}

private final class MemoryRuntimeConfigurationStore: RuntimeConfigurationStoring, @unchecked Sendable {
    private var configuration: RuntimeConfiguration?

    init(configuration: RuntimeConfiguration? = nil) {
        self.configuration = configuration
    }

    func load() -> RuntimeConfiguration? { configuration }
    func save(_ configuration: RuntimeConfiguration) throws { self.configuration = configuration }
    func clear() throws { configuration = nil }
}
