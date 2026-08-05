import Foundation

enum HostAdapterMode: Equatable, Sendable {
    case empty
    case mock
}

enum HostAdapterError: Error, Equatable, Sendable {
    case unavailable
    case notConnected
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

protocol VoiceAdapter: Sendable {
    func connect() async throws
    func send(_ payload: Data) async throws
    func disconnect() async
    func snapshot() async -> VoiceAdapterSnapshot
}

struct EmptyVoiceAdapter: VoiceAdapter {
    func connect() async throws {
        throw HostAdapterError.unavailable
    }

    func send(_ payload: Data) async throws {
        _ = payload
        throw HostAdapterError.unavailable
    }

    func disconnect() async {}

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
    private var isConnected = false
    private var connectCallCount = 0
    private var sendCallCount = 0
    private var disconnectCallCount = 0

    func connect() async throws {
        connectCallCount += 1
        isConnected = true
    }

    func send(_ payload: Data) async throws {
        _ = payload
        guard isConnected else { throw HostAdapterError.notConnected }
        sendCallCount += 1
    }

    func disconnect() async {
        disconnectCallCount += 1
        isConnected = false
    }

    func snapshot() async -> VoiceAdapterSnapshot {
        VoiceAdapterSnapshot(
            mode: .mock,
            isConnected: isConnected,
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
    let backend: any BackendAdapter
    let voice: any VoiceAdapter
    let credentials: any CredentialProviderAdapter
    let deviceBinding: any DeviceBindingProviderAdapter

    init(
        backend: any BackendAdapter = EmptyBackendAdapter(),
        voice: any VoiceAdapter = EmptyVoiceAdapter(),
        credentials: any CredentialProviderAdapter = EmptyCredentialProvider(),
        deviceBinding: any DeviceBindingProviderAdapter = EmptyDeviceBindingProvider()
    ) {
        self.backend = backend
        self.voice = voice
        self.credentials = credentials
        self.deviceBinding = deviceBinding
    }

    static var empty: HostAdapterDependencies {
        HostAdapterDependencies()
    }
}
