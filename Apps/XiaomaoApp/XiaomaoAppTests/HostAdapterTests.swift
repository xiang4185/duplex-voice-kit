import Foundation
import XCTest
@testable import XiaomaoApp

@MainActor
final class HostAdapterTests: XCTestCase {
    func testEmptyAdaptersFailClosedWithoutNetworkActivity() async {
        let backend = EmptyBackendAdapter()
        let voice = EmptyVoiceAdapter()

        do {
            _ = try await backend.execute(BackendAdapterRequest(route: "offline-check"))
            XCTFail("Empty backend adapter must fail closed")
        } catch {
            XCTAssertEqual(error as? HostAdapterError, .unavailable)
        }

        do {
            try await voice.connect()
            XCTFail("Empty voice adapter must fail closed")
        } catch {
            XCTAssertEqual(error as? HostAdapterError, .unavailable)
        }

        let backendSnapshot = await backend.snapshot()
        let voiceSnapshot = await voice.snapshot()
        XCTAssertEqual(backendSnapshot.mode, .empty)
        XCTAssertEqual(backendSnapshot.networkRequestCount, 0)
        XCTAssertEqual(voiceSnapshot.mode, .empty)
        XCTAssertFalse(voiceSnapshot.isConnected)
        XCTAssertEqual(voiceSnapshot.networkConnectionCount, 0)
    }

    func testMockAdaptersUseCannedResultsWithoutNetworkActivity() async throws {
        let expected = BackendAdapterResponse(
            statusCode: 202,
            payload: Data("mock-response".utf8)
        )
        let backend = MockBackendAdapter(response: expected)
        let voice = MockVoiceAdapter()

        let response = try await backend.execute(
            BackendAdapterRequest(route: "mock-route", payload: Data("mock-request".utf8))
        )
        try await voice.connect()
        try await voice.send(makeVoiceEvent())
        await voice.disconnect()

        XCTAssertEqual(response, expected)
        let backendSnapshot = await backend.snapshot()
        let voiceSnapshot = await voice.snapshot()
        XCTAssertEqual(backendSnapshot.mode, .mock)
        XCTAssertEqual(backendSnapshot.invocationCount, 1)
        XCTAssertEqual(backendSnapshot.networkRequestCount, 0)
        XCTAssertEqual(voiceSnapshot.mode, .mock)
        XCTAssertEqual(voiceSnapshot.connectCallCount, 1)
        XCTAssertEqual(voiceSnapshot.sendCallCount, 1)
        XCTAssertEqual(voiceSnapshot.disconnectCallCount, 1)
        XCTAssertEqual(voiceSnapshot.networkConnectionCount, 0)
        XCTAssertFalse(voiceSnapshot.isConnected)
    }

    func testDependencyInjectionUsesProvidedHostAdapters() async throws {
        let backend = MockBackendAdapter(
            response: BackendAdapterResponse(statusCode: 204)
        )
        let voice = MockVoiceAdapter()
        let credentials = MockCredentialProvider(
            credentials: AuthCredentials(accessToken: "synthetic-token", refreshToken: nil)
        )
        let deviceBinding = MockDeviceBindingProvider(
            state: .bound(deviceID: "synthetic-device")
        )
        let dependencies = HostAdapterDependencies(
            mode: .mock,
            backend: backend,
            voice: voice,
            credentials: credentials,
            deviceBinding: deviceBinding
        )
        let coordinator = AppCoordinator(
            environment: makeEnvironment(hostAdapters: dependencies)
        )

        _ = try await coordinator.hostAdapters.backend.execute(
            BackendAdapterRequest(route: "injected-route")
        )
        let obtained = try await coordinator.hostAdapters.credentials.obtainCredentials()
        let bindingState = await coordinator.hostAdapters.deviceBinding.currentState()
        let backendSnapshot = await backend.snapshot()

        XCTAssertEqual(backendSnapshot.invocationCount, 1)
        XCTAssertEqual(obtained?.accessToken, "synthetic-token")
        XCTAssertEqual(bindingState, .bound(deviceID: "synthetic-device"))
    }

    func testDefaultStartupUsesEmptyProviders() async throws {
        let coordinator = AppCoordinator(environment: makeEnvironment())
        await coordinator.start()

        let credentials = try await coordinator.hostAdapters.credentials.obtainCredentials()
        let bindingState = await coordinator.hostAdapters.deviceBinding.currentState()
        let backendSnapshot = await coordinator.hostAdapters.backend.snapshot()
        let voiceSnapshot = await coordinator.hostAdapters.voice.snapshot()

        XCTAssertNil(credentials)
        XCTAssertEqual(bindingState, .unbound)
        XCTAssertEqual(backendSnapshot.mode, .empty)
        XCTAssertEqual(voiceSnapshot.mode, .empty)
    }

    func testBundleEnvironmentFactoryDefaultsToEmptyProviders() async throws {
        let dependencies = AppEnvironment.fromBundle().hostAdapters

        let credentials = try await dependencies.credentials.obtainCredentials()
        let bindingState = await dependencies.deviceBinding.currentState()
        let backendSnapshot = await dependencies.backend.snapshot()
        let voiceSnapshot = await dependencies.voice.snapshot()

        XCTAssertNil(credentials)
        XCTAssertEqual(bindingState, .unbound)
        XCTAssertEqual(backendSnapshot.mode, .empty)
        XCTAssertEqual(voiceSnapshot.mode, .empty)
    }

    func testDefaultDependencyContainerDoesNotConnectBackendOrVoice() async {
        let dependencies = HostAdapterDependencies.empty

        await dependencies.voice.disconnect()
        let backendSnapshot = await dependencies.backend.snapshot()
        let voiceSnapshot = await dependencies.voice.snapshot()

        XCTAssertEqual(backendSnapshot.invocationCount, 0)
        XCTAssertEqual(backendSnapshot.networkRequestCount, 0)
        XCTAssertEqual(voiceSnapshot.connectCallCount, 0)
        XCTAssertEqual(voiceSnapshot.networkConnectionCount, 0)
        XCTAssertFalse(voiceSnapshot.isConnected)
    }

    private func makeEnvironment(
        hostAdapters: HostAdapterDependencies = .empty
    ) -> AppEnvironment {
        AppEnvironment(
            apiBaseURL: nil,
            voiceWebSocketURL: nil,
            deviceID: "",
            appEnvironment: "test",
            enableMockVoice: hostAdapters.mode == .mock,
            enableMemory: false,
            defaultVoiceRoute: .b,
            appBuildSHA: "test",
            appBuildTime: "test",
            hostAdapters: hostAdapters
        )
    }

    private func makeVoiceEvent() -> VoiceEvent {
        VoiceEvent(
            version: VoiceEvent.protocolVersion,
            eventID: "mock-event",
            traceID: "mock-trace",
            sessionID: "mock-session",
            sequence: 1,
            timestamp: 1,
            type: .ping,
            payload: [:]
        )
    }
}
