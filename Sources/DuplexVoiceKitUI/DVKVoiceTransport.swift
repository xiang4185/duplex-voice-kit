import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DuplexVoiceKit

/// Neutral lifecycle events for the companion voice transport.
public enum DVKVoiceTransportLifecycleEvent: Equatable, Sendable {
    case connecting
    case connected
    case disconnected(DVKVoiceTransportDisconnectInfo)
    case failed(DVKVoiceTransportDisconnectInfo)
}

public struct DVKVoiceTransportDisconnectInfo: Error, Equatable, Sendable {
    public let closeCode: Int?
    public let recoverable: Bool
    public let errorCategory: String
    public let reasonCategory: String

    public init(closeCode: Int?, recoverable: Bool, errorCategory: String, reasonCategory: String) {
        self.closeCode = closeCode
        self.recoverable = recoverable
        self.errorCategory = errorCategory
        self.reasonCategory = reasonCategory
    }
}

/// Classifies transport failures into neutral categories used by the session
/// controller to decide between reconnect, explicit failure, or client close.
public enum DVKVoiceTransportErrorClassifier {
    public static func classify(
        error: Error?,
        closeCode: Int?,
        httpStatus: Int? = nil,
        intentional: Bool = false
    ) -> DVKVoiceTransportDisconnectInfo {
        if intentional {
            return info(closeCode, false, "cancelled", "client_closed")
        }
        if httpStatus == 401 || httpStatus == 403 {
            return info(closeCode, false, "unauthorized", "http_unauthorized")
        }
        if closeCode == 1006 {
            return info(closeCode, true, "connection_lost", "abnormal_close")
        }
        if let closeCode, closeCode == 1000 || closeCode == 1001 {
            return info(closeCode, false, "server_closed", "normal_close")
        }
        guard let error else {
            return info(closeCode, true, "connection_lost", "transport_closed")
        }
        if error is DecodingError {
            return info(closeCode, false, "protocol_error", "invalid_server_event")
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorUserAuthenticationRequired:
                return info(closeCode, false, "unauthorized", "authentication_required")
            case NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorSecureConnectionFailed,
                 NSURLErrorClientCertificateRejected:
                return info(closeCode, false, "tls_failed", "certificate_or_tls")
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return info(closeCode, true, "network_unavailable", "network_transport")
            case NSURLErrorTimedOut:
                return info(closeCode, true, "timed_out", "transport_timeout")
            case NSURLErrorCancelled:
                return info(closeCode, false, "cancelled", "request_cancelled")
            case NSURLErrorBadServerResponse:
                return info(
                    closeCode,
                    httpStatus == nil,
                    httpStatus == nil ? "protocol_error" : "server_closed",
                    "bad_server_response"
                )
            default:
                break
            }
        }
        return info(closeCode, true, "unknown", "unclassified_transport_error")
    }

    private static func info(
        _ closeCode: Int?,
        _ recoverable: Bool,
        _ errorCategory: String,
        _ reasonCategory: String
    ) -> DVKVoiceTransportDisconnectInfo {
        DVKVoiceTransportDisconnectInfo(
            closeCode: closeCode,
            recoverable: recoverable,
            errorCategory: errorCategory,
            reasonCategory: reasonCategory
        )
    }
}

/// Credentials injected at construction time only; never stored or committed.
public struct DVKVoiceCredentials: Sendable {
    public let url: URL
    public let token: String
    public let deviceID: String

    public init(url: URL, token: String, deviceID: String) {
        self.url = url
        self.token = token
        self.deviceID = deviceID
    }
}

/// Companion voice transports extend DVKTransport with lifecycle observation
/// and an explicit connectivity probe used by the session orchestration.
public protocol DVKCompanionVoiceTransport: DVKTransport {
    var lifecycleEvents: AsyncStream<DVKVoiceTransportLifecycleEvent> { get }
    func isConnected() async -> Bool
}

/// Broadcasts inbound protocol events to multiple async stream consumers.
public final class DVKVoiceEventBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let bufferLimit: Int
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    public init(bufferLimit: Int) {
        self.bufferLimit = bufferLimit
    }

    public func makeStream() -> AsyncStream<Element> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(bufferLimit)) { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            lock.lock()
            continuations[identifier] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(identifier)
            }
        }
    }

    public func yield(_ value: Element) {
        lock.lock()
        let active = Array(continuations.values)
        lock.unlock()
        for continuation in active {
            continuation.yield(value)
        }
    }

    private func removeContinuation(_ identifier: UUID) {
        lock.lock()
        continuations.removeValue(forKey: identifier)
        lock.unlock()
    }
}

/// URLSession WebSocket transport conforming to DVKTransport.
///
/// The handshake carries the Bearer token, X-Device-ID and the protocol version
/// header. Actual URL, token and device identifier are injected at construction
/// time only. URLSessionWebSocketTask is Darwin-only, so this transport exists
/// only on Apple platforms.
#if canImport(Darwin)
public actor DVKVoiceWebSocketTransport: DVKCompanionVoiceTransport {
    public static let handshakeTimeoutSeconds: TimeInterval = 10
    public static let resourceTimeoutSeconds: TimeInterval = 86_400
    /// Mirrors the public protocol version used by DVKProtocolCodec.
    public static let protocolVersion = "0.2"

    nonisolated public let lifecycleEvents: AsyncStream<DVKVoiceTransportLifecycleEvent>
    private nonisolated let eventBroadcaster = DVKVoiceEventBroadcaster<DVKInboundEvent>(bufferLimit: 256)
    private let lifecycleContinuation: AsyncStream<DVKVoiceTransportLifecycleEvent>.Continuation
    private let credentials: DVKVoiceCredentials
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connectionGeneration: UUID?
    private var intentionalDisconnect = false

    /// Builds the handshake URLRequest with the frozen neutral headers. Exposed
    /// internally so tests can verify the contract without a live socket.
    static func makeHandshakeRequest(credentials: DVKVoiceCredentials) -> URLRequest {
        var request = URLRequest(url: credentials.url)
        request.timeoutInterval = handshakeTimeoutSeconds
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.deviceID, forHTTPHeaderField: "X-Device-ID")
        request.setValue(protocolVersion, forHTTPHeaderField: "X-Protocol-Version")
        return request
    }

    public init(credentials: DVKVoiceCredentials, session: URLSession? = nil) {
        let lifecyclePair = AsyncStream<DVKVoiceTransportLifecycleEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        lifecycleEvents = lifecyclePair.stream
        lifecycleContinuation = lifecyclePair.continuation
        self.credentials = credentials
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.handshakeTimeoutSeconds
            configuration.timeoutIntervalForResource = Self.resourceTimeoutSeconds
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    nonisolated public func events() -> AsyncStream<DVKInboundEvent> {
        eventBroadcaster.makeStream()
    }

    public func connect() async throws {
        await disconnect(notify: false)
        intentionalDisconnect = false
        lifecycleContinuation.yield(.connecting)

        var request = URLRequest(url: credentials.url)
        request.timeoutInterval = Self.handshakeTimeoutSeconds
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.deviceID, forHTTPHeaderField: "X-Device-ID")
        request.setValue(Self.protocolVersion, forHTTPHeaderField: "X-Protocol-Version")

        let generation = UUID()
        connectionGeneration = generation
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        do {
            try await ping(task)
        } catch {
            let info = disconnectInfo(error: error, task: task, intentional: false)
            lifecycleContinuation.yield(.failed(info))
            task.cancel(with: .goingAway, reason: nil)
            self.task = nil
            connectionGeneration = nil
            throw info
        }

        guard connectionGeneration == generation, self.task === task else {
            throw DVKVoiceTransportErrorClassifier.classify(
                error: URLError(.cancelled),
                closeCode: nil,
                intentional: true
            )
        }
        lifecycleContinuation.yield(.connected)
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: task, generation: generation)
        }
    }

    public func send(_ message: DVKOutboundMessage) async throws {
        guard let task, connectionGeneration != nil else {
            throw DVKVoiceTransportDisconnectInfo(
                closeCode: nil,
                recoverable: true,
                errorCategory: "connection_lost",
                reasonCategory: "transport_closed"
            )
        }
        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DVKVoiceTransportDisconnectInfo(
                closeCode: nil,
                recoverable: false,
                errorCategory: "protocol_error",
                reasonCategory: "event_encoding_failed"
            )
        }
        try await task.send(.string(text))
    }

    public func ping() async throws {
        guard let task, connectionGeneration != nil else {
            throw DVKVoiceTransportDisconnectInfo(
                closeCode: nil,
                recoverable: true,
                errorCategory: "connection_lost",
                reasonCategory: "transport_closed"
            )
        }
        try await ping(task)
    }

    public func disconnect() async {
        await disconnect(notify: true)
    }

    public func isConnected() async -> Bool {
        task != nil && connectionGeneration != nil
    }

    private func disconnect(notify: Bool) async {
        intentionalDisconnect = true
        let activeTask = task
        connectionGeneration = nil
        task = nil
        receiveTask?.cancel()
        receiveTask = nil
        activeTask?.cancel(with: .normalClosure, reason: nil)
        if notify, activeTask != nil {
            let info = DVKVoiceTransportErrorClassifier.classify(
                error: URLError(.cancelled),
                closeCode: 1000,
                intentional: true
            )
            lifecycleContinuation.yield(.disconnected(info))
        }
    }

    private func ping(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask, generation: UUID) async {
        while !Task.isCancelled, connectionGeneration == generation {
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: continue
                }
                let event = try JSONDecoder().decode(DVKInboundEvent.self, from: data)
                eventBroadcaster.yield(event)
            } catch {
                guard connectionGeneration == generation else { return }
                let info = disconnectInfo(
                    error: error,
                    task: task,
                    intentional: intentionalDisconnect || Task.isCancelled
                )
                connectionGeneration = nil
                self.task = nil
                receiveTask = nil
                lifecycleContinuation.yield(.disconnected(info))
                return
            }
        }
    }

    private func disconnectInfo(
        error: Error?,
        task: URLSessionWebSocketTask,
        intentional: Bool
    ) -> DVKVoiceTransportDisconnectInfo {
        let rawCloseCode = task.closeCode.rawValue
        let closeCode = rawCloseCode == 0 ? nil : rawCloseCode
        let status = (task.response as? HTTPURLResponse)?.statusCode
        return DVKVoiceTransportErrorClassifier.classify(
            error: error,
            closeCode: closeCode,
            httpStatus: status,
            intentional: intentional
        )
    }
}
#endif

/// Deterministic mock transport for public demo mode. It never touches the
/// network and scripts the same lifecycle the live gateway provides.
public actor DVKVoiceMockTransport: DVKCompanionVoiceTransport {
    nonisolated public let lifecycleEvents: AsyncStream<DVKVoiceTransportLifecycleEvent>
    private nonisolated let eventBroadcaster = DVKVoiceEventBroadcaster<DVKInboundEvent>(bufferLimit: 256)
    private let lifecycleContinuation: AsyncStream<DVKVoiceTransportLifecycleEvent>.Continuation
    private var serverSequence = 0
    private var connected = false

    public init() {
        let lifecyclePair = AsyncStream<DVKVoiceTransportLifecycleEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        lifecycleEvents = lifecyclePair.stream
        lifecycleContinuation = lifecyclePair.continuation
    }

    nonisolated public func events() -> AsyncStream<DVKInboundEvent> {
        eventBroadcaster.makeStream()
    }

    public func connect() async throws {
        lifecycleContinuation.yield(.connecting)
        connected = true
        lifecycleContinuation.yield(.connected)
    }

    public func send(_ message: DVKOutboundMessage) async throws {
        guard connected else {
            throw DVKVoiceTransportDisconnectInfo(
                closeCode: nil,
                recoverable: true,
                errorCategory: "connection_lost",
                reasonCategory: "transport_closed"
            )
        }
        serverSequence += 1
        let responseType: String
        var payload: [String: DVKJSONValue] = [:]
        switch message.type {
        case "session.start": responseType = "session.ready"
        case "session.resume": responseType = "session.resumed"
        case "audio.commit": responseType = "thinking.started"
        case "interrupt": responseType = "interrupted"; payload = ["success": .bool(true)]
        case "session.end": responseType = "session.closed"
        case "ping": responseType = "pong"
        default: responseType = "server.state"
        }
        eventBroadcaster.yield(DVKInboundEvent(
            version: message.version,
            eventID: UUID().uuidString,
            traceID: message.traceID,
            sessionID: message.sessionID,
            sequence: serverSequence,
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
            type: responseType,
            payload: payload
        ))
    }

    public func ping() async throws {
        guard connected else {
            throw DVKVoiceTransportDisconnectInfo(
                closeCode: nil,
                recoverable: true,
                errorCategory: "connection_lost",
                reasonCategory: "transport_closed"
            )
        }
    }

    public func disconnect() async {
        guard connected else { return }
        connected = false
        lifecycleContinuation.yield(.disconnected(
            DVKVoiceTransportErrorClassifier.classify(
                error: URLError(.cancelled),
                closeCode: 1000,
                intentional: true
            )
        ))
    }

    public func isConnected() async -> Bool { connected }
}

/// Creates live or mock transports for the session controller.
public struct DVKVoiceTransportFactory: DVKTransportFactory {
    public let credentials: DVKVoiceCredentials
    public let useMock: Bool

    public init(credentials: DVKVoiceCredentials, useMock: Bool = false) {
        self.credentials = credentials
        self.useMock = useMock
    }

    public func makeTransport() -> any DVKTransport {
        makeCompanionTransport()
    }

    public func makeCompanionTransport() -> any DVKCompanionVoiceTransport {
        #if canImport(Darwin)
        if useMock { return DVKVoiceMockTransport() }
        return DVKVoiceWebSocketTransport(credentials: credentials)
        #else
        // URLSessionWebSocketTask is Darwin-only; non-Apple builds always use
        // the deterministic mock transport so the package compiles and tests
        // stay hermetic.
        return DVKVoiceMockTransport()
        #endif
    }
}
