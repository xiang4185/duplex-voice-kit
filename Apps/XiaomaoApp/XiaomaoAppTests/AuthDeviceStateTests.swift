import XCTest
@testable import XiaomaoApp

final class AuthDeviceStateTests: XCTestCase {
    private let credentials = AuthCredentials(accessToken: "synthetic-token", refreshToken: nil)

    func testCredentialStatePermissions() {
        XCTAssertTrue(CredentialState.noCredentials.allowsBindingFlow)
        XCTAssertFalse(CredentialState.noCredentials.allowsChat)
        XCTAssertTrue(CredentialState.valid(credentials).allowsChat)
        XCTAssertTrue(CredentialState.valid(credentials).allowsVoice)
        XCTAssertTrue(CredentialState.valid(credentials).allowsHome)
        XCTAssertTrue(CredentialState.expired.allowsBindingFlow)
        XCTAssertTrue(CredentialState.revoked.allowsBindingFlow)
    }

    func testDeviceBindingLifecycleTransitions() {
        XCTAssertTrue(DeviceBindingState.unbound.canTransition(to: .binding))
        XCTAssertTrue(DeviceBindingState.binding.canTransition(to: .bound(deviceID: "synthetic-device")))
        XCTAssertTrue(DeviceBindingState.bound(deviceID: "synthetic-device").canTransition(to: .expired))
        XCTAssertTrue(DeviceBindingState.expired.canTransition(to: .rebinding))
        XCTAssertTrue(DeviceBindingState.rebinding.canTransition(to: .bound(deviceID: "replacement-device")))
        XCTAssertTrue(DeviceBindingState.bound(deviceID: "synthetic-device").canTransition(to: .unbinding))
        XCTAssertTrue(DeviceBindingState.unbinding.canTransition(to: .unbound))
        XCTAssertFalse(DeviceBindingState.unbound.allowsHome)
        XCTAssertTrue(DeviceBindingState.bound(deviceID: "synthetic-device").allowsHome)
        XCTAssertTrue(DeviceBindingState.expired.allowsBindingFlow)
    }

    func testLaunchRoutesConfigurationBindingAndHome() {
        XCTAssertEqual(
            AppCoordinator.launchRoute(
                environmentReady: false,
                mockMode: false,
                credentialState: .noCredentials,
                bindingState: .unbound
            ),
            .configurationError
        )
        XCTAssertEqual(
            AppCoordinator.launchRoute(
                environmentReady: true,
                mockMode: false,
                credentialState: .expired,
                bindingState: .expired
            ),
            .binding
        )
        XCTAssertEqual(
            AppCoordinator.launchRoute(
                environmentReady: true,
                mockMode: false,
                credentialState: .valid(credentials),
                bindingState: .bound(deviceID: "synthetic-device")
            ),
            .home
        )
    }

    func testMockLaunchNeedsNoProductionConfiguration() {
        XCTAssertEqual(
            AppCoordinator.launchRoute(
                environmentReady: false,
                mockMode: true,
                credentialState: .noCredentials,
                bindingState: .unbound
            ),
            .home
        )
    }

    func testEmptyAndMockProvidersAreOffline() async throws {
        let emptyCredentials = EmptyCredentialProvider()
        let emptyBinding = EmptyDeviceBindingProvider()
        let mockCredentials = MockCredentialProvider()
        let mockBinding = MockDeviceBindingProvider()

        let emptyCredentialResult = try await emptyCredentials.obtainCredentials()
        let emptyBindingResult = await emptyBinding.currentState()
        let mockCredentialResult = try await mockCredentials.obtainCredentials()
        let mockBindingResult = await mockBinding.currentState()

        XCTAssertNil(emptyCredentialResult)
        XCTAssertEqual(emptyBindingResult, .unbound)
        XCTAssertNil(mockCredentialResult)
        XCTAssertEqual(mockBindingResult, .unbound)
        let obtainCallCount = await mockCredentials.obtainCallCount
        let refreshCallCount = await mockCredentials.refreshCallCount
        let currentStateCallCount = await mockBinding.currentStateCallCount
        let bindCallCount = await mockBinding.bindCallCount
        XCTAssertEqual(obtainCallCount, 1)
        XCTAssertEqual(refreshCallCount, 0)
        XCTAssertEqual(currentStateCallCount, 1)
        XCTAssertEqual(bindCallCount, 0)
    }
}
