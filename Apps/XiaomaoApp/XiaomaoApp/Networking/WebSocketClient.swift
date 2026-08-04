import Foundation

final class BoundedAsyncStreamBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let bufferLimit: Int
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    init(bufferLimit: Int) {
        self.bufferLimit = bufferLimit
    }

    func makeStream() -> AsyncStream<Element> {
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

    func yield(_ value: Element) {
        lock.lock()
        let activeContinuations = Array(continuations.values)
        lock.unlock()
        for continuation in activeContinuations {
            continuation.yield(value)
        }
    }

    private func removeContinuation(_ identifier: UUID) {
        lock.lock()
        continuations.removeValue(forKey: identifier)
        lock.unlock()
    }
}

enum VoiceWebSocketEnvelope {
    static func message(for event: VoiceEvent) throws -> URLSessionWebSocketTask.Message {
        let data = try JSONEncoder().encode(event)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppError.protocolError("event_encoding_failed")
        }
        return .string(text)
    }
}

protocol VoiceWebSocketClient: AnyObject, Sendable {
    func makeEventStream() -> AsyncStream<VoiceEvent>
    var lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent> { get }
    func connect(url: URL, token: String, deviceID: String) async throws
    func send(_ event: VoiceEvent) async throws
    func ping() async throws
    func disconnect() async
    func isConnected() async -> Bool
}

enum VoiceWebSocketConfiguration {
    static let handshakeTimeoutSeconds: TimeInterval = 10
    static let resourceTimeoutSeconds: TimeInterval = 86_400

    static func makeURLSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = handshakeTimeoutSeconds
        configuration.timeoutIntervalForResource = resourceTimeoutSeconds
        configuration.waitsForConnectivity = false
        return configuration
    }
}

actor URLSessionVoiceWebSocketClient: VoiceWebSocketClient {

    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>

    private nonisolated let eventBroadcaster = BoundedAsyncStreamBroadcaster<VoiceEvent>(bufferLimit: 256)
    private let lifecycleContinuation: AsyncStream<VoiceWebSocketLifecycleEvent>.Continuation
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connectionGeneration: UUID?
    private var intentionalDisconnect = false

    init(session: URLSession? = nil) {
        let lifecyclePair = AsyncStream<VoiceWebSocketLifecycleEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        lifecycleEvents = lifecyclePair.stream
        lifecycleContinuation = lifecyclePair.continuation
        if let session {
            self.session = session
        } else {
            self.session = URLSession(
                configuration: VoiceWebSocketConfiguration.makeURLSessionConfiguration()
            )
        }
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> {
        eventBroadcaster.makeStream()
    }

    func connect(url: URL, token: String, deviceID: String) async throws {
        await disconnect(notify: false)
        intentionalDisconnect = false
        lifecycleContinuation.yield(.connecting)

        var request = URLRequest(url: url)
        request.timeoutInterval = VoiceWebSocketConfiguration.handshakeTimeoutSeconds
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        request.setValue(VoiceEvent.protocolVersion, forHTTPHeaderField: "X-Protocol-Version")

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
            let info = VoiceWebSocketErrorClassifier.classify(
                error: URLError(.cancelled),
                closeCode: nil,
                intentional: true
            )
            throw info
        }
        lifecycleContinuation.yield(.connected)
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: task, generation: generation)
        }
    }

    func send(_ event: VoiceEvent) async throws {
        guard let task, connectionGeneration != nil else { throw AppError.networkUnavailable }
        try await task.send(VoiceWebSocketEnvelope.message(for: event))
    }

    func ping() async throws {
        guard let task, connectionGeneration != nil else { throw AppError.networkUnavailable }
        try await ping(task)
    }

    func disconnect() async {
        await disconnect(notify: true)
    }

    func isConnected() async -> Bool {
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
            let info = VoiceWebSocketErrorClassifier.classify(
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
                eventBroadcaster.yield(try JSONDecoder().decode(VoiceEvent.self, from: data))
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
    ) -> VoiceWebSocketDisconnectInfo {
        let rawCloseCode = task.closeCode.rawValue
        let closeCode = rawCloseCode == 0 ? nil : rawCloseCode
        let status = (task.response as? HTTPURLResponse)?.statusCode
        return VoiceWebSocketErrorClassifier.classify(
            error: error,
            closeCode: closeCode,
            httpStatus: status,
            intentional: intentional
        )
    }
}

actor MockWebSocketClient: VoiceWebSocketClient {
    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>
    private nonisolated let eventBroadcaster = BoundedAsyncStreamBroadcaster<VoiceEvent>(bufferLimit: 256)
    private let lifecycleContinuation: AsyncStream<VoiceWebSocketLifecycleEvent>.Continuation
    private var serverSequence = 0
    private var connected = false

    init() {
        let lifecyclePair = AsyncStream<VoiceWebSocketLifecycleEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        lifecycleEvents = lifecyclePair.stream
        lifecycleContinuation = lifecyclePair.continuation
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> {
        eventBroadcaster.makeStream()
    }

    func connect(url: URL, token: String, deviceID: String) async throws {
        _ = url
        _ = token
        _ = deviceID
        lifecycleContinuation.yield(.connecting)
        connected = true
        lifecycleContinuation.yield(.connected)
    }

    func send(_ event: VoiceEvent) async throws {
        guard connected else { throw AppError.networkUnavailable }
        serverSequence += 1
        let responseType: VoiceEventType
        switch event.type {
        case .sessionStart: responseType = .sessionReady
        case .sessionResume: responseType = .sessionResumed
        case .audioCommit: responseType = .thinkingStarted
        case .interrupt: responseType = .interrupted
        case .sessionEnd: responseType = .sessionClosed
        case .ping: responseType = .pong
        default: responseType = .serverState
        }
        eventBroadcaster.yield(VoiceEvent(
            version: VoiceEvent.protocolVersion,
            eventID: UUID().uuidString,
            traceID: event.traceID,
            sessionID: event.sessionID,
            sequence: serverSequence,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: responseType,
            payload: responseType == .interrupted ? ["success": .bool(true)] : [:]
        ))
    }

    func ping() async throws {
        guard connected else { throw AppError.networkUnavailable }
    }

    func disconnect() async {
        guard connected else { return }
        connected = false
        lifecycleContinuation.yield(.disconnected(
            VoiceWebSocketErrorClassifier.classify(
                error: URLError(.cancelled),
                closeCode: 1000,
                intentional: true
            )
        ))
    }

    func isConnected() async -> Bool { connected }
}
