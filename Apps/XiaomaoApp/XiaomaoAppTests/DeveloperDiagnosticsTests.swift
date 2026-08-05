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
            hostAdapters: .mock
        )

        let snapshot = DeveloperDiagnosticsSnapshot.make(
            environment: environment,
            hasCredentials: false,
            hasBoundDevice: false,
            launchRoute: .home
        )

        XCTAssertEqual(snapshot.backendStatus, "Not Configured")
        XCTAssertEqual(snapshot.voiceStatus, "Configured")
        XCTAssertEqual(snapshot.credentialStatus, "Missing")
        XCTAssertEqual(snapshot.deviceStatus, "Unbound")
        XCTAssertEqual(snapshot.mockStatus, "Enabled")
        XCTAssertEqual(snapshot.launchRouteStatus, "Home")
        XCTAssertEqual(snapshot.backendAdapterStatus, "Mock")
        XCTAssertEqual(snapshot.voiceAdapterStatus, "Mock")
    }

    func testProductionFailureSnapshotShowsConfigurationErrorAndSafeBuildPlaceholders() {
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
            hasCredentials: false,
            hasBoundDevice: false,
            launchRoute: .configurationError
        )

        XCTAssertEqual(snapshot.backendStatus, "Not Configured")
        XCTAssertEqual(snapshot.voiceStatus, "Not Configured")
        XCTAssertEqual(snapshot.credentialStatus, "Missing")
        XCTAssertEqual(snapshot.deviceStatus, "Unbound")
        XCTAssertEqual(snapshot.mockStatus, "Disabled")
        XCTAssertEqual(snapshot.launchRouteStatus, "Configuration Error")
        XCTAssertEqual(snapshot.buildSHA, "Unknown")
        XCTAssertEqual(snapshot.buildTime, "Unknown")
    }

    func testCredentialAndDevicePresentMapToValidAndBound() {
        let snapshot = DeveloperDiagnosticsSnapshot.make(
            environment: environment(hostAdapters: .empty),
            hasCredentials: true,
            hasBoundDevice: true,
            launchRoute: .home
        )

        XCTAssertEqual(snapshot.credentialStatus, "Valid")
        XCTAssertEqual(snapshot.deviceStatus, "Bound")
    }

    func testBindingLaunchRouteIsDisplayed() {
        let snapshot = DeveloperDiagnosticsSnapshot.make(
            environment: environment(hostAdapters: .empty),
            hasCredentials: false,
            hasBoundDevice: false,
            launchRoute: .binding
        )

        XCTAssertEqual(snapshot.launchRouteStatus, "Binding")
    }

    func testEmptyAdaptersAreDisplayedAsEmpty() {
        let snapshot = DeveloperDiagnosticsSnapshot.make(
            environment: environment(hostAdapters: .empty),
            hasCredentials: false,
            hasBoundDevice: false,
            launchRoute: .home
        )

        XCTAssertEqual(snapshot.backendAdapterStatus, "Empty")
        XCTAssertEqual(snapshot.voiceAdapterStatus, "Empty")
    }

    func testMockAdaptersAreDisplayedAsMock() {
        let adapters = HostAdapterDependencies(
            mode: .mock,
            backend: MockBackendAdapter(),
            voice: MockVoiceAdapter(),
            credentials: MockCredentialProvider(),
            deviceBinding: MockDeviceBindingProvider()
        )
        let snapshot = DeveloperDiagnosticsSnapshot.make(
            environment: environment(hostAdapters: adapters),
            hasCredentials: false,
            hasBoundDevice: false,
            launchRoute: .home
        )

        XCTAssertEqual(snapshot.backendAdapterStatus, "Mock")
        XCTAssertEqual(snapshot.voiceAdapterStatus, "Mock")
    }

    private func environment(hostAdapters: HostAdapterDependencies) -> AppEnvironment {
        AppEnvironment(
            apiBaseURL: nil,
            voiceWebSocketURL: nil,
            deviceID: "",
            appEnvironment: "debug",
            enableMockVoice: true,
            enableMemory: true,
            defaultVoiceRoute: .b,
            appBuildSHA: "abc123",
            appBuildTime: "build-time",
            hostAdapters: hostAdapters
        )
    }
}
#endif
