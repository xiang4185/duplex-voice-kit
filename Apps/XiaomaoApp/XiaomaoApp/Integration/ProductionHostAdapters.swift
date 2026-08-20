import Foundation

private enum ProductionHostAdapterValidation {
    static func remoteURL(_ url: URL?, scheme: String) -> URL? {
        guard let url,
              url.scheme?.lowercased() == scheme,
              let host = url.host?.lowercased(),
              !host.isEmpty,
              host != "localhost",
              host != "127.0.0.1",
              host != "::1",
              !host.hasSuffix(".localhost") else {
            return nil
        }
        return url
    }

    static func relativeURL(baseURL: URL, route: String) -> URL? {
        let trimmed = route.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("//"),
              !trimmed.contains("://"),
              !trimmed.split(separator: "/").contains("..") else {
            return nil
        }
        let normalized = trimmed.drop(while: { $0 == "/" })
        guard !normalized.isEmpty else { return nil }
        return baseURL.appending(path: String(normalized))
    }

    static func boundDeviceID(from state: DeviceBindingState) -> String? {
        guard case .bound(let deviceID) = state else { return nil }
        let normalized = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

actor ProductionBackendAdapter: BackendAdapter {
    private static let allowedServerErrorCodes: Set<String> = [
        "session_mismatch",
        "invalid_session_id",
        "idempotency_conflict",
        "invalid_xiaomao_mode",
        "invalid_participant",
        "participant_already_completed",
        "turn_not_found",
        "invalid_request",
        "not_found",
        "forbidden",
        "not_bound",
        "ledger_limit_exceeded",
        "invalid_entry_type",
        "invalid_amount",
        "invalid_status",
        "undo_expired",
        "undo_conflict",
        "invalid_code",
        "expired_code",
        "already_bound",
        "code_already_used",
        "cannot_bind_self",
        "media_not_found",
        "invalid_media",
        "invalid_media_id",
        "media_too_large",
        "unsupported_media_type",
        "media_type_mismatch",
        "invalid_media_dimensions",
        "invalid_avatar",
        "avatar_too_large",
        "avatar_type_mismatch"
    ]

    private struct ServerErrorResponse: Decodable {
        let error: String
    }

    private let baseURL: URL
    private let credentials: any CredentialProviderAdapter
    private let deviceBinding: any DeviceBindingProviderAdapter
    private let session: URLSession
    private var invocationCount = 0
    private var networkRequestCount = 0

    init(
        baseURL: URL,
        credentials: any CredentialProviderAdapter,
        deviceBinding: any DeviceBindingProviderAdapter,
        session: URLSession = .shared
    ) throws {
        guard let validatedURL = ProductionHostAdapterValidation.remoteURL(baseURL, scheme: "https") else {
            throw HostAdapterError.invalidConfiguration
        }
        self.baseURL = validatedURL
        self.credentials = credentials
        self.deviceBinding = deviceBinding
        self.session = session
    }

    func execute(_ request: BackendAdapterRequest) async throws -> BackendAdapterResponse {
        invocationCount += 1
        guard let url = ProductionHostAdapterValidation.relativeURL(
            baseURL: baseURL,
            route: request.route
        ) else {
            throw HostAdapterError.invalidConfiguration
        }
        guard let credential = try await credentials.obtainCredentials(),
              credential.hasAccessToken else {
            throw AppError.unauthorized
        }
        let bindingState = await deviceBinding.currentState()
        guard let deviceID = ProductionHostAdapterValidation.boundDeviceID(from: bindingState) else {
            throw AppError.unauthorized
        }

        var bodyObject: [String: Any]
        if request.payload.isEmpty {
            bodyObject = [:]
        } else {
            guard let decoded = try? JSONSerialization.jsonObject(with: request.payload),
                  let object = decoded as? [String: Any] else {
                throw AppError.protocolError("invalid_request")
            }
            bodyObject = object
        }
        bodyObject["device_id"] = deviceID
        guard JSONSerialization.isValidJSONObject(bodyObject),
              let body = try? JSONSerialization.data(withJSONObject: bodyObject) else {
            throw AppError.protocolError("invalid_request")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        urlRequest.httpBody = body
        networkRequestCount += 1

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw AppError.networkUnavailable
            }
            if http.statusCode == 401 { throw AppError.unauthorized }
            guard 200..<300 ~= http.statusCode else {
                let decoded = try? JSONDecoder().decode(ServerErrorResponse.self, from: data)
                let safeCode = decoded.flatMap {
                    Self.allowedServerErrorCodes.contains($0.error) ? $0.error : nil
                }
                throw AppError.server(safeCode ?? "http_\(http.statusCode)")
            }
            return BackendAdapterResponse(statusCode: http.statusCode, payload: data)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.networkUnavailable
        }
    }

    func snapshot() async -> BackendAdapterSnapshot {
        BackendAdapterSnapshot(
            mode: .production,
            invocationCount: invocationCount,
            networkRequestCount: networkRequestCount
        )
    }
}

actor ProductionVoiceAdapter: VoiceAdapter {
    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>

    private let url: URL
    private let credentials: any CredentialProviderAdapter
    private let deviceBinding: any DeviceBindingProviderAdapter
    private nonisolated let client: any VoiceWebSocketClient
    private var connectCallCount = 0
    private var sendCallCount = 0
    private var disconnectCallCount = 0
    private var networkConnectionCount = 0

    init(
        url: URL,
        credentials: any CredentialProviderAdapter,
        deviceBinding: any DeviceBindingProviderAdapter,
        client: any VoiceWebSocketClient = URLSessionVoiceWebSocketClient()
    ) throws {
        guard let validatedURL = ProductionHostAdapterValidation.remoteURL(url, scheme: "wss") else {
            throw HostAdapterError.invalidConfiguration
        }
        self.url = validatedURL
        self.credentials = credentials
        self.deviceBinding = deviceBinding
        self.client = client
        lifecycleEvents = client.lifecycleEvents
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> {
        client.makeEventStream()
    }

    func connect() async throws {
        connectCallCount += 1
        guard let credential = try await credentials.obtainCredentials(),
              credential.hasAccessToken else {
            throw AppError.unauthorized
        }
        let bindingState = await deviceBinding.currentState()
        guard let deviceID = ProductionHostAdapterValidation.boundDeviceID(from: bindingState) else {
            throw AppError.unauthorized
        }
        networkConnectionCount += 1
        try await client.connect(
            url: url,
            token: credential.accessToken,
            deviceID: deviceID
        )
    }

    func connect(url: URL, token: String, deviceID: String) async throws {
        _ = url
        _ = token
        _ = deviceID
        try await connect()
    }

    func send(_ event: VoiceEvent) async throws {
        guard await client.isConnected() else { throw HostAdapterError.notConnected }
        try await client.send(event)
        sendCallCount += 1
    }

    func ping() async throws {
        guard await client.isConnected() else { throw HostAdapterError.notConnected }
        try await client.ping()
    }

    func disconnect() async {
        disconnectCallCount += 1
        await client.disconnect()
    }

    func isConnected() async -> Bool {
        await client.isConnected()
    }

    func snapshot() async -> VoiceAdapterSnapshot {
        let connected = await client.isConnected()
        return VoiceAdapterSnapshot(
            mode: .production,
            isConnected: connected,
            connectCallCount: connectCallCount,
            sendCallCount: sendCallCount,
            disconnectCallCount: disconnectCallCount,
            networkConnectionCount: networkConnectionCount
        )
    }
}

struct KeychainCredentialProviderAdapter: CredentialProviderAdapter {
    private let tokenStore: any AuthTokenStoring

    init(tokenStore: any AuthTokenStoring = KeychainAuthTokenStore()) {
        self.tokenStore = tokenStore
    }

    func obtainCredentials() async throws -> AuthCredentials? {
        guard let token = tokenStore.load().map(RuntimeCredentialNormalizer.token),
              !token.isEmpty else {
            return nil
        }
        guard !token.isEmpty else { return nil }
        return AuthCredentials(accessToken: token, refreshToken: nil)
    }

    func refreshCredentials(_ credentials: AuthCredentials) async throws -> AuthCredentials? {
        _ = credentials
        throw HostAdapterError.unsupportedOperation
    }

    func clearCredentials() async throws {
        try tokenStore.clear()
    }
}

struct InjectedDeviceBindingProviderAdapter: DeviceBindingProviderAdapter {
    private let deviceID: String

    init(deviceID: String) {
        self.deviceID = RuntimeCredentialNormalizer.deviceID(deviceID)
    }

    func currentState() async -> DeviceBindingState {
        deviceID.isEmpty ? .unbound : .bound(deviceID: deviceID)
    }

    func bind() async throws -> DeviceBindingState {
        throw HostAdapterError.unsupportedOperation
    }

    func unbind() async throws -> DeviceBindingState {
        throw HostAdapterError.unsupportedOperation
    }
}

enum HostAdapterFactory {
    static func make(
        mode: HostAdapterMode,
        apiBaseURL: URL?,
        voiceWebSocketURL: URL?,
        tokenStore: any AuthTokenStoring,
        deviceID: String,
        backendSession: URLSession = .shared,
        voiceClient: (any VoiceWebSocketClient)? = nil
    ) -> HostAdapterDependencies {
        switch mode {
        case .empty:
            return .empty
        case .mock:
            return .mock
        case .production:
            let credentials = KeychainCredentialProviderAdapter(tokenStore: tokenStore)
            let deviceBinding = InjectedDeviceBindingProviderAdapter(deviceID: deviceID)
            guard let apiBaseURL,
                  let voiceWebSocketURL,
                  !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let backend = try? ProductionBackendAdapter(
                    baseURL: apiBaseURL,
                    credentials: credentials,
                    deviceBinding: deviceBinding,
                    session: backendSession
                  ),
                  let voice = try? ProductionVoiceAdapter(
                    url: voiceWebSocketURL,
                    credentials: credentials,
                    deviceBinding: deviceBinding,
                    client: voiceClient ?? URLSessionVoiceWebSocketClient()
                  ) else {
                return .empty
            }
            return HostAdapterDependencies(
                mode: .production,
                backend: backend,
                voice: voice,
                credentials: credentials,
                deviceBinding: deviceBinding
            )
        }
    }
}
