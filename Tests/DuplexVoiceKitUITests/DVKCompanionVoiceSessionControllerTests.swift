#if canImport(Combine)
import XCTest
@testable import DuplexVoiceKitUI
import DuplexVoiceKit
import DuplexVoiceKitCompanion

/// Scripted transport double: records outbound messages, replies with the
/// same lifecycle the live gateway provides, and accepts pushed test events.
actor DVKTestVoiceTransport: DVKCompanionVoiceTransport {
    nonisolated let lifecycleEvents: AsyncStream<DVKVoiceTransportLifecycleEvent>
    private nonisolated let broadcaster = DVKVoiceEventBroadcaster<DVKInboundEvent>(bufferLimit: 512)
    private let lifecycleContinuation: AsyncStream<DVKVoiceTransportLifecycleEvent>.Continuation
    private var sentMessages: [DVKOutboundMessage] = []
    private var connected = false
    private var failConnect = false
    private var nextServerSequence = 0

    init() {
        let pair = AsyncStream<DVKVoiceTransportLifecycleEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(128)
        )
        lifecycleEvents = pair.stream
        lifecycleContinuation = pair.continuation
    }

    nonisolated func events() -> AsyncStream<DVKInboundEvent> {
        broadcaster.makeStream()
    }

    func connect() async throws {
        if failConnect {
            throw DVKVoiceTransportDisconnectInfo(
                closeCode: nil,
                recoverable: true,
                errorCategory: "network_unavailable",
                reasonCategory: "network_transport"
            )
        }
        connected = true
        lifecycleContinuation.yield(.connecting)
        lifecycleContinuation.yield(.connected)
    }

    func send(_ message: DVKOutboundMessage) async throws {
        sentMessages.append(message)
        guard connected else {
            throw DVKVoiceTransportDisconnectInfo(
                closeCode: nil,
                recoverable: true,
                errorCategory: "connection_lost",
                reasonCategory: "transport_closed"
            )
        }
        nextServerSequence += 1
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
        broadcaster.yield(DVKInboundEvent(
            version: message.version,
            eventID: UUID().uuidString,
            traceID: message.traceID,
            sessionID: message.sessionID,
            sequence: nextServerSequence,
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
            type: responseType,
            payload: payload
        ))
    }

    func ping() async throws {}

    func disconnect() async {
        connected = false
        lifecycleContinuation.yield(.disconnected(
            DVKVoiceTransportErrorClassifier.classify(
                error: URLError(.cancelled),
                closeCode: 1000,
                intentional: true
            )
        ))
    }

    func isConnected() async -> Bool { connected }

    // Test controls
    func pushEvent(_ event: DVKInboundEvent) { broadcaster.yield(event) }
    func pushLifecycle(_ event: DVKVoiceTransportLifecycleEvent) { lifecycleContinuation.yield(event) }
    func setConnected(_ value: Bool) { connected = value }
    func setFailConnect(_ value: Bool) { failConnect = value }
    func sentMessagesSnapshot() -> [DVKOutboundMessage] { sentMessages }
    func sentMessageCount() -> Int { sentMessages.count }
}

/// Deterministic audio IO double. No second engine: pure test state.
final class DVKMockAudioIO: DVKCompanionAudioIO, @unchecked Sendable {
    var captureGeneration = 0
    var callbackCount = 0
    var engineRunning = true
    var tapInstalled = true
    var isInterrupted = false
    var restartCount = 0
    var lastCallbackAt: Date? = Date()
    var startFailure: Error?
    var recoverFailure: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var enqueued: [(data: Data, responseID: String, chunkIndex: Int)] = []
    var amplitudeSink: (any DVKPlaybackAmplitudeSink)?

    var healthSnapshot: DVKCompanionAudioHealth {
        DVKCompanionAudioHealth(
            engineRunning: engineRunning,
            tapInstalled: tapInstalled,
            callbackCount: callbackCount,
            lastCallbackAt: lastCallbackAt,
            restartCount: restartCount,
            isInterrupted: isInterrupted
        )
    }

    func startCapture() throws {
        if let startFailure { throw startFailure }
        startCount += 1
        captureGeneration += 1
    }
    func stopCapture() { stopCount += 1 }
    func enqueuePlayback(_ data: Data, responseID: String, chunkIndex: Int) {
        enqueued.append((data, responseID, chunkIndex))
    }
    func cancelPlayback(responseID: String?) {}
    func recoverCapture() throws {
        if let recoverFailure { throw recoverFailure }
        restartCount += 1
        lastCallbackAt = Date()
    }
    func shutdown() {}
    func setPlaybackAmplitudeSink(_ sink: (any DVKPlaybackAmplitudeSink)?) {
        amplitudeSink = sink
    }
}

@MainActor
final class DVKCompanionVoiceSessionControllerTests: XCTestCase {

    private var tokenStore: DVKMemoryTokenStore!
    private var transport: DVKTestVoiceTransport!
    private var audioIO: DVKMockAudioIO!
    private var controller: DVKCompanionVoiceSessionController!

    override func setUp() {
        super.setUp()
        tokenStore = DVKMemoryTokenStore()
        try? tokenStore.save("synthetic-token")
        transport = DVKTestVoiceTransport()
        audioIO = DVKMockAudioIO()
    }

    override func tearDown() async throws {
        if let controller {
            await controller.endCurrentCall()
        }
        controller = nil
        transport = nil
        audioIO = nil
        tokenStore = nil
    }

    /// Defaults keep heartbeat and capture-watchdog timers out of the way so
    /// assertions are not raced by background pong sequences or a stall failure.
    /// Only the dedicated heartbeat / watchdog tests shorten their own timer.
    private func makeController(
        heartbeat: Duration = .seconds(30),
        stallThreshold: Duration = .seconds(30),
        watchdogInterval: Duration = .seconds(30)
    ) -> DVKCompanionVoiceSessionController {
        let configuration = DVKRuntimeConfiguration(
            apiBaseURL: URL(string: "https" + "://" + "api.example.test")!,
            voiceWebSocketURL: URL(string: "wss" + "://" + "voice.example.test/v1/voice/ws")!,
            deviceID: "dvk-demo-device"
        )
        let controller = DVKCompanionVoiceSessionController(
            configuration: configuration,
            tokenStore: tokenStore,
            transportFactory: { [transport] _ in transport },
            audioIO: audioIO,
            reconnectPolicy: DVKReconnectPolicy(
                maximumAttempts: 2,
                baseDelay: .milliseconds(20),
                maximumDelay: .milliseconds(40)
            ),
            protocolReadyTimeout: .seconds(2),
            captureWatchdogInterval: watchdogInterval,
            captureStallThreshold: stallThreshold,
            maximumCaptureRecoveryAttempts: 1,
            heartbeatInterval: heartbeat
        )
        self.controller = controller
        return controller
    }

    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(3), file: StaticString = #filePath, line: UInt = #line) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition not met within timeout", file: file, line: line)
    }

    private func event(type: String, sessionID: String, sequence: Int, payload: [String: DVKJSONValue] = [:]) -> DVKInboundEvent {
        DVKInboundEvent(
            version: "0.2",
            eventID: UUID().uuidString,
            traceID: "trace",
            sessionID: sessionID,
            sequence: sequence,
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
            type: type,
            payload: payload
        )
    }

    // 14.4: session.start waits for session.ready (ready gate)
    func testSessionStartWaitsForReady() async {
        let controller = makeController()
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(controller.state, .ready)
        XCTAssertTrue(controller.pipelineDiagnosticsForTesting != nil, "must drive the DVK upload pipeline")
    }

    // 14.4: resume continues from the last server sequence
    func testResumeUsesLastServerSequence() async {
        let controller = makeController()
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(controller.lastServerSequenceForTesting, 1)

        await transport.setConnected(false)
        await transport.pushLifecycle(.disconnected(
            DVKVoiceTransportDisconnectInfo(
                closeCode: 1006,
                recoverable: true,
                errorCategory: "connection_lost",
                reasonCategory: "abnormal_close"
            )
        ))
        await waitUntil { controller.state == .ready && controller.reconnectAttempt == 0 }

        let messages = await transport.sentMessagesSnapshot()
        let resume = messages.first { $0.type == "session.resume" }
        XCTAssertNotNil(resume, "reconnect must send session.resume")
        if case .int(let sequence)? = resume?.payload["last_received_server_sequence"] {
            XCTAssertEqual(sequence, 1)
        } else {
            XCTFail("session.resume must carry last_received_server_sequence")
        }
    }

    // 14.4: stale server sequences are dropped
    func testStaleSequenceIsDropped() async {
        let controller = makeController()
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }

        // Duplicate of the last seen sequence: must be ignored.
        await transport.pushEvent(event(
            type: "response.started",
            sessionID: controller.sessionID,
            sequence: 1,
            payload: ["response_id": .string("r-stale")]
        ))
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(controller.responseIDForTesting, "")

        // A newer sequence is accepted.
        await transport.pushEvent(event(
            type: "response.started",
            sessionID: controller.sessionID,
            sequence: 2,
            payload: ["response_id": .string("r1")]
        ))
        await waitUntil { controller.state == .speaking }
        XCTAssertEqual(controller.responseIDForTesting, "r1")
    }

    // 14.4: interrupt sends the active response id and drops later audio
    func testInterruptSendsResponseID() async {
        let controller = makeController()
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        await transport.pushEvent(event(
            type: "response.started",
            sessionID: controller.sessionID,
            sequence: 2,
            payload: ["response_id": .string("r1")]
        ))
        await waitUntil { controller.state == .speaking }
        await controller.interrupt()
        let messages = await transport.sentMessagesSnapshot()
        let interrupt = messages.first { $0.type == "interrupt" }
        XCTAssertNotNil(interrupt)
        if case .string(let responseID)? = interrupt?.payload["response_id"] {
            XCTAssertEqual(responseID, "r1")
        } else {
            XCTFail("interrupt must carry the active response_id")
        }
    }

    // 14.4: mute and unmute are propagated and capture is paused/resumed
    func testMuteAndUnmute() async {
        let controller = makeController()
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        await waitUntil { controller.isRecording }

        await controller.setMuted(true)
        XCTAssertTrue(controller.isMuted)
        XCTAssertFalse(controller.isRecording)
        let afterMute = await transport.sentMessagesSnapshot()
        XCTAssertTrue(afterMute.contains { $0.type == "mute" })

        await controller.setMuted(false)
        XCTAssertFalse(controller.isMuted)
        await waitUntil { controller.isRecording }
        let afterUnmute = await transport.sentMessagesSnapshot()
        XCTAssertTrue(afterUnmute.contains { $0.type == "unmute" })
    }

    // 14.4: server idle warning surfaces remaining seconds
    func testIdleWarningSetsRemainingSeconds() async {
        let controller = makeController()
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        await transport.pushEvent(event(
            type: "server.idle_warning",
            sessionID: controller.sessionID,
            sequence: 2,
            payload: ["remaining_seconds": .int(20)]
        ))
        await waitUntil { controller.idleWarningRemainingSeconds == 20 }
    }

    // 14.4: session.ended with idle_timeout ends the session
    func testIdleTimeoutEndsSession() async {
        let controller = makeController()
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        await transport.pushEvent(event(
            type: "session.ended",
            sessionID: controller.sessionID,
            sequence: 2,
            payload: ["reason": .string("idle_timeout")]
        ))
        await waitUntil { controller.state == .closed }
        XCTAssertTrue(controller.idleTimeoutEnded)
        XCTAssertFalse(controller.hasActiveCall)
    }

    // 14.4: the 20s heartbeat policy sends pings (shortened for the test)
    func testHeartbeatSendsPing() async {
        let controller = makeController(heartbeat: .milliseconds(30))
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        try? await Task.sleep(for: .milliseconds(150))
        let messages = await transport.sentMessagesSnapshot()
        XCTAssertTrue(messages.contains { $0.type == "ping" })
    }

    // 14.4: the capture watchdog fails explicitly after recovery is exhausted
    func testCaptureWatchdogFailsAfterExhaustion() async {
        audioIO.callbackCount = 0
        audioIO.engineRunning = false
        audioIO.tapInstalled = false
        audioIO.recoverFailure = DVKAudioUploadError.sendFailed
        let controller = makeController(
            stallThreshold: .milliseconds(30),
            watchdogInterval: .milliseconds(20)
        )
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        await waitUntil { controller.isRecording }
        await waitUntil { controller.state == .failed }
        XCTAssertTrue(controller.errorMessage.lowercased().contains("capture"))
        XCTAssertEqual(controller.lastReasonCategoryForTesting, "capture_watchdog_exhausted")
    }

    // 14.4: diagnostics never contain token, device id, or transcript
    func testDiagnosticsAreRedacted() async {
        let controller = makeController()
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        controller.setResponseTextForTesting("secret-message")
        let text = controller.redactedDiagnosticsText
        XCTAssertFalse(text.contains("synthetic-token"))
        XCTAssertFalse(text.contains("dvk-demo-device"))
        XCTAssertFalse(text.contains("secret-message"))
    }

    // 14.4: the controller reuses DVK Core state machines (no second pipeline or filter)
    func testUsesDVKPipelineAndResponseFilter() async {
        let controller = makeController()
        await controller.startNewCall()
        await waitUntil { controller.state == .ready }
        await transport.pushEvent(event(
            type: "response.started",
            sessionID: controller.sessionID,
            sequence: 2,
            payload: ["response_id": .string("r1")]
        ))
        await waitUntil { controller.state == .speaking }
        XCTAssertNotNil(controller.pipelineDiagnosticsForTesting)
        XCTAssertGreaterThan(controller.responseFilterLastServerSequenceForTesting, 0)
        XCTAssertEqual(
            controller.responseFilterLastServerSequenceForTesting,
            controller.lastServerSequenceForTesting,
            "sequence tracking must flow through the DVK response filter"
        )
    }
}
#endif
