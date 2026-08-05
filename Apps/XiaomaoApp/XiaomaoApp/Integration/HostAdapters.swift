import Foundation

enum HostAdapterMode: String, Equatable, Sendable {
    case empty
    case mock
    case production

    static func requested(_ rawValue: String, enableMock: Bool) -> HostAdapterMode {
        if enableMock { return .mock }
        return HostAdapterMode(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .empty
    }

    var diagnosticLabel: String {
        switch self {
        case .empty: "Empty"
        case .mock: "Mock"
        case .production: "Production"
        }
    }
}

enum HostAdapterError: Error, Equatable, Sendable {
    case unavailable
    case notConnected
    case invalidConfiguration
    case unsupportedOperation
    case invalidResponse
}

struct BackendAdapterRequest: Equatable, Sendable {
    let route: String
    let payload: Data

    init(route: String, payload: Data = Data()) {
        self.route = route
        self.payload = payload
    }
}

struct BackendAdapterResponse: Equatable, Sendable {
    let statusCode: Int
    let payload: Data

    init(statusCode: Int, payload: Data = Data()) {
        self.statusCode = statusCode
        self.payload = payload
    }
}

struct BackendAdapterSnapshot: Equatable, Sendable {
    let mode: HostAdapterMode
    let invocationCount: Int
    let networkRequestCount: Int
}

protocol BackendAdapter: Sendable {
    func execute(_ request: BackendAdapterRequest) async throws -> BackendAdapterResponse
    func snapshot() async -> BackendAdapterSnapshot
}

struct EmptyBackendAdapter: BackendAdapter {
    func execute(_ request: BackendAdapterRequest) async throws -> BackendAdapterResponse {
        _ = request
        throw HostAdapterError.unavailable
    }

    func snapshot() async -> BackendAdapterSnapshot {
        BackendAdapterSnapshot(mode: .empty, invocationCount: 0, networkRequestCount: 0)
    }
}

actor MockBackendAdapter: BackendAdapter {
    private let response: BackendAdapterResponse
    private var invocationCount = 0

    init(response: BackendAdapterResponse = BackendAdapterResponse(statusCode: 200)) {
        self.response = response
    }

    func execute(_ request: BackendAdapterRequest) async throws -> BackendAdapterResponse {
        _ = request
        invocationCount += 1
        return response
    }

    func snapshot() async -> BackendAdapterSnapshot {
        BackendAdapterSnapshot(
            mode: .mock,
            invocationCount: invocationCount,
            networkRequestCount: 0
        )
    }
}

struct VoiceAdapterSnapshot: Equatable, Sendable {
    let mode: HostAdapterMode
    let isConnected: Bool
    let connectCallCount: Int
    let sendCallCount: Int
    let disconnectCallCount: Int
    let networkConnectionCount: Int
}

protocol VoiceAdapter: VoiceWebSocketClient {
    func connect() async throws
    func snapshot() async -> VoiceAdapterSnapshot
}

actor EmptyVoiceAdapter: VoiceAdapter {
    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>

    init() {
        lifecycleEvents = AsyncStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func connect() async throws {
        throw HostAdapterError.unavailable
    }

    func connect(url: URL, token: String, deviceID: String) async throws {
        _ = url
        _ = token
        _ = deviceID
        try await connect()
    }

    func send(_ event: VoiceEvent) async throws {
        _ = event
        throw HostAdapterError.unavailable
    }

    func ping() async throws {
        throw HostAdapterError.unavailable
    }

    func disconnect() async {}

    func isConnected() async -> Bool { false }

    func snapshot() async -> VoiceAdapterSnapshot {
        VoiceAdapterSnapshot(
            mode: .empty,
            isConnected: false,
            connectCallCount: 0,
            sendCallCount: 0,
            disconnectCallCount: 0,
            networkConnectionCount: 0
        )
    }
}

actor MockVoiceAdapter: VoiceAdapter {
    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>

    private nonisolated let client: MockWebSocketClient
    private var connected = false
    private var connectCallCount = 0
    private var sendCallCount = 0
    private var disconnectCallCount = 0

    init(client: MockWebSocketClient = MockWebSocketClient()) {
        self.client = client
        lifecycleEvents = client.lifecycleEvents
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> {
        client.makeEventStream()
    }

    func connect() async throws {
        connectCallCount += 1
        try await client.connect(
            url: URL(fileURLWithPath: "/"),
            token: "",
            deviceID: ""
        )
        connected = true
    }

    func connect(url: URL, token: String, deviceID: String) async throws {
        _ = url
        _ = token
        _ = deviceID
        try await connect()
    }

    func send(_ event: VoiceEvent) async throws {
        guard connected else { throw HostAdapterError.notConnected }
        try await client.send(event)
        sendCallCount += 1
    }

    func ping() async throws {
        guard connected else { throw HostAdapterError.notConnected }
        try await client.ping()
    }

    func disconnect() async {
        disconnectCallCount += 1
        connected = false
        await client.disconnect()
    }

    func isConnected() async -> Bool {
        let clientConnected = await client.isConnected()
        return connected && clientConnected
    }

    func snapshot() async -> VoiceAdapterSnapshot {
        let clientConnected = await client.isConnected()
        VoiceAdapterSnapshot(
            mode: .mock,
            isConnected: connected && clientConnected,
            connectCallCount: connectCallCount,
            sendCallCount: sendCallCount,
            disconnectCallCount: disconnectCallCount,
            networkConnectionCount: 0
        )
    }
}

protocol CredentialProviderAdapter: CredentialProviding {}

extension EmptyCredentialProvider: CredentialProviderAdapter {}
extension MockCredentialProvider: CredentialProviderAdapter {}

protocol DeviceBindingProviderAdapter: DeviceBindingProviding {}

extension EmptyDeviceBindingProvider: DeviceBindingProviderAdapter {}
extension MockDeviceBindingProvider: DeviceBindingProviderAdapter {}

struct HostAdapterDependencies: Sendable {
    let mode: HostAdapterMode
    let backend: any BackendAdapter
    let voice: any VoiceAdapter
    let credentials: any CredentialProviderAdapter
    let deviceBinding: any DeviceBindingProviderAdapter

    init(
        mode: HostAdapterMode = .empty,
        backend: any BackendAdapter = EmptyBackendAdapter(),
        voice: any VoiceAdapter = EmptyVoiceAdapter(),
        credentials: any CredentialProviderAdapter = EmptyCredentialProvider(),
        deviceBinding: any DeviceBindingProviderAdapter = EmptyDeviceBindingProvider()
    ) {
        self.mode = mode
        self.backend = backend
        self.voice = voice
        self.credentials = credentials
        self.deviceBinding = deviceBinding
    }

    static var empty: HostAdapterDependencies {
        HostAdapterDependencies()
    }

    static var mock: HostAdapterDependencies {
        HostAdapterDependencies(
            mode: .mock,
            backend: MockBackendAdapter(),
            voice: MockVoiceAdapter(),
            credentials: MockCredentialProvider(
                credentials: AuthCredentials(accessToken: "mock", refreshToken: nil)
            ),
            deviceBinding: MockDeviceBindingProvider(
                state: .bound(deviceID: "mock-device")
            )
        )
    }
}
