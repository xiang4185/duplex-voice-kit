import Foundation
import XCTest
@testable import XiaomaoApp

final class ProductionHostAdapterTests: XCTestCase {
    func testFactoryDefaultsToEmptyWithoutNetworkActivity() async {
        let dependencies = HostAdapterFactory.make(
            mode: .empty,
            apiBaseURL: nil,
            voiceWebSocketURL: nil,
            tokenStore: MemoryAuthTokenStore(),
            deviceID: ""
        )

        let backendSnapshot = await dependencies.backend.snapshot()
        let voiceSnapshot = await dependencies.voice.snapshot()
        XCTAssertEqual(dependencies.mode, .empty)
        XCTAssertEqual(backendSnapshot.networkRequestCount, 0)
        XCTAssertEqual(voiceSnapshot.networkConnectionCount, 0)
    }

    func testFactoryMockModeRemainsOffline() async throws {
        let dependencies = HostAdapterFactory.make(
            mode: .mock,
            apiBaseURL: nil,
            voiceWebSocketURL: nil,
            tokenStore: MemoryAuthTokenStore(),
            deviceID: ""
        )

        try await dependencies.voice.connect()
        await dependencies.voice.disconnect()
        let backendSnapshot = await dependencies.backend.snapshot()
        let voiceSnapshot = await dependencies.voice.snapshot()
        XCTAssertEqual(dependencies.mode, .mock)
        XCTAssertEqual(backendSnapshot.networkRequestCount, 0)
        XCTAssertEqual(voiceSnapshot.networkConnectionCount, 0)
    }

    func testProductionBackendRejectsNonHTTPSAndHostOverrideRoutes() async throws {
        let credentials = MockCredentialProvider(
            credentials: AuthCredentials(accessToken: "synthetic-token", refreshToken: nil)
        )
        let device = MockDeviceBindingProvider(state: .bound(deviceID: "synthetic-device"))

        XCTAssertThrowsError(try ProductionBackendAdapter(
            baseURL: try XCTUnwrap(URL(string: "http://example.invalid")),
            credentials: credentials,
            deviceBinding: device
        )) { error in
            XCTAssertEqual(error as? HostAdapterError, .invalidConfiguration)
        }

        let adapter = try ProductionBackendAdapter(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
            credentials: credentials,
            deviceBinding: device,
            session: makeSession { request in
                XCTFail("Invalid route must not start a request")
                return try Self.response(for: request, statusCode: 200, data: Data())
            }
        )
        do {
            _ = try await adapter.execute(
                BackendAdapterRequest(route: "https://example.invalid/override")
            )
            XCTFail("Host override must fail closed")
        } catch {
            XCTAssertEqual(error as? HostAdapterError, .invalidConfiguration)
        }
        let snapshot = await adapter.snapshot()
        XCTAssertEqual(snapshot.networkRequestCount, 0)
    }

    func testBackendMissingCredentialDoesNotStartRequest() async throws {
        let counter = RequestCounter()
        let adapter = try ProductionBackendAdapter(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
            credentials: EmptyCredentialProvider(),
            deviceBinding: InjectedDeviceBindingProviderAdapter(deviceID: "synthetic-device"),
            session: makeSession { request in
                counter.increment()
                return try Self.response(for: request, statusCode: 200, data: Data())
            }
        )

        await assertUnauthorized {
            _ = try await adapter.execute(BackendAdapterRequest(route: "/v1/chat"))
        }
        XCTAssertEqual(counter.value, 0)
        let snapshot = await adapter.snapshot()
        XCTAssertEqual(snapshot.networkRequestCount, 0)
    }

    func testBackendMissingDeviceDoesNotStartRequest() async throws {
        let counter = RequestCounter()
        let credentials = MockCredentialProvider(
            credentials: AuthCredentials(accessToken: "synthetic-token", refreshToken: nil)
        )
        let adapter = try ProductionBackendAdapter(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
            credentials: credentials,
            deviceBinding: InjectedDeviceBindingProviderAdapter(deviceID: ""),
            session: makeSession { request in
                counter.increment()
                return try Self.response(for: request, statusCode: 200, data: Data())
            }
        )

        await assertUnauthorized {
            _ = try await adapter.execute(BackendAdapterRequest(route: "/v1/chat"))
        }
        XCTAssertEqual(counter.value, 0)
        let snapshot = await adapter.snapshot()
        XCTAssertEqual(snapshot.networkRequestCount, 0)
    }

    func testBackendSyntheticRequestHasSecurityHeadersAndSnapshotIsRedacted() async throws {
        let captured = CapturedRequest()
        let tokenStore = MemoryAuthTokenStore()
        try tokenStore.save("synthetic-token")
        let adapter = try ProductionBackendAdapter(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
            credentials: KeychainCredentialProviderAdapter(tokenStore: tokenStore),
            deviceBinding: InjectedDeviceBindingProviderAdapter(deviceID: "synthetic-device"),
            session: makeSession { request in
                captured.set(request)
                return try Self.response(
                    for: request,
                    statusCode: 200,
                    data: Data(#"{"ok":true}"#.utf8)
                )
            }
        )

        _ = try await adapter.execute(BackendAdapterRequest(
            route: "/v1/chat",
            payload: Data(#"{"message":"synthetic"}"#.utf8)
        ))

        let request = try XCTUnwrap(captured.value)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
        XCTAssertFalse(request.value(forHTTPHeaderField: "X-Device-ID")?.isEmpty ?? true)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try requestBodyData(from: request)) as? [String: Any]
        )
        XCTAssertNotNil(body["device_id"])
        XCTAssertEqual(body["message"] as? String, "synthetic")

        let snapshotText = String(describing: await adapter.snapshot())
        XCTAssertFalse(snapshotText.contains("example.invalid"))
        XCTAssertFalse(snapshotText.contains("synthetic-token"))
        XCTAssertFalse(snapshotText.contains("synthetic-device"))
        XCTAssertFalse(snapshotText.contains("synthetic"))
    }

    func testBackendMapsUnauthorizedAndNonSuccessWithoutResponseBodyLeak() async throws {
        let status = MutableStatusCode(401)
        let tokenStore = MemoryAuthTokenStore()
        try tokenStore.save("synthetic-token")
        let adapter = try ProductionBackendAdapter(
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
            credentials: KeychainCredentialProviderAdapter(tokenStore: tokenStore),
            deviceBinding: InjectedDeviceBindingProviderAdapter(deviceID: "synthetic-device"),
            session: makeSession { request in
                try Self.response(
                    for: request,
                    statusCode: status.value,
                    data: Data(#"{"error":"sensitive-server-detail"}"#.utf8)
                )
            }
        )

        await assertUnauthorized {
            _ = try await adapter.execute(BackendAdapterRequest(route: "/v1/chat"))
        }
        status.value = 503
        do {
            _ = try await adapter.execute(BackendAdapterRequest(route: "/v1/chat"))
            XCTFail("Expected safe server error")
        } catch AppError.server(let code) {
            XCTAssertEqual(code, "http_503")
            XCTAssertFalse(code.contains("sensitive"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProductionVoiceRejectsNonWSS() throws {
        XCTAssertThrowsError(try ProductionVoiceAdapter(
            url: try XCTUnwrap(URL(string: "ws://example.invalid/v1/voice/ws")),
            credentials: EmptyCredentialProvider(),
            deviceBinding: EmptyDeviceBindingProvider(),
            client: VoiceClientSpy()
        )) { error in
            XCTAssertEqual(error as? HostAdapterError, .invalidConfiguration)
        }
    }

    func testVoiceMissingCredentialOrDeviceDoesNotConnect() async throws {
        let credentialSpy = VoiceClientSpy()
        let missingCredential = try ProductionVoiceAdapter(
            url: try XCTUnwrap(URL(string: "wss://example.invalid/v1/voice/ws")),
            credentials: EmptyCredentialProvider(),
            deviceBinding: InjectedDeviceBindingProviderAdapter(deviceID: "synthetic-device"),
            client: credentialSpy
        )
        await assertUnauthorized { try await missingCredential.connect() }
        let credentialConnectCount = await credentialSpy.connectCountValue()
        let missingCredentialSnapshot = await missingCredential.snapshot()
        XCTAssertEqual(credentialConnectCount, 0)
        XCTAssertEqual(missingCredentialSnapshot.networkConnectionCount, 0)

        let deviceSpy = VoiceClientSpy()
        let missingDevice = try ProductionVoiceAdapter(
            url: try XCTUnwrap(URL(string: "wss://example.invalid/v1/voice/ws")),
            credentials: MockCredentialProvider(
                credentials: AuthCredentials(accessToken: "synthetic-token", refreshToken: nil)
            ),
            deviceBinding: EmptyDeviceBindingProvider(),
            client: deviceSpy
        )
        await assertUnauthorized { try await missingDevice.connect() }
        let deviceConnectCount = await deviceSpy.connectCountValue()
        let missingDeviceSnapshot = await missingDevice.snapshot()
        XCTAssertEqual(deviceConnectCount, 0)
        XCTAssertEqual(missingDeviceSnapshot.networkConnectionCount, 0)
    }

    func testVoiceSyntheticConnectionUsesCredentialDeviceAndProtocolContract() async throws {
        let spy = VoiceClientSpy()
        let adapter = try ProductionVoiceAdapter(
            url: try XCTUnwrap(URL(string: "wss://example.invalid/v1/voice/ws")),
            credentials: MockCredentialProvider(
                credentials: AuthCredentials(accessToken: "synthetic-token", refreshToken: nil)
            ),
            deviceBinding: InjectedDeviceBindingProviderAdapter(deviceID: "synthetic-device"),
            client: spy
        )

        try await adapter.connect()

        let observation = await spy.connectionObservation()
        XCTAssertTrue(observation.receivedSecureScheme)
        XCTAssertTrue(observation.receivedCredential)
        XCTAssertTrue(observation.receivedDevice)
        XCTAssertEqual(VoiceEvent.protocolVersion, "0.2")
        let snapshotText = String(describing: await adapter.snapshot())
        XCTAssertFalse(snapshotText.contains("example.invalid"))
        XCTAssertFalse(snapshotText.contains("synthetic-token"))
        XCTAssertFalse(snapshotText.contains("synthetic-device"))
    }

    func testVoiceSendBeforeConnectFailsClosed() async throws {
        let adapter = try ProductionVoiceAdapter(
            url: try XCTUnwrap(URL(string: "wss://example.invalid/v1/voice/ws")),
            credentials: MockCredentialProvider(
                credentials: AuthCredentials(accessToken: "synthetic-token", refreshToken: nil)
            ),
            deviceBinding: InjectedDeviceBindingProviderAdapter(deviceID: "synthetic-device"),
            client: VoiceClientSpy()
        )

        do {
            try await adapter.send(makeVoiceEvent())
            XCTFail("Send must fail before connect")
        } catch {
            XCTAssertEqual(error as? HostAdapterError, .notConnected)
        }
        let snapshot = await adapter.snapshot()
        XCTAssertEqual(snapshot.sendCallCount, 0)
    }

    func testCredentialProviderLoadClearAndRefreshFailClosed() async throws {
        let store = MemoryAuthTokenStore()
        try store.save("synthetic-token")
        let provider = KeychainCredentialProviderAdapter(tokenStore: store)

        let loaded = try await provider.obtainCredentials()
        XCTAssertTrue(loaded?.hasAccessToken == true)
        do {
            _ = try await provider.refreshCredentials(
                AuthCredentials(accessToken: "synthetic-token", refreshToken: nil)
            )
            XCTFail("Refresh must fail closed without a server contract")
        } catch {
            XCTAssertEqual(error as? HostAdapterError, .unsupportedOperation)
        }
        try await provider.clearCredentials()
        let cleared = try await provider.obtainCredentials()
        XCTAssertNil(cleared)
    }

    func testDeviceProviderBoundUnboundAndUnsupportedOperationsFailClosed() async {
        let unbound = InjectedDeviceBindingProviderAdapter(deviceID: "   ")
        let unboundState = await unbound.currentState()
        XCTAssertEqual(unboundState, .unbound)

        let bound = InjectedDeviceBindingProviderAdapter(deviceID: "synthetic-device")
        let boundState = await bound.currentState()
        XCTAssertTrue(boundState.allowsHome)
        do {
            _ = try await bound.bind()
            XCTFail("Remote bind must not be invented")
        } catch {
            XCTAssertEqual(error as? HostAdapterError, .unsupportedOperation)
        }
        do {
            _ = try await bound.unbind()
            XCTFail("Remote unbind must not be invented")
        } catch {
            XCTAssertEqual(error as? HostAdapterError, .unsupportedOperation)
        }
    }

    @MainActor
    func testAppCoordinatorSelectsEmptyMockAndProductionHostPaths() throws {
        let empty = AppCoordinator(environment: makeEnvironment(
            requestedMode: .empty,
            dependencies: .empty
        ))
        let mock = AppCoordinator(environment: makeEnvironment(
            requestedMode: .mock,
            dependencies: .mock
        ))

        let tokenStore = MemoryAuthTokenStore()
        try tokenStore.save("synthetic-token")
        let productionDependencies = HostAdapterFactory.make(
            mode: .production,
            apiBaseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
            voiceWebSocketURL: try XCTUnwrap(URL(string: "wss://example.invalid/v1/voice/ws")),
            tokenStore: tokenStore,
            deviceID: "synthetic-device",
            backendSession: makeSession { request in
                try Self.response(for: request, statusCode: 200, data: Data())
            },
            voiceClient: VoiceClientSpy()
        )
        let production = AppCoordinator(
            environment: makeEnvironment(
                requestedMode: .production,
                dependencies: productionDependencies
            ),
            tokenStore: tokenStore
        )

        XCTAssertEqual(empty.hostAdapters.mode, .empty)
        XCTAssertEqual(mock.hostAdapters.mode, .mock)
        XCTAssertTrue(mock.chatService is MockChatService)
        XCTAssertEqual(production.hostAdapters.mode, .production)
        XCTAssertTrue(production.chatService is ChatService)
    }

    func testChatServiceActuallyUsesBackendAdapter() async throws {
        let backend = RecordingBackendAdapter()
        let service = ChatService(backend: backend)

        let result = try await service.send(
            message: "synthetic",
            sessionID: "session",
            requestID: "request"
        )

        let route = await backend.lastRoute()
        let invocationCount = await backend.invocationCount()
        XCTAssertEqual(result.sessionID, "session")
        XCTAssertEqual(route, "/v1/chat")
        XCTAssertEqual(invocationCount, 1)
    }

    @MainActor
    func testEmptyReleaseStyleEnvironmentFailsClosed() async {
        let coordinator = AppCoordinator(environment: makeEnvironment(
            requestedMode: .empty,
            dependencies: .empty
        ))

        await coordinator.start()

        let backendSnapshot = await coordinator.hostAdapters.backend.snapshot()
        let voiceSnapshot = await coordinator.hostAdapters.voice.snapshot()
        XCTAssertEqual(coordinator.screen, .configurationError)
        XCTAssertEqual(backendSnapshot.networkRequestCount, 0)
        XCTAssertEqual(voiceSnapshot.networkConnectionCount, 0)
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        ProductionURLProtocolState.shared.setHandler(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductionURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func requestBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw try XCTUnwrap(stream.streamError)
            }
            if count == 0 {
                break
            }
            body.append(buffer, count: count)
        }
        return body
    }

    private func makeEnvironment(
        requestedMode: HostAdapterMode,
        dependencies: HostAdapterDependencies
    ) -> AppEnvironment {
        AppEnvironment(
            apiBaseURL: requestedMode == .production
                ? URL(string: "https://example.invalid") : nil,
            voiceWebSocketURL: requestedMode == .production
                ? URL(string: "wss://example.invalid/v1/voice/ws") : nil,
            deviceID: requestedMode == .production ? "synthetic-device" : "",
            appEnvironment: "test",
            enableMockVoice: requestedMode == .mock,
            enableMemory: false,
            defaultVoiceRoute: .b,
            appBuildSHA: "test",
            appBuildTime: "test",
            requestedHostAdapterMode: requestedMode,
            hostAdapters: dependencies
        )
    }

    private func makeVoiceEvent() -> VoiceEvent {
        VoiceEvent(
            version: VoiceEvent.protocolVersion,
            eventID: "event",
            traceID: "trace",
            sessionID: "session",
            sequence: 1,
            timestamp: 1,
            type: .ping,
            payload: [:]
        )
    }

    private func assertUnauthorized(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int,
        data: Data
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        return (response, data)
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class CapturedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func set(_ request: URLRequest) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    var value: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private final class MutableStatusCode: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int

    init(_ value: Int) { storage = value }

    var value: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private final class ProductionURLProtocolState: @unchecked Sendable {
    static let shared = ProductionURLProtocolState()

    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    func setHandler(
        _ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        guard let handler else { throw ProductionURLProtocolError.missingHandler }
        return try handler(request)
    }
}

private enum ProductionURLProtocolError: Error {
    case missingHandler
}

private final class ProductionURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try ProductionURLProtocolState.shared.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct VoiceConnectionObservation: Sendable {
    let receivedSecureScheme: Bool
    let receivedCredential: Bool
    let receivedDevice: Bool
}

private actor VoiceClientSpy: VoiceWebSocketClient {
    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>
    private nonisolated let eventStream: AsyncStream<VoiceEvent>
    private var connected = false
    private var connectCount = 0
    private var observation = VoiceConnectionObservation(
        receivedSecureScheme: false,
        receivedCredential: false,
        receivedDevice: false
    )

    init() {
        lifecycleEvents = AsyncStream { continuation in
            continuation.finish()
        }
        eventStream = AsyncStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> { eventStream }

    func connect(url: URL, token: String, deviceID: String) async throws {
        connectCount += 1
        observation = VoiceConnectionObservation(
            receivedSecureScheme: url.scheme?.lowercased() == "wss",
            receivedCredential: !token.isEmpty,
            receivedDevice: !deviceID.isEmpty
        )
        connected = true
    }

    func send(_ event: VoiceEvent) async throws {
        _ = event
        guard connected else { throw AppError.networkUnavailable }
    }

    func ping() async throws {
        guard connected else { throw AppError.networkUnavailable }
    }

    func disconnect() async { connected = false }
    func isConnected() async -> Bool { connected }
    func connectCountValue() async -> Int { connectCount }
    func connectionObservation() async -> VoiceConnectionObservation { observation }
}

private actor RecordingBackendAdapter: BackendAdapter {
    private var routes: [String] = []

    func execute(_ request: BackendAdapterRequest) async throws -> BackendAdapterResponse {
        routes.append(request.route)
        let data = Data(#"""
        {
            "session_id":"session",
            "turn_id":"synthetic-turn",
            "messages":[
                {
                    "id":"synthetic-user",
                    "role":"user",
                    "participant":"user",
                    "turn_id":"synthetic-turn",
                    "status":"completed",
                    "content":"synthetic",
                    "created_at":"2026-08-06T00:00:00Z"
                },
                {
                    "id":"synthetic-companion",
                    "role":"assistant",
                    "participant":"companion",
                    "turn_id":"synthetic-turn",
                    "status":"completed",
                    "content":"synthetic",
                    "created_at":"2026-08-06T00:00:01Z"
                }
            ],
            "participant_results":[
                {
                    "participant":"companion",
                    "turn_id":"synthetic-turn",
                    "status":"completed",
                    "retryable":false,
                    "message":{
                        "id":"synthetic-companion",
                        "role":"assistant",
                        "participant":"companion",
                        "turn_id":"synthetic-turn",
                        "status":"completed",
                        "content":"synthetic",
                        "created_at":"2026-08-06T00:00:01Z"
                    }
                }
            ],
            "route":"direct",
            "degraded":false,
            "persisted":true
        }
        """#.utf8)
        return BackendAdapterResponse(statusCode: 200, payload: data)
    }

    func snapshot() async -> BackendAdapterSnapshot {
        BackendAdapterSnapshot(
            mode: .production,
            invocationCount: routes.count,
            networkRequestCount: 0
        )
    }

    func lastRoute() async -> String? { routes.last }
    func invocationCount() async -> Int { routes.count }
}
