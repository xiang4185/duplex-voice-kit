#if DEBUG
import XCTest
@testable import XiaomaoApp

final class DeveloperDiagnosticsTests: XCTestCase {
    func testMockOfflineSnapshotShowsStatusesWithoutValues() {
        let environment = AppEnvironment(
            apiBaseURL: nil,
            voiceWebSocketURL: nil,
            deviceID: "",
            appEnvironment: "debug",
            enableMockVoice: true,
            enableMemory: true,
            defaultVoiceRoute: .b,
            appBuildSHA: "abc123",
            appBuildTime: "build-time",
            hostAdapters: .empty
        )

        let snapshot = DeveloperDiagnosticsSnapshot.make(
            environment: environment,
            credentialState: .noCredentials,
            deviceState: .unbound,
            launchRoute: .home
        )

        XCTAssertEqual(snapshot.backendStatus, "Not Configured")
        XCTAssertEqual(snapshot.voiceStatus, "Configured")
        XCTAssertEqual(snapshot.credentialStatus, "Missing")
        XCTAssertEqual(snapshot.deviceStatus, "Unbound")
        XCTAssertEqual(snapshot.mockStatus, "Enabled")
        XCTAssertEqual(snapshot.launchRouteStatus, "Home")
        XCTAssertEqual(snapshot.backendAdapterStatus, "Empty")
        XCTAssertEqual(snapshot.voiceAdapterStatus, "Empty")
    }

    func testProductionFailureSnapshotShowsConfigurationError() {
        let environment = AppEnvironment(
            apiBaseURL: nil,
            voiceWebSocketURL: nil,
            deviceID: "",
            appEnvironment: "release",
            enableMockVoice: false,
            enableMemory: false,
            defaultVoiceRoute: .b,
            appBuildSHA: "",
            appBuildTime: ""
        )

        let snapshot = DeveloperDiagnosticsSnapshot.make(
            environment: environment,
            credentialState: .expired,
            deviceState: .expired,
            launchRoute: .configurationError
        )

        XCTAssertEqual(snapshot.backendStatus, "Not Configured")
        XCTAssertEqual(snapshot.voiceStatus, "Not Configured")
        XCTAssertEqual(snapshot.credentialStatus, "Expired")
        XCTAssertEqual(snapshot.deviceStatus, "Expired")
        XCTAssertEqual(snapshot.mockStatus, "Disabled")
        XCTAssertEqual(snapshot.launchRouteStatus, "Configuration Error")
        XCTAssertEqual(snapshot.buildSHA, "Unknown")
        XCTAssertEqual(snapshot.buildTime, "Unknown")
    }
}
#endif
