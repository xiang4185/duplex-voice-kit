import Foundation
import DuplexVoiceKit
import DuplexVoiceKitCompanion

/// Neutral names for server-pushed event types. This is a routing taxonomy only:
/// wire decoding stays in DVKInboundEvent and wire encoding stays in
/// DVKAudioUploadPipeline. No second codec exists in this layer.
public enum DVKVoiceServerEvent: String, Sendable {
    case sessionReady = "session.ready"
    case sessionResumed = "session.resumed"
    case sessionClosed = "session.closed"
    case sessionEnded = "session.ended"
    case idleWarning = "server.idle_warning"
    case listeningStarted = "listening.started"
    case listeningStopped = "listening.stopped"
    case thinkingStarted = "thinking.started"
    case transcriptPartial = "transcript.partial"
    case transcriptFinal = "transcript.final"
    case responseStarted = "response.started"
    case responseAudioDelta = "response.audio.delta"
    case responseAudioDone = "response.audio.done"
    case responseTextDelta = "response.text.delta"
    case responseTextDone = "response.text.done"
    case responseCancelled = "response.cancelled"
    case interrupted = "interrupted"
    case degraded = "degraded"
    case error = "error"
    case pong = "pong"
    case serverState = "server.state"
}

public enum DVKVoiceTransportState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case failed
}

/// Redacted audio health mirror. Contains no transcript, token, or raw audio.
public struct DVKCompanionAudioHealth: Sendable, Equatable {
    public let engineRunning: Bool
    public let tapInstalled: Bool
    public let callbackCount: Int
    public let lastCallbackAt: Date?
    public let restartCount: Int
    public let isInterrupted: Bool

    public static let unavailable = DVKCompanionAudioHealth(
        engineRunning: false,
        tapInstalled: false,
        callbackCount: 0,
        lastCallbackAt: nil,
        restartCount: 0,
        isInterrupted: false
    )
}

/// Audio engine injection seam. The production implementation delegates one to
/// one to DVKRealtimeAudioIO; tests inject deterministic doubles. No second
/// audio engine, buffering, queue, or graph state lives here.
public protocol DVKCompanionAudioIO: AnyObject, Sendable {
    var captureGeneration: Int { get }
    var healthSnapshot: DVKCompanionAudioHealth { get }
    func startCapture() throws
    func stopCapture()
    func enqueuePlayback(_ data: Data, responseID: String, chunkIndex: Int)
    func cancelPlayback(responseID: String?)
    func recoverCapture() throws
    func shutdown()
    func setPlaybackAmplitudeSink(_ sink: (any DVKPlaybackAmplitudeSink)?)
}

#if os(iOS)
/// One-to-one delegation to the DVK realtime audio engine. No logic, no state.
final class DVKRealtimeAudioIOAdapter: DVKCompanionAudioIO {
    private let audioIO: DVKRealtimeAudioIO

    init(audioIO: DVKRealtimeAudioIO) {
        self.audioIO = audioIO
    }

    var captureGeneration: Int { audioIO.captureGeneration }
    var healthSnapshot: DVKCompanionAudioHealth {
        let health = audioIO.healthSnapshot
        return DVKCompanionAudioHealth(
            engineRunning: health.captureEngineRunning,
            tapInstalled: health.captureTapInstalled,
            callbackCount: health.captureCallbackCount,
            lastCallbackAt: health.lastCaptureCallbackAt,
            restartCount: health.captureRestartCount,
            isInterrupted: health.isInterrupted
        )
    }
    func startCapture() throws { try audioIO.startCapture() }
    func stopCapture() { audioIO.stopCapture() }
    func enqueuePlayback(_ data: Data, responseID: String, chunkIndex: Int) {
        audioIO.enqueuePlayback(data, responseID: responseID, chunkIndex: chunkIndex)
    }
    func cancelPlayback(responseID: String?) { audioIO.cancelPlayback(responseID: responseID) }
    func recoverCapture() throws { try audioIO.recoverCapture() }
    func shutdown() { audioIO.shutdown() }
    func setPlaybackAmplitudeSink(_ sink: (any DVKPlaybackAmplitudeSink)?) {
        audioIO.setPlaybackAmplitudeSink(sink)
    }
}
#endif

/// Aggregated redacted diagnostics for the companion voice session. No
/// transcript, token, device identifier, or raw audio is included.
public struct DVKCompanionVoiceDiagnostics: Sendable, Equatable {
    public let state: DVKSessionState
    public let transportState: String
    public let sessionHash: String
    public let lastEventType: String
    public let lastEventSequence: Int
    public let reconnectAttempt: Int
    public let audioHealth: DVKCompanionAudioHealth
    public let uploadNextChunkIndex: Int
    public let uploadNextClientSequence: Int
    public let uploadQueueDepth: Int
    public let uploadDroppedStaleGenerationChunks: Int
    public let uploadInputBackpressureCount: Int
    public let uploadSentAudioChunks: Int
    public let generatedAt: Date
}

#if canImport(Combine)
import Combine

/// Mature companion voice session orchestration over the DVK Core.
///
/// This controller only orchestrates the mature application lifecycle. All
/// protocol encoding, sequencing, chunk allocation, audio queueing, VAD,
/// realtime audio IO, and reconnect policy live in the DVK Core
/// (DVKAudioUploadPipeline, DVKResponseFilter, DVKVoiceActivityDetector,
/// DVKRealtimeAudioIO, DVKReconnectPolicy).
@MainActor
public final class DVKCompanionVoiceSessionController: ObservableObject {
    @Published public private(set) var state: DVKSessionState = .idle
    @Published public private(set) var webSocketState: DVKVoiceTransportState = .disconnected
    @Published public private(set) var transcript = ""
    @Published public private(set) var responseText = ""
    @Published public private(set) var errorMessage = ""
    @Published public private(set) var isMuted = false
    @Published public private(set) var reconnectAttempt = 0
    @Published public private(set) var lastCloseCode: Int?
    @Published public private(set) var lastErrorCategory = ""
    @Published public private(set) var lastReasonCategory = ""
    @Published public private(set) var lastServerEventType = ""
    @Published public private(set) var idleWarningRemainingSeconds: Int?
    @Published public private(set) var idleTimeoutEnded = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var playbackAmplitude: Float = 0
    @Published public private(set) var isPlaybackActive = false

    public private(set) var sessionID = ""
    public private(set) var traceID = ""

    private let configuration: DVKRuntimeConfiguration
    private let tokenStore: any DVKTokenStoring
    private let transportFactory: (DVKVoiceCredentials) -> any DVKCompanionVoiceTransport
    private let audioIO: (any DVKCompanionAudioIO)?
    private let reconnectPolicy: DVKReconnectPolicy
    private let protocolReadyTimeout: Duration
    private let captureWatchdogInterval: Duration
    private let captureStallThresholdSeconds: TimeInterval
    private let maximumCaptureRecoveryAttempts: Int
    private let heartbeatInterval: Duration

    private var transport: (any DVKCompanionVoiceTransport)?
    private var pipeline: DVKAudioUploadPipeline?
    private var voiceActivityDetector = DVKVoiceActivityDetector()
    private var responseFilter = DVKResponseFilter()

    private var receiveTask: Task<Void, Never>?
    private var receiveGeneration = 0
    private var lifecycleTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var captureWatchdogTask: Task<Void, Never>?
    private var captureWatchdogStartedAt: Date?
    private var lastObservedCaptureCallbackCount = 0
    private var captureRecoveryAttemptCount = 0
    private var reconnectTask: Task<Void, Never>?
    private var reconnectGeneration: UUID?
    private var lastServerSequence = 0
    private var responseID = ""
    private var interruptedResponseID = ""
    private var interruptedResponseIDs: Set<String> = []
    private var automaticBargeInActive = false
    private var callIsActive = false
    private var suspendedForBackground = false
    private var expectedReadyEvent: DVKVoiceServerEvent?
    private var lastReadyEvent: DVKVoiceServerEvent?
    private var lastServerEventAt: Date?
    private var webSocketConnectedAt: Date?
    private var terminalProtocolErrorCode: String?
    private var terminalLocalAudioFailure = false
    private var amplitudeSink: DVKCompanionAmplitudeSink?

    public init(
        configuration: DVKRuntimeConfiguration,
        tokenStore: any DVKTokenStoring,
        transportFactory: @escaping (DVKVoiceCredentials) -> any DVKCompanionVoiceTransport = { credentials in
            DVKVoiceTransportFactory(credentials: credentials, useMock: false).makeCompanionTransport()
        },
        audioIO: (any DVKCompanionAudioIO)? = nil,
        reconnectPolicy: DVKReconnectPolicy = .realtimeDefault,
        protocolReadyTimeout: Duration = .seconds(8),
        captureWatchdogInterval: Duration = .seconds(1),
        captureStallThreshold: Duration = .seconds(2),
        maximumCaptureRecoveryAttempts: Int = 2,
        heartbeatInterval: Duration = .seconds(20)
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.transportFactory = transportFactory
        self.audioIO = audioIO ?? Self.makeDefaultAudioIO()
        self.reconnectPolicy = reconnectPolicy
        self.protocolReadyTimeout = protocolReadyTimeout
        self.captureWatchdogInterval = captureWatchdogInterval
        self.captureStallThresholdSeconds = Self.timeInterval(captureStallThreshold)
        self.maximumCaptureRecoveryAttempts = max(1, maximumCaptureRecoveryAttempts)
        self.heartbeatInterval = heartbeatInterval

        if let audioIO = self.audioIO {
            let relay = DVKCompanionAmplitudeSink { [weak self] amplitude in
                Task { @MainActor in
                    self?.playbackAmplitude = amplitude
                }
            }
            amplitudeSink = relay
            audioIO.setPlaybackAmplitudeSink(relay)
        }
    }

    private static func makeDefaultAudioIO() -> (any DVKCompanionAudioIO)? {
        #if os(iOS)
        return (try? DVKRealtimeAudioIO(configuration: .realtimeVoice))
            .map(DVKRealtimeAudioIOAdapter.init(audioIO:))
        #else
        return nil
        #endif
    }

    private static func timeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

    // MARK: - Public state gates

    public var hasActiveCall: Bool { callIsActive }

    public var companionVoiceState: DVKCompanionVoiceState {
        switch state {
        case .idle, .failed, .degraded: return .idle
        case .connecting, .reconnecting: return .connecting
        case .ready, .listening: return .listening
        case .endpointing, .processing, .interrupting: return .processing
        case .speaking: return .speaking
        case .closing, .closed: return .ended
        }
    }

    public var canStartVoice: Bool {
        callIsActive && state == .ready && webSocketState == .connected
            && !isRecording && !isMuted
    }

    public var canEndVoice: Bool { callIsActive && state != .idle }

    public var canMute: Bool {
        callIsActive && webSocketState == .connected
            && state != .connecting && state != .closing && state != .closed
    }

    public var canInterrupt: Bool {
        callIsActive && state == .speaking && !responseID.isEmpty
    }

    public var shouldShowReconnect: Bool {
        callIsActive && (state == .failed || state == .closed || state == .reconnecting)
    }

    // MARK: - Public lifecycle

    public func startNewCall() async {
        await tearDownCurrentCall(sendSessionEnd: callIsActive, finalState: nil)
        resetForNewCall()
        guard let credentials = connectionCredentials() else {
            state = .failed
            errorMessage = "Device binding information is incomplete."
            return
        }
        let transport = transportFactory(credentials)
        self.transport = transport
        let pipeline = DVKAudioUploadPipeline(outboundTransport: transport)
        self.pipeline = pipeline
        await pipeline.configure(
            processor: { [weak self] frame in
                await self?.voiceIntents(for: frame) ?? []
            },
            notificationHandler: { [weak self] notification in
                await self?.handleUploadNotification(notification)
            }
        )
        callIsActive = true
        suspendedForBackground = false
        observeLifecycleEvents(of: transport)
        await startReceiveLoop()
        await establishNewSession()
    }

    public func reconnectCurrentCall() {
        guard callIsActive else { return }
        if terminalLocalAudioFailure || state == .closed {
            Task { @MainActor [weak self] in await self?.startNewCall() }
            return
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectGeneration = nil
        beginReconnect(immediate: true)
    }

    public func endCurrentCall() async {
        await tearDownCurrentCall(sendSessionEnd: callIsActive, finalState: .closed)
    }

    public func interrupt() async {
        guard canInterrupt else { return }
        state = .interrupting
        audioIO?.cancelPlayback(responseID: responseID)
        isPlaybackActive = false
        do {
            try await pipeline?.interrupt(responseID: responseID)
        } catch {
            recordSendFailure(error)
        }
    }

    public func setMuted(_ muted: Bool) async {
        guard callIsActive, isMuted != muted else { return }
        isMuted = muted
        if muted {
            await pipeline?.pauseCapture()
            stopContinuousCapture(resetVAD: true)
            guard webSocketState == .connected else { return }
            do {
                try await pipeline?.setMuted(true)
            } catch {
                recordSendFailure(error)
            }
            return
        }
        if webSocketState == .connected {
            do {
                try await pipeline?.setMuted(false)
            } catch {
                recordSendFailure(error)
                return
            }
            await startContinuousCaptureIfPossible()
        } else if lastDisconnectRecoverable,
                  state != .closed,
                  state != .failed,
                  lastReasonCategory != "idle_timeout" {
            reconnectCurrentCall()
        }
    }

    public func commitAudio() async {
        guard callIsActive, isRecording, state == .listening else { return }
        voiceActivityDetector.suspend()
        state = .processing
        do {
            try await pipeline?.commit()
        } catch {
            recordSendFailure(error)
        }
    }

    public func appDidEnterBackground() async {
        guard callIsActive else { return }
        suspendedForBackground = false
    }

    public func appWillEnterForeground() async {
        guard callIsActive else { return }
        suspendedForBackground = false
        if webSocketState != .connected {
            reconnectCurrentCall()
        }
    }

    public var diagnosticsSnapshot: DVKCompanionVoiceDiagnostics {
        let upload = pipeline?.diagnosticsSnapshot
        return DVKCompanionVoiceDiagnostics(
            state: state,
            transportState: webSocketState.rawValue,
            sessionHash: DVKDiagnosticsSnapshot.shortHash(sessionID),
            lastEventType: lastServerEventType,
            lastEventSequence: lastServerSequence,
            reconnectAttempt: reconnectAttempt,
            audioHealth: audioIO?.healthSnapshot ?? .unavailable,
            uploadNextChunkIndex: upload?.nextChunkIndex ?? 0,
            uploadNextClientSequence: upload?.nextClientSequence ?? 0,
            uploadQueueDepth: upload?.queueDepth ?? 0,
            uploadDroppedStaleGenerationChunks: upload?.droppedStaleGenerationChunks ?? 0,
            uploadInputBackpressureCount: upload?.inputBackpressureCount ?? 0,
            uploadSentAudioChunks: upload?.sentAudioChunks ?? 0,
            generatedAt: Date()
        )
    }

    public var redactedDiagnosticsText: String {
        let diagnostics = diagnosticsSnapshot
        return [
            "DuplexVoiceKit Companion voice diagnostics",
            "state=\(diagnostics.state.rawValue)",
            "transport_state=\(diagnostics.transportState)",
            "session_hash=\(diagnostics.sessionHash)",
            "last_event_type=\(diagnostics.lastEventType.isEmpty ? "none" : diagnostics.lastEventType)",
            "last_event_sequence=\(diagnostics.lastEventSequence)",
            "reconnect_attempt=\(diagnostics.reconnectAttempt)",
            "audio_engine_running=\(diagnostics.audioHealth.engineRunning)",
            "audio_tap_installed=\(diagnostics.audioHealth.tapInstalled)",
            "audio_restart_count=\(diagnostics.audioHealth.restartCount)",
            "upload_next_chunk_index=\(diagnostics.uploadNextChunkIndex)",
            "upload_next_client_sequence=\(diagnostics.uploadNextClientSequence)",
            "upload_queue_depth=\(diagnostics.uploadQueueDepth)",
            "upload_dropped_stale_generation_chunks=\(diagnostics.uploadDroppedStaleGenerationChunks)",
            "upload_input_backpressure_count=\(diagnostics.uploadInputBackpressureCount)",
            "upload_sent_audio_chunks=\(diagnostics.uploadSentAudioChunks)"
        ].joined(separator: "\n")
    }

    // Internal-only observability used by unit tests. Never rendered.
    var lastServerSequenceForTesting: Int { lastServerSequence }
    var responseIDForTesting: String { responseID }
    var hasReconnectTaskForTesting: Bool { reconnectTask != nil }
    var hasHeartbeatTaskForTesting: Bool { heartbeatTask != nil }
    var hasCaptureWatchdogTaskForTesting: Bool { captureWatchdogTask != nil }
    var lastReasonCategoryForTesting: String { lastReasonCategory }
    var pipelineDiagnosticsForTesting: DVKAudioUploadDiagnosticsSnapshot? {
        pipeline?.diagnosticsSnapshot
    }
    var responseFilterLastServerSequenceForTesting: Int {
        responseFilter.lastServerSequence
    }
    func setResponseTextForTesting(_ value: String) {
        responseText = value
    }

    // MARK: - Private lifecycle

    private func resetForNewCall() {
        sessionID = UUID().uuidString
        traceID = UUID().uuidString
        lastServerSequence = 0
        responseID = ""
        transcript = ""
        responseText = ""
        errorMessage = ""
        idleWarningRemainingSeconds = nil
        idleTimeoutEnded = false
        isMuted = false
        isRecording = false
        expectedReadyEvent = nil
        lastReadyEvent = nil
        interruptedResponseID = ""
        interruptedResponseIDs.removeAll(keepingCapacity: false)
        automaticBargeInActive = false
        reconnectAttempt = 0
        lastCloseCode = nil
        lastErrorCategory = ""
        lastReasonCategory = ""
        lastServerEventType = ""
        lastServerEventAt = nil
        webSocketState = .disconnected
        state = .idle
        voiceActivityDetector.resetForListening()
        responseFilter.clear()
        terminalProtocolErrorCode = nil
        terminalLocalAudioFailure = false
        isPlaybackActive = false
        playbackAmplitude = 0
        stopCaptureWatchdog()
        audioIO?.cancelPlayback(responseID: nil)
        audioIO?.stopCapture()
    }

    private func connectionCredentials() -> DVKVoiceCredentials? {
        guard configuration.isLive,
              let url = configuration.voiceWebSocketURL,
              let token = tokenStore.load(),
              !token.isEmpty,
              !configuration.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return DVKVoiceCredentials(url: url, token: token, deviceID: configuration.deviceID)
    }

    private func observeLifecycleEvents(of transport: any DVKCompanionVoiceTransport) {
        lifecycleTask?.cancel()
        lifecycleTask = Task { @MainActor [weak self] in
            for await event in transport.lifecycleEvents {
                guard let self else { return }
                await self.handleLifecycleEvent(event)
            }
        }
    }

    private func establishNewSession() async {
        guard let transport, let pipeline else {
            state = .failed
            errorMessage = "Device binding information is incomplete."
            return
        }
        state = .connecting
        expectedReadyEvent = .sessionReady
        lastReadyEvent = nil
        do {
            try await transport.connect()
            markWebSocketConnected()
            try await pipeline.openConnection(sessionID: sessionID, traceID: traceID)
            startHeartbeat()
            try await waitForReady(expected: .sessionReady)
        } catch {
            handleConnectionFailure(error, allowReconnect: true)
        }
    }

    private func beginReconnect(immediate: Bool) {
        guard callIsActive,
              !suspendedForBackground,
              terminalProtocolErrorCode == nil,
              !terminalLocalAudioFailure,
              reconnectTask == nil else { return }
        let generation = UUID()
        reconnectGeneration = generation
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runReconnectLoop(immediate: immediate)
            guard self.reconnectGeneration == generation else { return }
            self.reconnectTask = nil
            self.reconnectGeneration = nil
        }
    }

    private func runReconnectLoop(immediate: Bool) async {
        guard let credentials = connectionCredentials(), let transport, let pipeline else {
            state = .failed
            errorMessage = "Device binding information is incomplete."
            return
        }
        let maximumAttempts = reconnectPolicy.maximumAttempts
        for attempt in 1...max(1, maximumAttempts) {
            guard callIsActive, !suspendedForBackground, !Task.isCancelled else { return }
            reconnectAttempt = attempt
            state = .reconnecting
            if !(immediate && attempt == 1) {
                do { try await Task.sleep(for: reconnectPolicy.delay(for: attempt)) } catch { return }
            }
            guard callIsActive, !Task.isCancelled else { return }
            expectedReadyEvent = .sessionResumed
            lastReadyEvent = nil
            do {
                try await transport.connect()
                markWebSocketConnected()
                try await pipeline.openConnection(
                    sessionID: sessionID,
                    traceID: traceID,
                    resumeFrom: lastServerSequence
                )
                startHeartbeat()
                try await waitForReady(expected: .sessionResumed)
                reconnectAttempt = 0
                errorMessage = ""
                return
            } catch let info as DVKVoiceTransportDisconnectInfo {
                applyDisconnectInfo(info)
                if !info.recoverable {
                    state = .failed
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                lastErrorCategory = "connection_lost"
                lastReasonCategory = "reconnect_attempt_failed"
                lastDisconnectRecoverable = true
            }
        }
        state = .failed
        errorMessage = "The connection failed after the maximum number of attempts."
    }

    private func waitForReady(expected: DVKVoiceServerEvent) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: protocolReadyTimeout)
        while clock.now < deadline {
            guard callIsActive else { throw DVKCompanionVoiceClientError.callEnded }
            if lastReadyEvent == expected, state == .ready { return }
            if state == .failed, !lastDisconnectRecoverable {
                throw DVKVoiceTransportDisconnectInfo(
                    closeCode: lastCloseCode,
                    recoverable: false,
                    errorCategory: lastErrorCategory.isEmpty ? "unknown" : lastErrorCategory,
                    reasonCategory: lastReasonCategory.isEmpty ? "protocol_failed" : lastReasonCategory
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw DVKCompanionVoiceClientError.protocolReadyTimedOut
    }

    private func startReceiveLoop() async {
        await stopReceiveLoop()
        receiveGeneration &+= 1
        let generation = receiveGeneration
        guard let transport else { return }
        let events = transport.events()
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in events {
                guard !Task.isCancelled, self.receiveGeneration == generation else { return }
                await self.handle(event)
            }
        }
    }

    private func stopReceiveLoop() async {
        receiveGeneration &+= 1
        guard let task = receiveTask else { return }
        task.cancel()
        await task.value
        receiveTask = nil
    }

    private func markWebSocketConnected() {
        if webSocketState != .connected {
            webSocketState = .connected
            if webSocketConnectedAt == nil {
                webSocketConnectedAt = Date()
            }
        }
    }

    private func handleLifecycleEvent(_ event: DVKVoiceTransportLifecycleEvent) async {
        switch event {
        case .connecting:
            if webSocketState != .connected {
                webSocketState = .connecting
            }
        case .connected:
            markWebSocketConnected()
        case .disconnected(let info):
            if let transport, await transport.isConnected() { return }
            webSocketState = .disconnected
            await pipeline?.pauseCapture()
            await pipeline?.abortConnection()
            stopContinuousCapture(resetVAD: true)
            applyDisconnectInfo(info)
            guard callIsActive, !suspendedForBackground else { return }
            if info.errorCategory == "cancelled" { return }
            if info.recoverable {
                beginReconnect(immediate: false)
            } else {
                state = info.errorCategory == "server_closed" ? .closed : .failed
            }
        case .failed(let info):
            if let transport, await transport.isConnected() { return }
            webSocketState = .failed
            await pipeline?.pauseCapture()
            await pipeline?.abortConnection()
            stopContinuousCapture(resetVAD: true)
            applyDisconnectInfo(info)
            guard callIsActive, !suspendedForBackground else { return }
            if info.recoverable {
                beginReconnect(immediate: false)
            } else {
                state = .failed
            }
        }
    }

    private var lastDisconnectRecoverable = false

    private func applyDisconnectInfo(_ info: DVKVoiceTransportDisconnectInfo) {
        webSocketConnectedAt = nil
        lastCloseCode = info.closeCode
        if !callIsActive, lastReasonCategory == "idle_timeout" { return }
        lastErrorCategory = info.errorCategory
        lastReasonCategory = info.reasonCategory
        lastDisconnectRecoverable = info.recoverable
        if info.errorCategory != "cancelled" {
            errorMessage = userMessage(for: info)
        }
    }

    private func handleConnectionFailure(_ error: Error, allowReconnect: Bool) {
        if let info = error as? DVKVoiceTransportDisconnectInfo {
            applyDisconnectInfo(info)
            if allowReconnect, info.recoverable {
                beginReconnect(immediate: false)
            } else {
                state = .failed
            }
            return
        }
        if let clientError = error as? DVKCompanionVoiceClientError,
           clientError == .protocolReadyTimedOut {
            lastErrorCategory = "timed_out"
            lastReasonCategory = "session_ready_timeout"
            lastDisconnectRecoverable = true
            errorMessage = "The connection was established, but the server session did not become ready."
            if allowReconnect { beginReconnect(immediate: false) }
            return
        }
        lastErrorCategory = "unknown"
        lastReasonCategory = "connection_failed"
        lastDisconnectRecoverable = true
        errorMessage = "The voice connection failed."
        if allowReconnect { beginReconnect(immediate: false) } else { state = .failed }
    }

    // MARK: - Inbound event routing

    private func handle(_ event: DVKInboundEvent) async {
        guard event.sessionID == sessionID else { return }
        lastServerEventType = event.type
        lastServerEventAt = Date()
        guard event.sequence > lastServerSequence else { return }
        lastServerSequence = event.sequence
        if terminalProtocolErrorCode != nil, event.type != DVKVoiceServerEvent.sessionClosed.rawValue {
            return
        }
        guard let serverEvent = DVKVoiceServerEvent(rawValue: event.type) else { return }

        switch serverEvent {
        case .sessionReady where expectedReadyEvent == .sessionReady:
            state = .ready
            reconnectAttempt = 0
            errorMessage = ""
            await pipeline?.markReady()
            await startContinuousCaptureIfPossible()
            lastReadyEvent = .sessionReady

        case .sessionResumed where expectedReadyEvent == .sessionResumed:
            resetProviderGenerationAfterResume()
            await pipeline?.markReady()
            guard await syncMuteStateAfterResume() else { return }
            state = .ready
            reconnectAttempt = 0
            errorMessage = ""
            if isRecording, let audioIO {
                await pipeline?.activateCaptureGeneration(audioIO.captureGeneration)
            } else {
                await startContinuousCaptureIfPossible()
            }
            lastReadyEvent = .sessionResumed

        case .listeningStarted:
            state = .listening

        case .listeningStopped, .thinkingStarted:
            state = .processing

        case .transcriptPartial, .transcriptFinal:
            transcript = event.payload.string("text") ?? transcript

        case .responseStarted:
            responseID = event.payload.string("response_id") ?? ""
            responseFilter.begin(responseID: responseID, serverSequence: event.sequence)
            automaticBargeInActive = false
            isPlaybackActive = false
            voiceActivityDetector.resetForListening()
            state = .speaking
            await startContinuousCaptureIfPossible()

        case .responseAudioDelta:
            guard let eventResponseID = event.payload.string("response_id") else { return }
            if shouldIgnoreInterruptedResponse(eventResponseID) {
                audioIO?.cancelPlayback(responseID: eventResponseID)
                return
            }
            guard eventResponseID == responseID,
                  let encoded = event.payload.string("audio"),
                  let data = Data(base64Encoded: encoded),
                  responseFilter.acceptAudio(
                    responseID: eventResponseID,
                    serverSequence: event.sequence
                  ) else { return }
            let index = event.payload.int("chunk_index") ?? 0
            audioIO?.enqueuePlayback(data, responseID: eventResponseID, chunkIndex: index)
            isPlaybackActive = true
            state = .speaking

        case .responseAudioDone, .responseCancelled:
            let eventResponseID = event.payload.string("response_id") ?? responseID
            if shouldIgnoreInterruptedResponse(eventResponseID) {
                audioIO?.cancelPlayback(responseID: eventResponseID)
                if responseID == eventResponseID {
                    responseID = ""
                    isPlaybackActive = false
                }
                return
            }
            guard eventResponseID == responseID else { return }
            _ = responseFilter.finish(
                responseID: eventResponseID,
                serverSequence: event.sequence
            )
            isPlaybackActive = false
            if automaticBargeInActive { return }
            responseID = ""
            automaticBargeInActive = false
            voiceActivityDetector.resetForListening()
            state = .ready
            await startContinuousCaptureIfPossible()

        case .responseTextDelta, .responseTextDone:
            responseText = event.payload.string("text") ?? responseText

        case .interrupted:
            audioIO?.cancelPlayback(responseID: responseID)
            isPlaybackActive = false
            responseID = ""
            automaticBargeInActive = false
            voiceActivityDetector.resetForListening()
            responseFilter.clear()
            state = .ready

        case .degraded:
            lastErrorCategory = "provider_degraded"
            state = .degraded

        case .idleWarning:
            let remainingSeconds = event.payload.int("remaining_seconds") ?? 30
            idleWarningRemainingSeconds = max(1, remainingSeconds)
            idleTimeoutEnded = false
            lastReasonCategory = "idle_warning"

        case .sessionEnded:
            guard event.payload.string("reason") == "idle_timeout" else { return }
            idleWarningRemainingSeconds = nil
            idleTimeoutEnded = true
            callIsActive = false
            lastReasonCategory = "idle_timeout"
            lastErrorCategory = "none"
            lastDisconnectRecoverable = false
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectGeneration = nil
            heartbeatTask?.cancel()
            heartbeatTask = nil
            await pipeline?.pauseCapture()
            await pipeline?.abortConnection()
            stopContinuousCapture(resetVAD: true)
            audioIO?.cancelPlayback(responseID: nil)
            isPlaybackActive = false
            responseID = ""
            interruptedResponseID = ""
            interruptedResponseIDs.removeAll(keepingCapacity: false)
            automaticBargeInActive = false
            audioIO?.shutdown()
            await transport?.disconnect()
            webSocketState = .disconnected
            expectedReadyEvent = nil
            lastReadyEvent = nil
            state = .closed

        case .sessionClosed:
            responseID = ""
            isPlaybackActive = false
            await pipeline?.pauseCapture()
            await pipeline?.abortConnection()
            stopContinuousCapture(resetVAD: true)
            heartbeatTask?.cancel()
            heartbeatTask = nil
            await transport?.disconnect()
            webSocketState = .disconnected
            state = .closed

        case .error:
            let code = event.payload.string("code") ?? "protocol_error"
            let retryable = event.payload.bool("retryable") ?? false
            if !retryable {
                guard terminalProtocolErrorCode == nil else { return }
                terminalProtocolErrorCode = code
                lastErrorCategory = code
                lastReasonCategory = "non_retryable_server_error"
                lastDisconnectRecoverable = false
                errorMessage = "The voice service returned an unrecoverable error."
                reconnectTask?.cancel()
                reconnectTask = nil
                reconnectGeneration = nil
                heartbeatTask?.cancel()
                heartbeatTask = nil
                await pipeline?.pauseCapture()
                await pipeline?.abortConnection()
                stopContinuousCapture(resetVAD: true)
                audioIO?.cancelPlayback(responseID: nil)
                isPlaybackActive = false
                responseID = ""
                interruptedResponseID = ""
                interruptedResponseIDs.removeAll(keepingCapacity: false)
                automaticBargeInActive = false
                state = .failed
                return
            }
            lastErrorCategory = code
            lastReasonCategory = "retryable_server_error"
            lastDisconnectRecoverable = true
            errorMessage = "The voice service is temporarily unavailable."
            state = .degraded

        case .pong, .serverState:
            break
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.callIsActive, !self.suspendedForBackground {
                do { try await Task.sleep(for: self.heartbeatInterval) } catch { return }
                do {
                    try await self.pipeline?.ping()
                } catch {
                    self.lastErrorCategory = "connection_lost"
                    self.lastReasonCategory = "heartbeat_failed"
                    self.lastDisconnectRecoverable = true
                    self.beginReconnect(immediate: false)
                    return
                }
            }
        }
    }

    // MARK: - VAD intents

    private func voiceIntents(for data: Data) -> [DVKAudioUploadIntent] {
        guard callIsActive,
              isRecording,
              !isMuted,
              webSocketState == .connected else { return [] }

        let mode: DVKVoiceActivityMode
        if state == .speaking, !responseID.isEmpty {
            mode = .bargeIn
        } else if state == .ready || state == .listening {
            mode = .listening
        } else {
            return []
        }

        let analysis = voiceActivityDetector.process(data, mode: mode)
        var intents: [DVKAudioUploadIntent] = []

        for action in analysis.actions {
            switch action {
            case .rejectedNoise:
                break
            case .speechStarted(let frames, let bargeIn):
                if lastReasonCategory == "idle_warning" {
                    lastReasonCategory = ""
                    idleWarningRemainingSeconds = nil
                }
                let interruptResponseID = bargeIn ? prepareAutomaticBargeIn() : nil
                if !bargeIn { state = .listening }
                intents.append(.beginUtterance(interruptResponseID: interruptResponseID))
                intents.append(contentsOf: frames.map(DVKAudioUploadIntent.audio))
            case .audio(let frame):
                intents.append(.audio(frame))
            case .commit:
                state = .processing
                intents.append(.commit)
            }
        }
        return intents
    }

    private func prepareAutomaticBargeIn() -> String? {
        guard state == .speaking,
              !responseID.isEmpty,
              interruptedResponseID != responseID else { return nil }
        let oldResponseID = responseID
        automaticBargeInActive = true
        interruptedResponseID = oldResponseID
        if interruptedResponseIDs.count >= 32,
           let oldest = interruptedResponseIDs.first {
            interruptedResponseIDs.remove(oldest)
        }
        interruptedResponseIDs.insert(oldResponseID)
        audioIO?.cancelPlayback(responseID: oldResponseID)
        isPlaybackActive = false
        state = .interrupting
        return oldResponseID
    }

    private func handleUploadNotification(_ notification: DVKAudioUploadNotification) {
        switch notification {
        case .audioSent:
            break
        case .commitSent:
            break
        case .interruptSent:
            state = .listening
        case .sendFailed:
            recordSendFailure(DVKAudioUploadError.sendFailed)
        case .backpressure:
            terminalLocalAudioFailure = true
            stopContinuousCapture(resetVAD: true)
            lastErrorCategory = "local_audio_upload_backpressure"
            lastReasonCategory = "audio_upload_queue_full"
            lastDisconnectRecoverable = false
            errorMessage = "The local audio upload queue is full. Please end the call and try again."
            state = .failed
        }
    }

    private func shouldIgnoreInterruptedResponse(_ eventResponseID: String) -> Bool {
        guard !eventResponseID.isEmpty else { return false }
        return interruptedResponseIDs.contains(eventResponseID)
            || (automaticBargeInActive && eventResponseID == interruptedResponseID)
    }

    private func resetProviderGenerationAfterResume() {
        responseID = ""
        interruptedResponseID = ""
        interruptedResponseIDs.removeAll(keepingCapacity: false)
        automaticBargeInActive = false
        audioIO?.cancelPlayback(responseID: nil)
        isPlaybackActive = false
        voiceActivityDetector.resetForListening()
        terminalProtocolErrorCode = nil
    }

    @discardableResult
    private func syncMuteStateAfterResume() async -> Bool {
        do {
            try await pipeline?.setMuted(isMuted)
            return true
        } catch {
            recordSendFailure(error)
            return false
        }
    }

    // MARK: - Continuous capture

    private func startContinuousCaptureIfPossible() async {
        guard callIsActive,
              !suspendedForBackground,
              !isMuted,
              !isRecording,
              let audioIO,
              webSocketState == .connected,
              state == .ready || state == .listening || state == .speaking else { return }
        do {
            try audioIO.startCapture()
            isRecording = true
            await pipeline?.activateCaptureGeneration(audioIO.captureGeneration)
            startCaptureWatchdogIfNeeded()
            voiceActivityDetector.resetForListening()
        } catch {
            state = .failed
            errorMessage = "Unable to start continuous microphone capture."
        }
    }

    private func stopContinuousCapture(resetVAD: Bool) {
        stopCaptureWatchdog()
        audioIO?.stopCapture()
        isRecording = false
        if resetVAD {
            voiceActivityDetector.suspend()
        }
    }

    // MARK: - Capture watchdog

    private func startCaptureWatchdogIfNeeded() {
        guard audioIO != nil, captureWatchdogTask == nil else { return }
        let snapshot = audioIO?.healthSnapshot ?? .unavailable
        captureWatchdogStartedAt = Date()
        lastObservedCaptureCallbackCount = snapshot.callbackCount
        captureRecoveryAttemptCount = 0
        captureWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: self.captureWatchdogInterval) } catch { return }
                await self.checkCaptureHealth()
            }
        }
    }

    private func stopCaptureWatchdog() {
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        captureWatchdogStartedAt = nil
        captureRecoveryAttemptCount = 0
        lastObservedCaptureCallbackCount = 0
    }

    private func checkCaptureHealth() async {
        guard callIsActive,
              !suspendedForBackground,
              !isMuted,
              isRecording,
              let audioIO,
              state != .failed,
              state != .closed,
              state != .closing else { return }

        let snapshot = audioIO.healthSnapshot
        guard !snapshot.isInterrupted else { return }
        if snapshot.callbackCount > lastObservedCaptureCallbackCount {
            lastObservedCaptureCallbackCount = snapshot.callbackCount
            captureRecoveryAttemptCount = 0
            captureWatchdogStartedAt = Date()
            return
        }

        let now = Date()
        let watchdogReference = captureWatchdogStartedAt ?? now
        let lastActivity = max(snapshot.lastCallbackAt ?? watchdogReference, watchdogReference)
        let callbackAge = now.timeIntervalSince(lastActivity)
        let stalled = !snapshot.engineRunning
            || !snapshot.tapInstalled
            || callbackAge >= captureStallThresholdSeconds
        guard stalled else { return }

        guard captureRecoveryAttemptCount < maximumCaptureRecoveryAttempts else {
            await failForCaptureStall()
            return
        }
        captureRecoveryAttemptCount += 1
        do {
            try audioIO.recoverCapture()
            await pipeline?.activateCaptureGeneration(audioIO.captureGeneration)
            captureWatchdogStartedAt = Date()
        } catch {
            if captureRecoveryAttemptCount >= maximumCaptureRecoveryAttempts {
                await failForCaptureStall()
            }
        }
    }

    private func failForCaptureStall() async {
        terminalLocalAudioFailure = true
        await pipeline?.pauseCapture()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectGeneration = nil
        stopContinuousCapture(resetVAD: true)
        audioIO?.cancelPlayback(responseID: nil)
        isPlaybackActive = false
        lastErrorCategory = "local_audio_capture_stalled"
        lastReasonCategory = "capture_watchdog_exhausted"
        lastDisconnectRecoverable = false
        errorMessage = "Local microphone capture stopped. Please end the call and try again."
        state = .failed
    }

    // MARK: - Teardown and helpers

    private func recordSendFailure(_ error: Error) {
        let info = error as? DVKVoiceTransportDisconnectInfo
        lastErrorCategory = info?.errorCategory ?? "connection_lost"
        lastReasonCategory = info?.reasonCategory ?? "send_failed"
        lastDisconnectRecoverable = info?.recoverable ?? true
        errorMessage = "Voice data failed to send. Reconnecting."
        beginReconnect(immediate: false)
    }

    private func tearDownCurrentCall(
        sendSessionEnd: Bool,
        finalState: DVKSessionState?
    ) async {
        let wasActive = callIsActive
        callIsActive = false
        suspendedForBackground = false
        if wasActive { state = .closing }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectGeneration = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        lifecycleTask?.cancel()
        lifecycleTask = nil
        await pipeline?.pauseCapture()
        stopContinuousCapture(resetVAD: true)
        audioIO?.cancelPlayback(responseID: nil)
        isPlaybackActive = false
        audioIO?.shutdown()
        if sendSessionEnd, await transport?.isConnected() == true {
            try? await pipeline?.endSession()
        }
        await pipeline?.abortConnection()
        await stopReceiveLoop()
        await transport?.disconnect()
        webSocketState = .disconnected
        responseID = ""
        expectedReadyEvent = nil
        lastReadyEvent = nil
        if let finalState { state = finalState }
    }

    private func userMessage(for info: DVKVoiceTransportDisconnectInfo) -> String {
        switch info.errorCategory {
        case "unauthorized": return "Voice authentication failed. Please re-enter the device token."
        case "tls_failed": return "The secure connection failed. Check system time and network certificates."
        case "network_unavailable": return "The network is currently unavailable."
        case "connection_lost": return "The voice connection dropped. Reconnecting."
        case "timed_out": return "The voice connection timed out. Reconnecting."
        case "server_closed": return "The voice connection was closed by the server."
        case "protocol_error": return "The voice protocol response was invalid."
        default: return "The voice connection encountered an error."
        }
    }
}

private enum DVKCompanionVoiceClientError: Error, Equatable {
    case callEnded
    case protocolReadyTimedOut
}

private final class DVKCompanionAmplitudeSink: DVKPlaybackAmplitudeSink, @unchecked Sendable {
    private let onChange: @Sendable (Float) -> Void

    init(onChange: @escaping @Sendable (Float) -> Void) {
        self.onChange = onChange
    }

    func playbackAmplitudeDidChange(_ amplitude: Float) {
        onChange(min(1, max(0, amplitude)))
    }
}

private extension Dictionary where Key == String, Value == DVKJSONValue {
    func string(_ key: String) -> String? {
        if case .string(let value) = self[key] { return value }
        return nil
    }

    func int(_ key: String) -> Int? {
        if case .int(let value) = self[key] { return value }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if case .bool(let value) = self[key] { return value }
        return nil
    }
}
#else
/// Linux / non-Combine fallback so the package still builds. No behavior.
@MainActor
public final class DVKCompanionVoiceSessionController {
    public init(configuration: DVKRuntimeConfiguration, tokenStore: any DVKTokenStoring) {}
}
#endif
