import Foundation
import XCTest
@testable import XiaomaoApp

@MainActor
final class VoiceSessionControllerTests: XCTestCase {
    func testStartNewCallCreatesFreshSessionAndResetsIdentifiersAndCounters() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let firstSession = fixture.controller.sessionIDForTesting
        let firstTrace = fixture.controller.traceIDForTesting
        XCTAssertEqual(fixture.controller.state, .ready)

        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        await settle()
        XCTAssertGreaterThan(fixture.controller.chunkIndexForTesting, 0)
        await fixture.controller.endCurrentCall()

        await fixture.controller.startNewCall()
        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertNotEqual(fixture.controller.sessionIDForTesting, firstSession)
        XCTAssertNotEqual(fixture.controller.traceIDForTesting, firstTrace)
        XCTAssertEqual(fixture.controller.chunkIndexForTesting, 0)
        XCTAssertEqual(fixture.controller.clientSequenceForTesting, 1)
    }

    func testInitialConnectionIndicatorStaysCompletedDuringLaterProcessing() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()
        XCTAssertFalse(fixture.controller.hasCompletedInitialConnection)

        fixture.audio.emit(pcmFrame(amplitude: 2_000))
        await waitUntil {
            fixture.controller.hasCompletedInitialConnection
        }
        XCTAssertTrue(fixture.controller.hasCompletedInitialConnection)

        await fixture.socket.emitServerEvent(
            .thinkingStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting
        )
        await settle()

        XCTAssertEqual(fixture.controller.state, .processing)
        XCTAssertTrue(fixture.controller.hasCompletedInitialConnection)
    }

    func testEndThenReenterNeverReusesClosedSession() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let closedSession = fixture.controller.sessionIDForTesting
        await fixture.controller.endCurrentCall()
        XCTAssertEqual(fixture.controller.state, .closed)
        await fixture.controller.startNewCall()
        XCTAssertNotEqual(fixture.controller.sessionIDForTesting, closedSession)
    }

    func testRecoverableDisconnectCreatesOnlyOneReconnectLoopAndWaitsForResume() async {
        let fixture = makeFixture(reconnectDelays: [.milliseconds(1), .milliseconds(1)])
        await fixture.controller.startNewCall()
        let initialCaptureStarts = fixture.capture.startCount
        let abnormal = VoiceWebSocketErrorClassifier.classify(
            error: URLError(.networkConnectionLost),
            closeCode: 1006
        )
        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.reconnectAttempt == 0
                && !fixture.controller.hasReconnectTaskForTesting
                && fixture.controller.isRecording
        }
        let connectCount = await fixture.socket.connectCountValue()
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertEqual(connectCount, 2)
        XCTAssertEqual(sent.filter { $0 == .sessionResume }.count, 1)
        XCTAssertEqual(fixture.capture.startCount, initialCaptureStarts + 1)
        XCTAssertEqual(fixture.controller.activeReceiveLoopCountForTesting, 1)
        XCTAssertEqual(fixture.controller.maxActiveReceiveLoopCountForTesting, 1)
        XCTAssertFalse(fixture.controller.hasReconnectTaskForTesting)
    }

    func testLateDuplicateDisconnectDoesNotInvalidateNewConnection() async {
        let fixture = makeFixture(
            autoResume: false,
            reconnectDelays: [.milliseconds(1)]
        )
        await fixture.controller.startNewCall()
        let initialCaptureStarts = fixture.capture.startCount
        let abnormal = VoiceWebSocketErrorClassifier.classify(
            error: URLError(.networkConnectionLost),
            closeCode: 1006
        )

        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        await fixture.socket.emitStaleDisconnect(abnormal)
        await fixture.socket.emitResumed()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.webSocketState == .connected
                && fixture.controller.reconnectAttempt == 0
                && !fixture.controller.hasReconnectTaskForTesting
                && fixture.controller.isRecording
        }

        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, 2)
        XCTAssertEqual(fixture.capture.startCount, initialCaptureStarts + 1)
        XCTAssertEqual(fixture.controller.maxActiveReceiveLoopCountForTesting, 1)
    }

    func testIntentionalDisconnectDoesNotReconnect() async {
        let fixture = makeFixture(reconnectDelays: [.milliseconds(1)])
        await fixture.controller.startNewCall()
        await fixture.controller.endCurrentCall()
        await settle()
        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, 1)
        XCTAssertEqual(fixture.controller.state, .closed)
    }

    func testSpeechStartReportsExplicitVADActivity() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()

        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))

        let reported = await fixture.socket.waitForSentEvent(
            .clientState,
            count: 1,
            timeout: .seconds(2)
        )
        XCTAssertTrue(reported)
        let events = await fixture.socket.sentEventsValue()
        let activity = events.last { $0.type == .clientState }
        XCTAssertEqual(activity?.payload["vad_state"], .string("speech_start"))
    }

    func testIdleWarningDisplaysRemainingTimeWithoutClosingCall() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await fixture.socket.emitServerEvent(
            .serverIdleWarning,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["remaining_seconds": .int(30)]
        )
        await settle()

        // P2.7B-FINAL-IDLE: 产品化 — 剩余秒数写入独立状态, 不写入 errorMessage, 不改变 .ready
        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertEqual(fixture.controller.idleWarningRemainingSeconds, 30)
        XCTAssertFalse(fixture.controller.idleTimeoutEnded)
        XCTAssertTrue(fixture.controller.errorMessage.isEmpty,
                      "空闲预警不得写入 errorMessage (不得显示为红色错误)")
    }

    func testIdleTimeoutEndsCallWithoutReconnect() async {
        let fixture = makeFixture(reconnectDelays: [.milliseconds(1)])
        await fixture.controller.startNewCall()
        await fixture.socket.emitServerEvent(
            .sessionEnded,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["reason": .string("idle_timeout")]
        )
        await waitUntil {
            fixture.controller.state == .closed
                && fixture.controller.webSocketState == .disconnected
        }
        await settle()

        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, 1)
        XCTAssertFalse(fixture.controller.hasReconnectTaskForTesting)
        XCTAssertFalse(fixture.controller.lastDisconnectRecoverable)
        XCTAssertEqual(fixture.controller.lastReasonCategory, "idle_timeout")
        // P2.7B-FINAL-IDLE: 产品化 — 空闲结束由专用弹窗呈现 (idleTimeoutEnded), 不写入 errorMessage
        XCTAssertTrue(fixture.controller.idleTimeoutEnded)
        XCTAssertNil(fixture.controller.idleWarningRemainingSeconds)
        XCTAssertTrue(fixture.controller.errorMessage.isEmpty,
                      "空闲结束不得写入 errorMessage (不得按普通错误/网络失败归类)")
    }

    // MARK: P2.7B-FINAL-IDLE 控制器产品状态补充验证

    func testIdleWarningDoesNotChangeReadyStateNorClearOnNewWarning() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()

        // 第一轮预警
        await fixture.socket.emitServerEvent(
            .serverIdleWarning,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["remaining_seconds": .int(60)]
        )
        await settle()
        XCTAssertEqual(fixture.controller.idleWarningRemainingSeconds, 60)
        XCTAssertEqual(fixture.controller.state, .ready)

        // 第二轮预警覆盖 (服务端可再次下发)
        await fixture.socket.emitServerEvent(
            .serverIdleWarning,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["remaining_seconds": .int(15)]
        )
        await settle()
        XCTAssertEqual(fixture.controller.idleWarningRemainingSeconds, 15)
        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertTrue(fixture.controller.errorMessage.isEmpty)
    }

    func testSpeechStartClearsIdleWarningAndReportsOnce() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()

        // 触发预警
        await fixture.socket.emitServerEvent(
            .serverIdleWarning,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["remaining_seconds": .int(30)]
        )
        await settle()
        XCTAssertEqual(fixture.controller.idleWarningRemainingSeconds, 30)

        // 真实语音 → 清空预警
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))

        let reported = await fixture.socket.waitForSentEvent(
            .clientState,
            count: 1,
            timeout: .seconds(2)
        )
        XCTAssertTrue(reported)
        await settle()
        XCTAssertNil(fixture.controller.idleWarningRemainingSeconds)

        // speech_start 仍只上报一次
        let events = await fixture.socket.sentEventsValue()
        let activityCount = events.filter { $0.type == .clientState && $0.payload["vad_state"] == .string("speech_start") }.count
        XCTAssertEqual(activityCount, 1, "speech start 必须只发送一次 client.state / speech_start")
    }

    func testNewCallResetsIdleUIStates() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await fixture.socket.emitServerEvent(
            .serverIdleWarning,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["remaining_seconds": .int(30)]
        )
        await settle()
        XCTAssertEqual(fixture.controller.idleWarningRemainingSeconds, 30)

        // 结束本轮并开始新通话 → 两个 idle UI 状态被清空
        await fixture.controller.endCurrentCall()
        await fixture.controller.startNewCall()
        await settle()
        XCTAssertNil(fixture.controller.idleWarningRemainingSeconds)
        XCTAssertFalse(fixture.controller.idleTimeoutEnded)
    }

    func testBackgroundKeepsActiveVoiceCallConnectedAndCapturing() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let captureStopCount = fixture.capture.stopCount

        await fixture.controller.appDidEnterBackground()
        await settle()

        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertEqual(fixture.controller.webSocketState, .connected)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertTrue(fixture.audioSession.isActive)
        XCTAssertEqual(fixture.capture.stopCount, captureStopCount)
        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, 1)

        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        let audioSent = await fixture.socket.waitForSentEvent(
            .audioAppend,
            count: 1,
            timeout: .seconds(2)
        )
        XCTAssertTrue(audioSent)
    }

    func test1006IsClassifiedAsRecoverable() {
        let abnormal = VoiceWebSocketErrorClassifier.classify(error: nil, closeCode: 1006)
        XCTAssertTrue(abnormal.recoverable)
        XCTAssertEqual(abnormal.errorCategory, "connection_lost")
        XCTAssertEqual(abnormal.reasonCategory, "abnormal_close")
    }

    func testUnauthorizedIsClassifiedAsNonRecoverable() {
        let unauthorized = VoiceWebSocketErrorClassifier.classify(
            error: URLError(.userAuthenticationRequired),
            closeCode: nil,
            httpStatus: 401
        )
        XCTAssertFalse(unauthorized.recoverable)
        XCTAssertEqual(unauthorized.errorCategory, "unauthorized")
    }

    func testUnauthorizedDoesNotRetryForever() async {
        let fixture = makeFixture(reconnectDelays: [.milliseconds(1), .milliseconds(1)])
        await fixture.controller.startNewCall()
        let unauthorized = VoiceWebSocketErrorClassifier.classify(
            error: URLError(.userAuthenticationRequired),
            closeCode: nil,
            httpStatus: 401
        )
        await fixture.socket.simulateFailure(unauthorized)
        await waitUntil { fixture.controller.state == .failed }
        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, 1)
        XCTAssertFalse(fixture.controller.hasReconnectTaskForTesting)
    }

    func testConnectedWithoutSessionReadyNeverBecomesReady() async {
        let fixture = makeFixture(autoReady: false, reconnectDelays: [], protocolReadyTimeout: .milliseconds(20))
        await fixture.controller.startNewCall()
        XCTAssertNotEqual(fixture.controller.state, .ready)
        XCTAssertEqual(fixture.controller.webSocketState, .connected)
    }

    func testSessionReadyTransitionsNewCallToReady() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        XCTAssertEqual(fixture.controller.state, .ready)
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertTrue(sent.contains(.sessionStart))
    }

    func testSessionResumedTransitionsReconnectToReady() async {
        let fixture = makeFixture(
            autoResume: false,
            reconnectDelays: [.milliseconds(1)]
        )
        await fixture.controller.startNewCall()
        let abnormal = VoiceWebSocketErrorClassifier.classify(error: nil, closeCode: 1006)
        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        await fixture.socket.emitResumed()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.reconnectAttempt == 0
                && !fixture.controller.hasReconnectTaskForTesting
                && fixture.controller.isRecording
        }
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertEqual(sent.filter { $0 == .sessionResume }.count, 1)
        XCTAssertEqual(fixture.controller.protocolReadyEventCountForTesting, 2)
    }

    func testResumedProviderGenerationResetsAudioChunkIndex() async {
        let fixture = makeFixture(
            autoResume: false,
            reconnectDelays: [.milliseconds(1)]
        )
        await fixture.controller.startNewCall()
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        let initialAudioSent = await fixture.socket.waitForSentEvent(
            .audioAppend,
            count: 3,
            timeout: .seconds(2)
        )
        XCTAssertTrue(initialAudioSent, fixture.controller.diagnosticText)
        guard initialAudioSent else { return }
        XCTAssertEqual(fixture.controller.chunkIndexForTesting, 3)

        let abnormal = VoiceWebSocketErrorClassifier.classify(error: nil, closeCode: 1006)
        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        await fixture.socket.emitResumed()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.isRecording
                && fixture.controller.reconnectAttempt == 0
                && !fixture.controller.hasReconnectTaskForTesting
        }

        XCTAssertEqual(fixture.controller.chunkIndexForTesting, 0)
        XCTAssertEqual(fixture.controller.responseIDForTesting, "")
    }

    func testFirstAudioChunkAfterResumeIsZero() async {
        let fixture = makeFixture(
            autoResume: false,
            reconnectDelays: [.milliseconds(1)]
        )
        await fixture.controller.startNewCall()
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        let initialAudioSent = await fixture.socket.waitForSentEvent(
            .audioAppend,
            count: 3,
            timeout: .seconds(2)
        )
        XCTAssertTrue(initialAudioSent, fixture.controller.diagnosticText)
        guard initialAudioSent else { return }

        let abnormal = VoiceWebSocketErrorClassifier.classify(error: nil, closeCode: 1006)
        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        await fixture.socket.emitResumed()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.isRecording
                && !fixture.controller.hasReconnectTaskForTesting
        }
        await fixture.socket.clearSentEvents()

        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        let resumedAudioSent = await fixture.socket.waitForSentEvent(
            .audioAppend,
            count: 3,
            timeout: .seconds(2)
        )
        XCTAssertTrue(resumedAudioSent, fixture.controller.diagnosticText)
        guard resumedAudioSent else { return }
        let events = await fixture.socket.sentEventsValue()
        XCTAssertEqual(Array(audioChunkIndexes(in: events).prefix(3)), [0, 1, 2])
    }

    func testResumeDoesNotReplayOldAudio() async {
        let fixture = makeFixture(
            autoResume: false,
            reconnectDelays: [.milliseconds(1)]
        )
        await fixture.controller.startNewCall()
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        await fixture.socket.waitForSentEvent(.audioAppend, count: 3)
        let beforeDisconnect = await fixture.socket.sentEventsValue()
        let oldAudioCount = beforeDisconnect.filter { $0.type == .audioAppend }.count

        let abnormal = VoiceWebSocketErrorClassifier.classify(error: nil, closeCode: 1006)
        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        await fixture.socket.emitResumed()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.isRecording
                && !fixture.controller.hasReconnectTaskForTesting
        }
        let afterResume = await fixture.socket.sentEventsValue()
        XCTAssertEqual(afterResume.filter { $0.type == .audioAppend }.count, oldAudioCount)
    }

    func testStrictReconnectRoundTripReturnsReady() async {
        let fixture = makeFixture(
            autoResume: false,
            reconnectDelays: [.milliseconds(1)]
        )
        await fixture.controller.startNewCall()
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        await fixture.socket.waitForSentEvent(.audioAppend, count: 3)
        let firstGeneration = await fixture.socket.sentEventsValue()
        XCTAssertEqual(Array(audioChunkIndexes(in: firstGeneration).prefix(3)), [0, 1, 2])

        let oldServerSequence = fixture.controller.lastServerSequenceForTesting
        let abnormal = VoiceWebSocketErrorClassifier.classify(error: nil, closeCode: 1006)
        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        let resumeEvents = await fixture.socket.sentEventsValue()
        guard let resume = resumeEvents.last(where: { $0.type == .sessionResume }) else {
            return XCTFail("session.resume must be sent")
        }
        guard case .int(let acknowledged) = resume.payload["last_received_server_sequence"] else {
            return XCTFail("session.resume must acknowledge the last server sequence")
        }
        XCTAssertEqual(acknowledged, oldServerSequence)
        await fixture.socket.emitResumed()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.isRecording
                && fixture.controller.reconnectAttempt == 0
                && !fixture.controller.hasReconnectTaskForTesting
        }
        await fixture.socket.clearSentEvents()

        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        await fixture.socket.waitForSentEvent(.audioAppend, count: 3)
        let secondGeneration = await fixture.socket.sentEventsValue()
        XCTAssertEqual(Array(audioChunkIndexes(in: secondGeneration).prefix(3)), [0, 1, 2])
        XCTAssertTrue(fixture.controller.state == .ready || fixture.controller.state == .listening)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.reconnectAttempt, 0)
        XCTAssertFalse(fixture.controller.hasReconnectTaskForTesting)
        XCTAssertEqual(fixture.controller.responseNextSentCount, 0)
    }

    func testNonRetryableProtocolErrorStopsCapture() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let appendCountBefore = (await fixture.socket.sentEventsValue())
            .filter { $0.type == .audioAppend }.count
        let stopCountBefore = fixture.capture.stopCount

        await fixture.socket.emitServerEvent(
            .error,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: [
                "code": .string("chunk_index_out_of_order"),
                "retryable": .bool(false)
            ]
        )
        await waitUntil {
            fixture.controller.state == .failed
                && !fixture.controller.isRecording
                && !fixture.controller.hasReconnectTaskForTesting
                && !fixture.controller.hasHeartbeatTaskForTesting
        }

        XCTAssertGreaterThan(fixture.capture.stopCount, stopCountBefore)
        XCTAssertEqual(fixture.controller.lastErrorCategory, "chunk_index_out_of_order")
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        await drainTasks()
        let appendCountAfter = (await fixture.socket.sentEventsValue())
            .filter { $0.type == .audioAppend }.count
        XCTAssertEqual(appendCountAfter, appendCountBefore)
    }

    func testChunkIndexErrorDoesNotFloodServer() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let payload: [String: JSONValue] = [
            "code": .string("chunk_index_out_of_order"),
            "retryable": .bool(false)
        ]
        for _ in 0..<12 {
            await fixture.socket.emitServerEvent(
                .error,
                sessionID: fixture.controller.sessionIDForTesting,
                traceID: fixture.controller.traceIDForTesting,
                payload: payload
            )
        }
        await waitUntil { fixture.controller.state == .failed }
        XCTAssertEqual(fixture.controller.providerErrorCountForTesting, 1)
        XCTAssertFalse(fixture.controller.isRecording)

        let before = (await fixture.socket.sentEventsValue())
            .filter { $0.type == .audioAppend }.count
        for _ in 0..<8 {
            fixture.capture.emit(pcmFrame(amplitude: 3_000))
        }
        await drainTasks()
        let after = (await fixture.socket.sentEventsValue())
            .filter { $0.type == .audioAppend }.count
        XCTAssertEqual(after, before)
        XCTAssertEqual(fixture.controller.providerErrorCountForTesting, 1)
    }

    func testManualReconnectFromClosedStartsFreshSession() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let closedSession = fixture.controller.sessionIDForTesting
        let initialCaptureStarts = fixture.capture.startCount
        await fixture.socket.emitServerEvent(
            .sessionClosed,
            sessionID: closedSession,
            traceID: fixture.controller.traceIDForTesting
        )
        await waitUntil { fixture.controller.state == .closed }
        fixture.controller.reconnectCurrentCall()
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionStart, count: 2)
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.sessionIDForTesting != closedSession
                && fixture.controller.isRecording
                && fixture.controller.activeReceiveLoopCountForTesting == 1
        }
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertNotEqual(fixture.controller.sessionIDForTesting, closedSession)
        XCTAssertEqual(sent.filter { $0 == .sessionStart }.count, 2)
        XCTAssertEqual(fixture.capture.startCount, initialCaptureStarts + 1)
    }

    func testReadyBeforeLifecycleConnectedStillStartsCapture() async {
        let fixture = makeFixture(autoLifecycleConnected: false)
        await fixture.controller.startNewCall()

        XCTAssertEqual(fixture.controller.protocolReadyEventCountForTesting, 1)
        XCTAssertEqual(fixture.controller.lifecycleConnectedEventCountForTesting, 0)
        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.capture.startCount, 1)

        await fixture.socket.emitConnected()
        await waitUntil {
            fixture.controller.lifecycleConnectedEventCountForTesting == 1
        }
        XCTAssertEqual(fixture.capture.startCount, 1)
    }

    func testLifecycleConnectedBeforeReadyStartsCapture() async {
        let fixture = makeFixture(
            autoReady: false,
            autoLifecycleConnected: true,
            reconnectDelays: [],
            protocolReadyTimeout: .seconds(1)
        )
        let startTask = Task { @MainActor in
            await fixture.controller.startNewCall()
        }
        await fixture.socket.waitForSentEvent(.sessionStart)
        await waitUntil {
            fixture.controller.lifecycleConnectedEventCountForTesting == 1
                && fixture.controller.webSocketState == .connected
        }
        XCTAssertEqual(fixture.capture.startCount, 0)

        await fixture.socket.emitReady()
        await startTask.value

        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.capture.startCount, 1)
    }

    func testDuplicateConnectedAndReadyStartCaptureOnlyOnce() async {
        let fixture = makeFixture(
            autoReady: false,
            autoLifecycleConnected: false,
            reconnectDelays: [],
            protocolReadyTimeout: .seconds(1)
        )
        let startTask = Task { @MainActor in
            await fixture.controller.startNewCall()
        }
        await fixture.socket.waitForSentEvent(.sessionStart)
        await fixture.socket.emitReady()
        await startTask.value
        XCTAssertEqual(fixture.capture.startCount, 1)

        await fixture.socket.emitConnected()
        await fixture.socket.emitConnected()
        await fixture.socket.emitReady()
        await fixture.socket.emitReady()
        await waitUntil {
            fixture.controller.lifecycleConnectedEventCountForTesting == 2
                && fixture.controller.protocolReadyEventCountForTesting == 3
        }

        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.capture.startCount, 1)
    }

    func testSessionResumedBeforeConnectedStillStartsCapture() async {
        let fixture = makeFixture(
            autoLifecycleConnected: false,
            reconnectDelays: [.milliseconds(1)]
        )
        await fixture.controller.startNewCall()
        let initialCaptureStarts = fixture.capture.startCount
        let abnormal = VoiceWebSocketErrorClassifier.classify(error: nil, closeCode: 1006)

        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.reconnectAttempt == 0
                && fixture.controller.isRecording
        }

        XCTAssertEqual(fixture.controller.lifecycleConnectedEventCountForTesting, 0)
        XCTAssertEqual(fixture.capture.startCount, initialCaptureStarts + 1)
        await fixture.socket.emitConnected()
        await waitUntil {
            fixture.controller.lifecycleConnectedEventCountForTesting == 1
        }
        XCTAssertEqual(fixture.capture.startCount, initialCaptureStarts + 1)
    }

    func testReceiveLoopIsFullyStoppedBeforeNewCall() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let oldGeneration = fixture.controller.receiveGenerationForTesting
        let oldStartCount = fixture.controller.receiveLoopStartCountForTesting
        let oldStopCount = fixture.controller.receiveLoopStopCountForTesting

        await fixture.controller.startNewCall()

        XCTAssertGreaterThan(fixture.controller.receiveGenerationForTesting, oldGeneration)
        XCTAssertEqual(fixture.controller.receiveLoopStartCountForTesting, oldStartCount + 1)
        XCTAssertEqual(fixture.controller.receiveLoopStopCountForTesting, oldStopCount + 1)
        XCTAssertEqual(fixture.controller.activeReceiveLoopCountForTesting, 1)
        XCTAssertEqual(fixture.controller.maxActiveReceiveLoopCountForTesting, 1)
        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertTrue(fixture.controller.isRecording)
    }

    func testManualReconnectDoesNotLoseNewSessionReady() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let oldSession = fixture.controller.sessionIDForTesting
        await fixture.socket.setAutomaticEvents(ready: false)
        await fixture.socket.emitServerEvent(
            .sessionClosed,
            sessionID: oldSession,
            traceID: fixture.controller.traceIDForTesting
        )
        await waitUntil { fixture.controller.state == .closed }

        fixture.controller.reconnectCurrentCall()
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionStart, count: 2)
        await fixture.socket.emitReady()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.sessionIDForTesting != oldSession
                && fixture.controller.isRecording
        }

        XCTAssertEqual(fixture.controller.activeReceiveLoopCountForTesting, 1)
        XCTAssertEqual(fixture.controller.protocolReadyEventCountForTesting, 2)
    }

    func testOldCancelledReceiveLoopCannotConsumeNewReady() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await fixture.controller.endCurrentCall()
        let stoppedLoops = fixture.controller.receiveLoopStopCountForTesting
        await fixture.socket.setAutomaticEvents(ready: false)

        let startTask = Task { @MainActor in
            await fixture.controller.startNewCall()
        }
        await fixture.socket.waitForSentEvent(.sessionStart, count: 2)
        await fixture.socket.emitReady()
        await startTask.value

        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.activeReceiveLoopCountForTesting, 1)
        XCTAssertEqual(fixture.controller.receiveLoopStopCountForTesting, stoppedLoops)
        XCTAssertEqual(fixture.controller.protocolReadyEventCountForTesting, 2)
    }

    func testOnlyOneReceiveLoopExistsDuringReconnect() async {
        let fixture = makeFixture(reconnectDelays: [.milliseconds(1)])
        await fixture.controller.startNewCall()
        let initialReceiveStarts = fixture.controller.receiveLoopStartCountForTesting
        let abnormal = VoiceWebSocketErrorClassifier.classify(error: nil, closeCode: 1006)

        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        await waitUntil(timeout: .seconds(1)) {
            fixture.controller.state == .ready
                && !fixture.controller.hasReconnectTaskForTesting
                && fixture.controller.isRecording
        }

        XCTAssertEqual(fixture.controller.receiveLoopStartCountForTesting, initialReceiveStarts)
        XCTAssertEqual(fixture.controller.activeReceiveLoopCountForTesting, 1)
        XCTAssertEqual(fixture.controller.maxActiveReceiveLoopCountForTesting, 1)
    }

    func testEndThenImmediateStartReceivesNewReady() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let oldSession = fixture.controller.sessionIDForTesting
        let oldCaptureStarts = fixture.capture.startCount
        await fixture.controller.endCurrentCall()
        await fixture.socket.setAutomaticEvents(ready: false)

        let startTask = Task { @MainActor in
            await fixture.controller.startNewCall()
        }
        await fixture.socket.waitForSentEvent(.sessionStart, count: 2)
        await fixture.socket.emitReady()
        await startTask.value

        let sent = await fixture.socket.sentTypesValue()
        XCTAssertNotEqual(fixture.controller.sessionIDForTesting, oldSession)
        XCTAssertEqual(sent.filter { $0 == .sessionStart }.count, 2)
        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.capture.startCount, oldCaptureStarts + 1)
        XCTAssertEqual(fixture.controller.activeReceiveLoopCountForTesting, 1)
        XCTAssertEqual(fixture.controller.maxActiveReceiveLoopCountForTesting, 1)
    }

    func testMicrophoneDeniedBlocksConnectionAndRecording() async {
        let fixture = makeFixture(audioPermission: .denied)
        await fixture.controller.startNewCall()
        fixture.controller.startListening()
        XCTAssertEqual(fixture.controller.state, .failed)
        XCTAssertEqual(fixture.capture.startCount, 0)
        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, 0)
        XCTAssertTrue(fixture.controller.errorMessage.contains("麦克风权限"))
    }

    func testNonReadyPressSendsNoAudio() async {
        let fixture = makeFixture(autoReady: false, reconnectDelays: [], protocolReadyTimeout: .milliseconds(20))
        await fixture.controller.startNewCall()
        fixture.controller.startListening()
        fixture.capture.emit(Data(repeating: 0, count: 640))
        await settle()
        XCTAssertEqual(fixture.capture.startCount, 0)
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertFalse(sent.contains(.audioAppend))
    }

    func testPressStartsOnceAndReleaseCommitsOnce() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        fixture.controller.startListening()
        fixture.controller.startListening()
        XCTAssertEqual(fixture.capture.startCount, 1)
        await fixture.controller.finishPress(cancelled: false)
        await fixture.controller.finishPress(cancelled: false)
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertEqual(sent.filter { $0 == .audioCommit }.count, 1)
    }

    func testSlideOutPolicySafelyCommitsOnce() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        fixture.controller.startListening()
        await fixture.controller.finishPress(cancelled: true)
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertEqual(sent.filter { $0 == .audioCommit }.count, 1)
    }

    func testSpeakingAllowsInterruptAndOtherStatesDoNot() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        XCTAssertFalse(fixture.controller.canInterrupt)
        await fixture.socket.emitServerEvent(
            .responseStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string("synthetic-response")]
        )
        await waitUntil { fixture.controller.state == .speaking }
        XCTAssertTrue(fixture.controller.canInterrupt)
        await fixture.controller.interrupt()
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertTrue(sent.contains(.interrupt))
    }

    func testDiagnosticTextIsSanitized() async {
        let fixture = makeFixture(token: "synthetic-private-token")
        await fixture.controller.startNewCall()
        let fullSession = fixture.controller.sessionIDForTesting
        let fullTrace = fixture.controller.traceIDForTesting
        await fixture.socket.emitServerEvent(
            .transcriptFinal,
            sessionID: fullSession,
            traceID: fullTrace,
            payload: ["text": .string("synthetic-private-message")]
        )
        await settle()
        let diagnostics = fixture.controller.diagnosticText
        XCTAssertFalse(diagnostics.contains("synthetic-private-token"))
        XCTAssertFalse(diagnostics.contains("Authorization"))
        XCTAssertFalse(diagnostics.contains("synthetic-private-message"))
        XCTAssertFalse(diagnostics.contains(fullSession))
        XCTAssertFalse(diagnostics.contains(fullTrace))
        XCTAssertTrue(diagnostics.contains("session_hash="))
        XCTAssertTrue(diagnostics.contains("route=b"))
    }

    func testDiagnosticsSplitCommitToFirstAudioIntoObservableStages() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()

        await fixture.controller.commitAudio()
        try? await Task.sleep(for: .milliseconds(2))
        await fixture.socket.emitServerEvent(
            .transcriptFinal,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["text": .string("private transcript must not appear")]
        )
        try? await Task.sleep(for: .milliseconds(2))
        let responseID = "diagnostic-response"
        await fixture.socket.emitServerEvent(
            .responseStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string(responseID)]
        )
        try? await Task.sleep(for: .milliseconds(2))
        await fixture.socket.emitServerEvent(
            .responseAudioDelta,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: [
                "response_id": .string(responseID),
                "chunk_index": .int(0),
                "audio": .string(Data(repeating: 1, count: 640).base64EncodedString())
            ]
        )
        await settle()

        let diagnostics = fixture.controller.diagnosticText
        let latency = fixture.controller.latencyDiagnosticText
        XCTAssertTrue(diagnostics.contains("commit_to_transcript_final_ms="))
        XCTAssertTrue(diagnostics.contains("transcript_final_to_response_started_ms="))
        XCTAssertTrue(diagnostics.contains("response_started_to_first_audio_ms="))
        XCTAssertTrue(diagnostics.contains("network_ping_ms="))
        XCTAssertTrue(latency.contains("ASR / 上行"))
        XCTAssertTrue(latency.contains("模型 / 路由"))
        XCTAssertTrue(latency.contains("TTS / 下行"))
        XCTAssertTrue(latency.contains("当前最长阶段"))
        XCTAssertFalse(diagnostics.contains("private transcript must not appear"))
    }

    func testCloseCleansCapturePlaybackAudioAndTasks() async {
        let fixture = makeFixture(reconnectDelays: [.milliseconds(1)])
        await fixture.controller.startNewCall()
        fixture.controller.startListening()
        await fixture.controller.endCurrentCall()
        XCTAssertGreaterThan(fixture.capture.stopCount, 0)
        XCTAssertGreaterThan(fixture.playback.cancelCount, 0)
        XCTAssertFalse(fixture.audioSession.isActive)
        XCTAssertFalse(fixture.controller.hasReceiveTaskForTesting)
        XCTAssertFalse(fixture.controller.hasHeartbeatTaskForTesting)
        XCTAssertFalse(fixture.controller.hasReconnectTaskForTesting)
        let socketConnected = await fixture.socket.isConnected()
        XCTAssertFalse(socketConnected)
    }

    func testSessionReadyAutomaticallyStartsContinuousCapture() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.capture.startCount, 1)
        XCTAssertEqual(fixture.controller.vadState, .idleListening)
    }

    func testSilenceDoesNotSendAudioOrCommit() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        for _ in 0..<12 {
            fixture.capture.emit(pcmFrame(amplitude: 0))
        }
        await settle()
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertFalse(sent.contains(.audioAppend))
        XCTAssertFalse(sent.contains(.audioCommit))
    }

    func testValidSpeechAutomaticallySendsAndCommitsOnce() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 0))
        fixture.capture.emit(pcmFrame(amplitude: 0))
        fixture.capture.emit(pcmFrame(amplitude: 0))
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            let sent = await fixture.socket.sentTypesValue()
            if sent.contains(.audioAppend),
               sent.filter({ $0 == .audioCommit }).count == 1,
               fixture.controller.speechStartCount == 1,
               fixture.controller.automaticCommitCount == 1 {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertTrue(sent.contains(.audioAppend))
        XCTAssertEqual(sent.filter { $0 == .audioCommit }.count, 1)
        XCTAssertEqual(fixture.controller.speechStartCount, 1)
        XCTAssertEqual(fixture.controller.automaticCommitCount, 1)
    }

    func testResponseDoneReturnsToAutomaticListening() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await fixture.socket.emitServerEvent(
            .responseStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string("response-one")]
        )
        await fixture.socket.emitServerEvent(
            .responseAudioDone,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string("response-one")]
        )
        await settle()
        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.vadState, .idleListening)
    }

    func testSpeakingValidSpeechInterruptsBeforeNewAudio() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await fixture.socket.emitServerEvent(
            .responseStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string("response-barge")]
        )
        await settle()
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        await settle()
        let sent = await fixture.socket.sentTypesValue()
        guard let interruptIndex = sent.firstIndex(of: .interrupt),
              let appendIndex = sent.firstIndex(of: .audioAppend) else {
            return XCTFail("barge-in events missing")
        }
        XCTAssertLessThan(interruptIndex, appendIndex)
        XCTAssertEqual(sent.filter { $0 == .interrupt }.count, 1)
        XCTAssertEqual(fixture.controller.bargeInDetectionCount, 1)
    }

    func testServerPushAudioPlaysWithoutResponseNextPulls() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let responseID = "server-push-response"
        await fixture.socket.emitServerEvent(
            .responseStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string(responseID)]
        )
        await settle()
        var sent = await fixture.socket.sentEventsValue()
        let responseNextBeforeAudio = sent.filter { $0.type == .responseNext }.count
        XCTAssertEqual(responseNextBeforeAudio, 0)

        let audio = Data(repeating: 2, count: 640).base64EncodedString()
        await fixture.socket.emitServerEvent(
            .responseAudioDelta,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: [
                "response_id": .string(responseID),
                "chunk_index": .int(0),
                "audio": .string(audio)
            ]
        )
        await settle()
        sent = await fixture.socket.sentEventsValue()
        let responseNextCount = sent.filter { $0.type == .responseNext }.count
        let playbackCount = fixture.playback.enqueueCount
        let serverPushChunkCount = fixture.controller.serverPushAudioChunks
        let recordedResponseNextCount = fixture.controller.responseNextSentCount
        let diagnostics = fixture.controller.diagnosticText

        XCTAssertEqual(responseNextCount, 0)
        XCTAssertEqual(playbackCount, 1)
        XCTAssertEqual(serverPushChunkCount, 1)
        XCTAssertEqual(recordedResponseNextCount, 0)
        XCTAssertTrue(diagnostics.contains("response_next_sent_count=0"))
        XCTAssertTrue(diagnostics.contains("server_push_audio_chunks=1"))
    }

    func testLateInterruptedAudioIsIgnoredWithoutPlaybackOrOldPull() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let oldResponseID = "response-late-audio"
        await fixture.socket.emitServerEvent(
            .responseStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string(oldResponseID)]
        )
        await settle()

        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        await settle()

        let playbackBefore = fixture.playback.enqueueCount
        let sentBefore = await fixture.socket.sentEventsValue()
        let oldPullsBefore = responseNextCount(in: sentBefore, responseID: oldResponseID)
        let appendsBefore = sentBefore.filter { $0.type == .audioAppend }.count

        let lateAudio = Data(repeating: 1, count: 640).base64EncodedString()
        for index in 0..<3 {
            await fixture.socket.emitServerEvent(
                .responseAudioDelta,
                sessionID: fixture.controller.sessionIDForTesting,
                traceID: fixture.controller.traceIDForTesting,
                payload: [
                    "response_id": .string(oldResponseID),
                    "chunk_index": .int(index),
                    "audio": .string(lateAudio)
                ]
            )
        }
        await settle()

        let sentAfterLateAudio = await fixture.socket.sentEventsValue()
        XCTAssertEqual(fixture.playback.enqueueCount, playbackBefore)
        XCTAssertEqual(
            responseNextCount(in: sentAfterLateAudio, responseID: oldResponseID),
            oldPullsBefore
        )
        XCTAssertEqual(fixture.controller.ignoredInterruptedAudioChunks, 3)
        XCTAssertTrue(
            fixture.controller.state == .listening || fixture.controller.state == .processing
        )
        XCTAssertTrue(
            fixture.controller.diagnosticText.contains("ignored_interrupted_audio_chunks=3")
        )

        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        await settle()
        let sentAfterNewUserAudio = await fixture.socket.sentEventsValue()
        XCTAssertGreaterThan(
            sentAfterNewUserAudio.filter { $0.type == .audioAppend }.count,
            appendsBefore
        )
    }

    func testLateInterruptedDoneDoesNotEndNewUserTurn() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let oldResponseID = "response-late-done"
        await fixture.socket.emitServerEvent(
            .responseStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string(oldResponseID)]
        )
        await settle()

        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        await settle()
        let stateBeforeDone = fixture.controller.state
        let appendCountBeforeDone = (await fixture.socket.sentEventsValue())
            .filter { $0.type == .audioAppend }.count

        await fixture.socket.emitServerEvent(
            .responseAudioDone,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string(oldResponseID)]
        )
        await settle()

        XCTAssertEqual(fixture.controller.state, stateBeforeDone)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertTrue(
            fixture.controller.vadState == .sendingSpeech
                || fixture.controller.vadState == .endpointing
        )

        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        await settle()
        let appendCountAfterDone = (await fixture.socket.sentEventsValue())
            .filter { $0.type == .audioAppend }.count
        XCTAssertGreaterThan(appendCountAfterDone, appendCountBeforeDone)
    }

    func testSpeakingShortNoiseDoesNotInterrupt() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await fixture.socket.emitServerEvent(
            .responseStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string("response-noise")]
        )
        await settle()
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 0))
        fixture.capture.emit(pcmFrame(amplitude: 0))
        await settle()
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertFalse(sent.contains(.interrupt))
        XCTAssertEqual(fixture.controller.bargeInDetectionCount, 0)
    }

    func testMuteStopsSendingAndUnmuteRestoresListening() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await fixture.controller.setMuted(true)
        XCTAssertFalse(fixture.controller.isRecording)
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        fixture.capture.emit(pcmFrame(amplitude: 6_000))
        await settle()
        var sent = await fixture.socket.sentTypesValue()
        XCTAssertFalse(sent.contains(.audioAppend))

        await fixture.controller.setMuted(false)
        XCTAssertTrue(fixture.controller.isRecording)
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        await settle()
        sent = await fixture.socket.sentTypesValue()
        XCTAssertTrue(sent.contains(.audioAppend))
    }

    // MARK: P2.8A 静音恢复 (V1 稳定化)

    func testUnmuteInListeningStateRestoresCapture() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        // 服务器事件驱动进入 .listening
        await fixture.socket.emitServerEvent(
            .listeningStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting
        )
        await settle()
        XCTAssertEqual(fixture.controller.state, .listening)

        await fixture.controller.setMuted(true)
        XCTAssertFalse(fixture.controller.isRecording)
        await fixture.controller.setMuted(false)
        // .listening 状态允许恢复采集 (P2.8A)
        XCTAssertTrue(fixture.controller.isRecording)

        // 取消静音后继续发送音频
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        fixture.capture.emit(pcmFrame(amplitude: 3_000))
        await settle()
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertTrue(sent.contains(.audioAppend))
    }

    func testUnmuteDoesNotRecreateSessionOrIncreaseConnectCount() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        let sessionID = fixture.controller.sessionIDForTesting
        let initialConnectCount = await fixture.socket.connectCountValue()
        let initialPingCount = await fixture.socket.pingCountValue()

        await fixture.controller.setMuted(true)
        await fixture.controller.setMuted(false)

        XCTAssertEqual(fixture.controller.sessionIDForTesting, sessionID,
                       "正常取消静音不得重新建立 Session")
        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, initialConnectCount,
                       "正常取消静音不得增加 WebSocket connect 次数")
        let pingCount = await fixture.socket.pingCountValue()
        XCTAssertEqual(pingCount, initialPingCount + 1,
                       "正常取消静音必须先探测一次 WebSocket 活性")
        XCTAssertTrue(fixture.controller.isRecording)
    }

    func testUnmutePingFailureTriggersExistingReconnect() async {
        let fixture = makeFixture(autoResume: false, reconnectDelays: [.milliseconds(1)])
        await fixture.controller.startNewCall()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.webSocketState == .connected
        }
        let sessionID = fixture.controller.sessionIDForTesting

        await fixture.controller.setMuted(true)
        XCTAssertTrue(fixture.controller.isMuted)
        XCTAssertFalse(fixture.controller.isRecording)

        await fixture.socket.failNextPing()
        await fixture.controller.setMuted(false)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)

        XCTAssertFalse(fixture.controller.isRecording,
                       "半断开链路探测失败后必须等待 resume 成功再恢复采集")
        XCTAssertEqual(fixture.controller.sessionIDForTesting, sessionID,
                       "取消静音探测失败必须复用原 Session")
        XCTAssertEqual(fixture.controller.pingFailureCount, 1)

        await fixture.socket.emitResumed()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.webSocketState == .connected
                && fixture.controller.isRecording
        }
        XCTAssertEqual(fixture.controller.sessionIDForTesting, sessionID)
    }

    func testRepeatedUnmuteDoesNotRestartCaptureMultipleTimes() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await fixture.controller.setMuted(true)
        let initialCaptureStarts = fixture.capture.startCount

        // 重复设置相同静音状态 → 幂等, 不重复启动采集
        await fixture.controller.setMuted(false)
        await fixture.controller.setMuted(false)
        await fixture.controller.setMuted(false)

        XCTAssertEqual(fixture.capture.startCount, initialCaptureStarts + 1,
                       "重复取消静音不得重复启动采集")
    }

    func testUnmuteWithRecoverableDisconnectTriggersExistingReconnect() async {
        // 断开后 controller 会自动重连; 用较长 reconnectDelays 保持"断开可恢复"窗口,
        // 使下方 waitUntil(disconnected && lastDisconnectRecoverable) 在自动重连完成前成立.
        let fixture = makeFixture(reconnectDelays: [.milliseconds(1_000)])
        await fixture.controller.startNewCall()
        // 1. 等待 ready + connected
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.webSocketState == .connected
        }
        let initialSessionID = fixture.controller.sessionIDForTesting

        // 2. 先在连接正常时 setMuted(true) (避免断线后发送 mute 进入失败路径, 与重连形成竞态)
        await fixture.controller.setMuted(true)
        XCTAssertTrue(fixture.controller.isMuted)
        XCTAssertFalse(fixture.controller.isRecording, "静音后必须停止采集")
        let captureStartsBefore = fixture.capture.startCount

        // 3. 模拟可恢复断开
        let abnormal = VoiceWebSocketErrorClassifier.classify(
            error: URLError(.networkConnectionLost),
            closeCode: 1006
        )
        await fixture.socket.simulateDisconnect(abnormal)
        await waitUntil {
            fixture.controller.webSocketState == .disconnected
                && fixture.controller.lastDisconnectRecoverable
        }

        // 4. 取消静音 → 断连但可恢复 → 走现有重连 (session.resume, 不新建 Session)
        await fixture.controller.setMuted(false)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        // 5. 等 sessionResumed 后 ready + connected + 恢复采集
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.webSocketState == .connected
                && fixture.controller.isRecording
        }

        // 6. 断言: Session 复用 / 无新 session.start / resume 一次 / connect 1→2 / 终态正确
        XCTAssertEqual(fixture.controller.sessionIDForTesting, initialSessionID,
                       "可恢复断连重连必须复用原 Session, 不得新建")
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertEqual(sent.filter { $0 == .sessionStart }.count, 1,
                       "不得新增 session.start (不得新建 Session)")
        XCTAssertEqual(sent.filter { $0 == .sessionResume }.count, 1,
                       "session.resume 必须恰好出现一次")
        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, 2, "WebSocket connect count 必须从 1 变为 2")
        XCTAssertFalse(fixture.controller.isMuted, "最终必须处于取消静音状态")
        XCTAssertEqual(fixture.controller.state, .ready, "最终必须回到 .ready")
        XCTAssertEqual(fixture.controller.webSocketState, .connected, "最终必须已连接")
        XCTAssertTrue(fixture.controller.isRecording, "最终必须恢复采集")
        XCTAssertEqual(fixture.capture.startCount, captureStartsBefore + 1,
                       "取消静音后必须恰好重启一次采集")
    }

    func testUnmuteAfterIdleTimeoutDoesNotReconnect() async {
        let fixture = makeFixture(reconnectDelays: [.milliseconds(1)])
        await fixture.controller.startNewCall()
        await fixture.socket.emitServerEvent(
            .sessionEnded,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["reason": .string("idle_timeout")]
        )
        await waitUntil {
            fixture.controller.state == .closed
                && fixture.controller.webSocketState == .disconnected
        }
        await settle()

        let connectCountBefore = await fixture.socket.connectCountValue()
        // 空闲结束后取消静音 → 不得静默重连
        await fixture.controller.setMuted(false)
        await settle()
        let connectCountAfter = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCountAfter, connectCountBefore,
                       "空闲结束(idle_timeout)后取消静音不得重新连接")
        XCTAssertEqual(fixture.controller.state, .closed)
    }

    // MARK: P2.8A-CI-FIX-2 失败注入测试

    func testUnmuteSendFailureDoesNotRestoreCaptureUntilReconnect() async {
        // P2.8A-CI-FIX-3: autoResume = false, 手工 emitResumed 精确控制,
        // 不使用 settle() 观察短暂失败窗口
        let fixture = makeFixture(autoResume: false, reconnectDelays: [.milliseconds(1)])
        await fixture.controller.startNewCall()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.webSocketState == .connected
        }
        let initialSessionID = fixture.controller.sessionIDForTesting

        await fixture.controller.setMuted(true)
        XCTAssertTrue(fixture.controller.isMuted)
        XCTAssertFalse(fixture.controller.isRecording)

        // 注入: 连接内下一次 unmute 发送失败 → recordSendFailure → 现有重连流程
        await fixture.socket.failNextSend(.unmute)
        await fixture.controller.setMuted(false)
        await fixture.socket.waitForSentEvent(.sessionResume)

        // 手工 emitResumed 之前 (同步尚未成功): 失败不得恢复采集 / 不得提升 .ready / Session 不变
        XCTAssertFalse(fixture.controller.isRecording,
                       "unmute 发送失败后不得恢复采集 (仅同步成功后恢复)")
        XCTAssertNotEqual(fixture.controller.state, .ready,
                          "同步成功前不得提升 .ready")
        XCTAssertEqual(fixture.controller.sessionIDForTesting, initialSessionID,
                       "重连必须复用原 Session, 不得新建")

        // 手工 emitResumed → Resume 静音同步成功 → 提升 .ready 并恢复采集
        await fixture.socket.emitResumed()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.webSocketState == .connected
                && fixture.controller.isRecording
        }
        XCTAssertEqual(fixture.controller.sessionIDForTesting, initialSessionID,
                       "成功恢复后必须仍复用原 Session")
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertEqual(sent.filter { $0 == .unmute }.count, 1,
                       "成功 Resume 后 unmute 必须恰好发送一次 (注入失败不计入)")
        XCTAssertEqual(sent.filter { $0 == .sessionStart }.count, 1,
                       "不得新增 session.start")
    }

    func testResumeMuteSyncFailureDefersCaptureAndRetries() async {
        // P2.8A-CI-FIX-3: autoResume = false + 较短 protocolReadyTimeout,
        // 手工 emitResumed 精确控制第一次失败与第二次成功
        let fixture = makeFixture(
            autoResume: false,
            reconnectDelays: [.milliseconds(1), .milliseconds(1)],
            protocolReadyTimeout: .milliseconds(100)
        )
        await fixture.controller.startNewCall()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.webSocketState == .connected
        }
        let initialSessionID = fixture.controller.sessionIDForTesting

        // 静音 (断开前): isMuted == true, 停采
        await fixture.controller.setMuted(true)
        XCTAssertFalse(fixture.controller.isRecording)
        // 初始断言: 调用链至今 session.start 必须恰好 1 次 (本轮 startNewCall 唯一一次)
        let baselineSent = await fixture.socket.sentTypesValue()
        XCTAssertEqual(baselineSent.filter { $0 == .sessionStart }.count, 1,
                       "初始 session.start 必须恰好 1 次")
        // 基线清零: 排除初始 setMuted(true) 的 mute, 后续按增量断言
        await fixture.socket.clearSentEvents()

        // 可恢复断开 → 自动重连第一轮 → 第一次 session.resume 已发送 (不自动 emit)
        let abnormal = VoiceWebSocketErrorClassifier.classify(
            error: URLError(.networkConnectionLost),
            closeCode: 1006
        )
        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForSentEvent(.sessionResume, count: 1)

        // 第一次 sessionResumed 前注入 .mute 失败, 再手工 emitResumed
        await fixture.socket.failNextSend(.mute)
        await fixture.socket.emitResumed()

        // 等待现有重连循环发送第二次 session.resume (其发生即证明第一轮 sync 失败,
        // 无需依赖易变的 lastReasonCategory 窗口)
        await fixture.socket.waitForSentEvent(.sessionResume, count: 2)

        // 第一次失败后 (第二轮进行中, 尚未第二次 emitResumed):
        // 保持 .reconnecting / 不采集 / 静音保持
        XCTAssertEqual(fixture.controller.state, .reconnecting,
                       "Resume 同步失败必须保持 .reconnecting (不得提升 .ready)")
        XCTAssertFalse(fixture.controller.isRecording,
                       "Resume 同步失败不得恢复采集")
        XCTAssertTrue(fixture.controller.isMuted, "静音状态必须保持")

        // 手工 emitResumed → 第二次同步成功 → 提升 .ready
        await fixture.socket.emitResumed()
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.webSocketState == .connected
        }

        // 精确断言 (增量基线, 不含初始 mute)
        let sent = await fixture.socket.sentTypesValue()
        XCTAssertEqual(fixture.controller.sessionIDForTesting, initialSessionID,
                       "Resume 同步失败重试必须复用原 Session, 不得新建")
        XCTAssertEqual(sent.filter { $0 == .sessionStart }.count, 0,
                       "恢复过程中不得新增 session.start (清空后基线为 0)")
        XCTAssertEqual(sent.filter { $0 == .sessionResume }.count, 2,
                       "session.resume 必须恰好 2 次 (第一次失败 + 第二次成功)")
        XCTAssertEqual(sent.filter { $0 == .mute }.count, 1,
                       "失败后的成功 mute 同步必须恰好一次 (注入失败不计入)")
        XCTAssertEqual(fixture.controller.state, .ready, "最终必须 .ready")
        XCTAssertTrue(fixture.controller.isMuted, "静音必须保持")
        XCTAssertFalse(fixture.controller.isRecording, "静音状态下不得恢复采集")
    }

    // MARK: P2.8A ViewModel 启动幂等

    func testViewModelAppearTwiceStartsNewCallOnlyOnce() async {
        let fixture = makeFixture()
        let viewModel = VoiceCallViewModel(controller: fixture.controller)

        await viewModel.appear()
        let firstSessionID = fixture.controller.sessionIDForTesting
        let connectAfterFirst = await fixture.socket.connectCountValue()
        XCTAssertEqual(fixture.controller.state, .ready)

        // 连续第二次 appear (SwiftUI .task 重算场景) → 幂等, 不重复建立 Session
        await viewModel.appear()
        await settle()

        XCTAssertEqual(fixture.controller.sessionIDForTesting, firstSessionID,
                       "同一页面生命周期内重复 appear() 不得重建 Session")
        let connectAfterSecond = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectAfterSecond, connectAfterFirst,
                       "重复 appear() 不得增加 WebSocket connect 次数")
    }

    func testReconnectDoesNotCreateDuplicateCaptureTask() async {
        let fixture = makeFixture(reconnectDelays: [.milliseconds(1)])
        await fixture.controller.startNewCall()
        let initialCaptureStarts = fixture.capture.startCount
        let initialReceiveStarts = fixture.controller.receiveLoopStartCountForTesting
        let abnormal = VoiceWebSocketErrorClassifier.classify(error: nil, closeCode: 1006)
        await fixture.socket.simulateDisconnect(abnormal)
        await fixture.socket.waitForConnectCount(2)
        await fixture.socket.waitForSentEvent(.sessionResume)
        await waitUntil {
            fixture.controller.state == .ready
                && fixture.controller.reconnectAttempt == 0
                && !fixture.controller.hasReconnectTaskForTesting
                && fixture.controller.isRecording
        }
        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, 2)
        XCTAssertEqual(fixture.capture.startCount, initialCaptureStarts + 1)
        XCTAssertEqual(fixture.controller.receiveLoopStartCountForTesting, initialReceiveStarts)
        XCTAssertEqual(fixture.controller.activeReceiveLoopCountForTesting, 1)
        XCTAssertEqual(fixture.controller.maxActiveReceiveLoopCountForTesting, 1)
    }

    func testSingleAudioEngineUsedForCaptureAndPlayback() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()

        XCTAssertTrue(fixture.controller.usesSharedAudioIOForTesting)
        XCTAssertEqual(fixture.audio.engineStartCount, 1)
        XCTAssertEqual(fixture.audio.tapInstallCount, 1)
    }

    func testDiagnosticsReportRealtimeCaptureHealth() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()
        fixture.audio.emit(pcmFrame(amplitude: 0))
        await waitUntil { fixture.audio.callbackCount == 1 }
        let diagnostics = fixture.controller.diagnosticText

        XCTAssertTrue(diagnostics.contains("capture_engine_running=true"))
        XCTAssertTrue(diagnostics.contains("capture_tap_installed=true"))
        XCTAssertTrue(diagnostics.contains("capture_callback_count=1"))
        XCTAssertTrue(diagnostics.contains("last_capture_callback_age_ms="))
        XCTAssertTrue(diagnostics.contains("capture_restart_count=0"))
        XCTAssertTrue(diagnostics.contains("audio_engine_start_count=1"))
    }

    func testCaptureContinuesWhilePlaybackIsActive() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()
        let responseID = "full-duplex-response"
        await emitAssistantAudio(fixture, responseID: responseID, done: false)
        XCTAssertEqual(fixture.controller.state, .speaking)
        XCTAssertGreaterThan(fixture.audio.enqueueCount, 0)

        let appendCountBefore = (await fixture.socket.sentEventsValue())
            .filter { $0.type == .audioAppend }.count
        async let interruptSent = fixture.socket.waitForSentEvent(
            .interrupt,
            count: 1,
            timeout: .seconds(2)
        )
        async let nextAudioAppendSent = fixture.socket.waitForSentEvent(
            .audioAppend,
            count: appendCountBefore + 1,
            timeout: .seconds(2)
        )

        emitBargeInUtterance(using: fixture.audio)
        let (didSendInterrupt, didSendNextAudioAppend) = await (
            interruptSent,
            nextAudioAppendSent
        )
        XCTAssertTrue(didSendInterrupt, "interrupt was not sent within 2 seconds")
        XCTAssertTrue(
            didSendNextAudioAppend,
            "a new audio.append was not sent within 2 seconds"
        )

        let appendCountAfter = (await fixture.socket.sentEventsValue())
            .filter { $0.type == .audioAppend }.count
        XCTAssertEqual(fixture.controller.bargeInDetectionCount, 1)
        XCTAssertGreaterThan(appendCountAfter, appendCountBefore)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertTrue(fixture.audio.tapInstalled)

        await fixture.controller.endCurrentCall()
    }

    func testPlaybackDoesNotStopInputTap() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()
        let tapInstallsBefore = fixture.audio.tapInstallCount
        let stopCountBefore = fixture.audio.stopCount

        await emitAssistantAudio(fixture, responseID: "playback-keeps-tap", done: true)

        XCTAssertTrue(fixture.audio.engineRunning)
        XCTAssertTrue(fixture.audio.tapInstalled)
        XCTAssertEqual(fixture.audio.tapInstallCount, tapInstallsBefore)
        XCTAssertEqual(fixture.audio.stopCount, stopCountBefore)
    }

    func testSecondUtteranceWorksAfterFirstResponseDone() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()

        emitValidUtterance(using: fixture.audio)
        await waitUntil { fixture.controller.automaticCommitCount == 1 }
        let firstAppendCount = (await fixture.socket.sentEventsValue())
            .filter { $0.type == .audioAppend }.count
        await emitAssistantAudio(fixture, responseID: "turn-1", done: true)

        emitValidUtterance(using: fixture.audio)
        await waitUntil { fixture.controller.automaticCommitCount == 2 }
        let events = await fixture.socket.sentEventsValue()
        let connectCount = await fixture.socket.connectCountValue()

        XCTAssertEqual(fixture.controller.speechStartCount, 2)
        XCTAssertEqual(fixture.controller.automaticCommitCount, 2)
        XCTAssertGreaterThan(events.filter { $0.type == .audioAppend }.count, firstAppendCount)
        XCTAssertEqual(events.filter { $0.type == .audioCommit }.count, 2)
        XCTAssertEqual(connectCount, 1)
        XCTAssertEqual(fixture.controller.reconnectAttempt, 0)
        XCTAssertTrue(fixture.controller.isRecording)
    }

    func testCaptureStallRestartsAudioWithoutWebSocketReconnect() async {
        let fixture = makeSharedAudioFixture(
            captureWatchdogInterval: .milliseconds(5),
            captureStallThreshold: .milliseconds(200)
        )
        await fixture.controller.startNewCall()
        let recoverCountBefore = fixture.audio.recoverCount
        let callbackCountBefore = fixture.audio.callbackCount
        fixture.audio.simulateCaptureStall()

        await waitUntil { fixture.audio.recoverCount == recoverCountBefore + 1 }
        fixture.audio.emit(pcmFrame(amplitude: 3_000))
        await waitUntil { fixture.audio.callbackCount > callbackCountBefore }
        let connectCount = await fixture.socket.connectCountValue()

        XCTAssertEqual(connectCount, 1)
        XCTAssertEqual(fixture.audio.restartCount, 1)
        XCTAssertEqual(fixture.audio.recoverCount, recoverCountBefore + 1)
        XCTAssertTrue(fixture.audio.engineRunning)
        XCTAssertTrue(fixture.audio.tapInstalled)
        XCTAssertTrue(fixture.controller.isRecording)
    }

    func testCaptureWatchdogStopsAfterTwoFailedRecoveries() async {
        let fixture = makeSharedAudioFixture(
            captureWatchdogInterval: .milliseconds(5),
            captureStallThreshold: .milliseconds(10)
        )
        await fixture.controller.startNewCall()
        fixture.audio.shouldFailRecovery = true
        fixture.audio.simulateCaptureStall()

        await waitUntil { fixture.controller.state == .failed }
        let connectCount = await fixture.socket.connectCountValue()

        XCTAssertEqual(fixture.audio.recoverCount, 2)
        XCTAssertEqual(connectCount, 1)
        XCTAssertFalse(fixture.controller.hasReconnectTaskForTesting)
        XCTAssertFalse(fixture.controller.hasCaptureWatchdogTaskForTesting)
        XCTAssertTrue(
            fixture.controller.diagnosticText.contains(
                "last_error_category=local_audio_capture_stalled"
            )
        )
    }

    func testMuteStopsInputWithoutStoppingPlaybackEngine() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()
        await emitAssistantAudio(fixture, responseID: "mute-playback", done: false)
        let cancelCountBefore = fixture.audio.cancelCount

        await fixture.controller.setMuted(true)

        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertFalse(fixture.audio.tapInstalled)
        XCTAssertTrue(fixture.audio.engineRunning)
        XCTAssertEqual(fixture.audio.cancelCount, cancelCountBefore)
        XCTAssertGreaterThan(fixture.audio.enqueueCount, 0)
    }

    func testCaptureWatchdogDisabledWhileMuted() async {
        let fixture = makeSharedAudioFixture(
            captureWatchdogInterval: .milliseconds(5),
            captureStallThreshold: .milliseconds(200)
        )
        await fixture.controller.startNewCall()
        let recoverCountBefore = fixture.audio.recoverCount
        await fixture.controller.setMuted(true)
        fixture.audio.simulateCaptureStall()
        await drainTasks()

        XCTAssertFalse(fixture.controller.hasCaptureWatchdogTaskForTesting)
        XCTAssertEqual(fixture.audio.recoverCount, recoverCountBefore)
        XCTAssertFalse(fixture.controller.isRecording)
    }

    func testAudioInterruptionRecoversCurrentCall() async {
        let fixture = makeSharedAudioFixture(
            captureWatchdogInterval: .milliseconds(5),
            captureStallThreshold: .milliseconds(200)
        )
        await fixture.controller.startNewCall()
        let recoverCountBefore = fixture.audio.recoverCount
        let callbackCountBefore = fixture.audio.callbackCount
        fixture.audio.simulateInterruptionBegan()
        await drainTasks()
        XCTAssertEqual(fixture.audio.recoverCount, recoverCountBefore)

        fixture.audio.simulateInterruptionEnded()
        fixture.audio.emit(pcmFrame(amplitude: 3_000))
        await waitUntil { fixture.audio.callbackCount > callbackCountBefore }
        let connectCount = await fixture.socket.connectCountValue()

        XCTAssertEqual(connectCount, 1)
        XCTAssertTrue(fixture.audio.engineRunning)
        XCTAssertTrue(fixture.audio.tapInstalled)
        XCTAssertTrue(fixture.controller.isRecording)
    }

    func testInputTapIsNeverInstalledTwice() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()
        fixture.controller.startListening()
        await emitAssistantAudio(fixture, responseID: "tap-once", done: true)
        fixture.controller.startListening()

        XCTAssertEqual(fixture.audio.tapInstallCount, 1)
        XCTAssertEqual(fixture.audio.engineStartCount, 1)
    }

    func testFiveTurnConversationKeepsCaptureAlive() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()

        for turn in 1...5 {
            emitValidUtterance(using: fixture.audio)
            await waitUntil { fixture.controller.automaticCommitCount == turn }
            await emitAssistantAudio(fixture, responseID: "turn-\(turn)", done: true)
        }

        let events = await fixture.socket.sentEventsValue()
        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(fixture.controller.speechStartCount, 5)
        XCTAssertEqual(fixture.controller.automaticCommitCount, 5)
        XCTAssertEqual(events.filter { $0.type == .audioCommit }.count, 5)
        XCTAssertGreaterThan(events.filter { $0.type == .audioAppend }.count, 5)
        XCTAssertEqual(connectCount, 1)
        XCTAssertEqual(fixture.controller.reconnectAttempt, 0)
        XCTAssertEqual(fixture.controller.serverPushAudioChunks, 15)
        XCTAssertEqual(fixture.audio.enqueueCount, 15)
        XCTAssertGreaterThanOrEqual(fixture.audio.callbackCount, 25)
        XCTAssertFalse(events.contains { $0.type == .responseNext })
        XCTAssertTrue(fixture.controller.diagnosticText.contains("reconnect_count=0"))
        XCTAssertTrue(fixture.controller.diagnosticText.contains("provider_error_count=0"))
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertTrue(fixture.audio.engineRunning)
        XCTAssertTrue(fixture.audio.tapInstalled)
    }

    func testEndingCallStopsSharedAudioEngine() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()
        await emitAssistantAudio(fixture, responseID: "ending-call", done: false)
        let shutdownCountBefore = fixture.audio.shutdownCount

        await fixture.controller.endCurrentCall()

        XCTAssertEqual(fixture.controller.state, .closed)
        XCTAssertFalse(fixture.audio.engineRunning)
        XCTAssertFalse(fixture.audio.tapInstalled)
        XCTAssertEqual(fixture.audio.shutdownCount, shutdownCountBefore + 1)
        XCTAssertFalse(fixture.controller.hasCaptureWatchdogTaskForTesting)
    }

    func testRouteRemainsBForHandsFreeForeground() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        XCTAssertEqual(fixture.controller.route, .b)
    }

    func testResponseDoneRecoversStalledCaptureWithoutChangingSession() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()
        fixture.audio.emit(pcmFrame(amplitude: 0))
        let sessionID = fixture.controller.sessionIDForTesting

        fixture.audio.simulateCaptureStall()
        await emitAssistantAudio(fixture, responseID: "response-stalled", done: true)

        await waitUntil(timeout: .seconds(1)) {
            fixture.audio.recoverCount == 1
                && fixture.controller.postResponseCaptureRecoveryCount == 1
        }
        XCTAssertEqual(fixture.controller.sessionIDForTesting, sessionID)
        let connectCount = await fixture.socket.connectCountValue()
        XCTAssertEqual(connectCount, 1)
        XCTAssertTrue(fixture.audio.engineRunning)
        XCTAssertTrue(fixture.audio.tapInstalled)
    }

    func testResponseDoneDoesNotRecoverWhenCaptureCallbacksContinue() async {
        let fixture = makeSharedAudioFixture()
        await fixture.controller.startNewCall()
        fixture.audio.emit(pcmFrame(amplitude: 0))
        let sessionID = fixture.controller.sessionIDForTesting

        await emitAssistantAudio(fixture, responseID: "response-healthy", done: true)
        try? await Task.sleep(for: .milliseconds(100))
        fixture.audio.emit(pcmFrame(amplitude: 0))
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(fixture.controller.sessionIDForTesting, sessionID)
        XCTAssertEqual(fixture.audio.recoverCount, 0)
        XCTAssertEqual(fixture.controller.postResponseCaptureRecoveryCount, 0)
        XCTAssertGreaterThan(fixture.controller.diagnosticText.count, 0)
    }

    private func makeFixture(
        token: String = "synthetic-token",
        autoReady: Bool = true,
        autoResume: Bool = true,
        autoLifecycleConnected: Bool = true,
        audioPermission: MicrophonePermissionState = .granted,
        reconnectDelays: [Duration] = [.milliseconds(1), .milliseconds(1)],
        protocolReadyTimeout: Duration = .milliseconds(200)
    ) -> Fixture {
        let socket = TestVoiceWebSocketClient(
            autoReady: autoReady,
            autoResume: autoResume,
            autoLifecycleConnected: autoLifecycleConnected
        )
        let capture = TestCapture()
        let playback = TestPlayback()
        _ = token
        let audioSession = TestAudioSession(permission: audioPermission)
        let controller = VoiceSessionController(
            environment: AppEnvironment(
                apiBaseURL: URL(string: "https://api.example.test"),
                voiceWebSocketURL: URL(string: "wss://voice.example.test/v1/voice/ws"),
                deviceID: "test-device",
                appEnvironment: "test",
                enableMockVoice: false,
                enableMemory: false,
                defaultVoiceRoute: .b,
                appBuildSHA: "test-sha",
                appBuildTime: "2026-07-30T00:00:00Z"
            ),
            socket: socket,
            capture: capture,
            playback: playback,
            audioSession: audioSession,
            networkMonitor: TestNetworkMonitor(),
            reconnectDelays: reconnectDelays,
            protocolReadyTimeout: protocolReadyTimeout,
            voiceActivityConfiguration: testVADConfiguration
        )
        addTeardownBlock { [controller] in
            await controller.endCurrentCall()
        }
        return Fixture(
            controller: controller,
            socket: socket,
            capture: capture,
            playback: playback,
            audioSession: audioSession
        )
    }

    private func makeSharedAudioFixture(
        captureWatchdogInterval: Duration = .seconds(3_600),
        captureStallThreshold: Duration = .seconds(7_200)
    ) -> SharedAudioFixture {
        let socket = TestVoiceWebSocketClient(
            autoReady: true,
            autoResume: true,
            autoLifecycleConnected: true
        )
        let audio = TestRealtimeAudioIO()
        let audioSession = TestAudioSession(permission: .granted)
        let controller = VoiceSessionController(
            environment: AppEnvironment(
                apiBaseURL: URL(string: "https://api.example.test"),
                voiceWebSocketURL: URL(string: "wss://voice.example.test/v1/voice/ws"),
                deviceID: "test-device",
                appEnvironment: "test",
                enableMockVoice: false,
                enableMemory: false,
                defaultVoiceRoute: .b,
                appBuildSHA: "test-sha",
                appBuildTime: "2026-07-30T00:00:00Z"
            ),
            socket: socket,
            capture: audio,
            playback: audio,
            audioSession: audioSession,
            networkMonitor: TestNetworkMonitor(),
            reconnectDelays: [.milliseconds(1)],
            protocolReadyTimeout: .milliseconds(200),
            voiceActivityConfiguration: testVADConfiguration,
            captureWatchdogInterval: captureWatchdogInterval,
            captureStallThreshold: captureStallThreshold
        )
        addTeardownBlock { [controller] in
            await controller.endCurrentCall()
        }
        return SharedAudioFixture(
            controller: controller,
            socket: socket,
            audio: audio,
            audioSession: audioSession
        )
    }

    private func emitValidUtterance(using audio: TestRealtimeAudioIO) {
        audio.emit(pcmFrame(amplitude: 3_000))
        audio.emit(pcmFrame(amplitude: 3_000))
        audio.emit(pcmFrame(amplitude: 0))
        audio.emit(pcmFrame(amplitude: 0))
        audio.emit(pcmFrame(amplitude: 0))
    }

    private func emitBargeInUtterance(using audio: TestRealtimeAudioIO) {
        audio.emit(pcmFrame(amplitude: 6_000))
        audio.emit(pcmFrame(amplitude: 6_000))
        audio.emit(pcmFrame(amplitude: 6_000))
    }

    private func emitAssistantAudio(
        _ fixture: SharedAudioFixture,
        responseID: String,
        done: Bool
    ) async {
        await fixture.socket.emitServerEvent(
            .responseStarted,
            sessionID: fixture.controller.sessionIDForTesting,
            traceID: fixture.controller.traceIDForTesting,
            payload: ["response_id": .string(responseID)]
        )
        let audio = Data(repeating: 2, count: 640).base64EncodedString()
        for index in 0..<3 {
            await fixture.socket.emitServerEvent(
                .responseAudioDelta,
                sessionID: fixture.controller.sessionIDForTesting,
                traceID: fixture.controller.traceIDForTesting,
                payload: [
                    "response_id": .string(responseID),
                    "chunk_index": .int(index),
                    "audio": .string(audio)
                ]
            )
        }
        if done {
            await fixture.socket.emitServerEvent(
                .responseAudioDone,
                sessionID: fixture.controller.sessionIDForTesting,
                traceID: fixture.controller.traceIDForTesting,
                payload: ["response_id": .string(responseID)]
            )
            await waitUntil {
                fixture.controller.state == .ready
                    && fixture.audio.enqueueCount >= 3
            }
        } else {
            await waitUntil {
                fixture.controller.state == .speaking
                    && fixture.audio.enqueueCount >= 3
            }
        }
    }

    private var testVADConfiguration: VoiceActivityConfiguration {
        VoiceActivityConfiguration(
            sampleRate: 16_000,
            bytesPerSample: 2,
            preRollMilliseconds: 40,
            minimumSpeechMilliseconds: 40,
            bargeInMinimumSpeechMilliseconds: 60,
            candidateAbortSilenceMilliseconds: 40,
            endSilenceMilliseconds: 40,
            maximumUtteranceMilliseconds: 200,
            speechRMSThreshold: 0.02,
            bargeInRMSThreshold: 0.08
        )
    }

    private func audioChunkIndexes(in events: [VoiceEvent]) -> [Int] {
        events.compactMap { event in
            guard event.type == .audioAppend,
                  case .int(let value) = event.payload["chunk_index"] else {
                return nil
            }
            return value
        }
    }

    private func responseNextCount(
        in events: [VoiceEvent],
        responseID: String
    ) -> Int {
        events.filter { event in
            guard event.type == .responseNext,
                  case .string(let value) = event.payload["response_id"] else {
                return false
            }
            return value == responseID
        }.count
    }

    private func pcmFrame(amplitude: Int16) -> Data {
        var samples = Array(repeating: amplitude, count: 320)
        return samples.withUnsafeBytes { Data($0) }
    }


    // P2.6C-REPAIR A: 重复挂断只发送一次 sessionEnd
    func testHangupSendsSessionEndExactlyOnce() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await fixture.controller.endCurrentCall()
        // 再次调用 endCurrentCall (URL scheme + onDisappear 双路径模拟) 不得重复发送
        await fixture.controller.endCurrentCall()
        let sentTypes = await fixture.socket.sentTypesValue()
        let endCount = sentTypes.filter { $0 == .sessionEnd }.count
        XCTAssertEqual(endCount, 1)
        XCTAssertEqual(fixture.controller.state, .closed)
    }

    // P2.6C-REPAIR B: 正常前后台切换不重复启动资源 (后台持续通话设计)
    func testForegroundWhileConnectedDoesNotRestartCaptureOrReconnect() async {
        let fixture = makeFixture()
        await fixture.controller.startNewCall()
        await waitUntil {
            fixture.controller.state == .ready && fixture.controller.webSocketState == .connected
        }
        XCTAssertTrue(fixture.controller.isRecording)
        let initialStarts = fixture.capture.startCount
        let initialStops = fixture.capture.stopCount
        let initialConnects = await fixture.socket.connectCountValue()

        await fixture.controller.appDidEnterBackground()
        await fixture.controller.appWillEnterForeground()

        XCTAssertEqual(fixture.controller.state, .ready)
        XCTAssertEqual(fixture.controller.webSocketState, .connected)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.capture.startCount, initialStarts, "后台持续通话: 回前台不得重启采集")
        XCTAssertEqual(fixture.capture.stopCount, initialStops, "后台持续通话: 不得停止采集")
        let finalConnects = await fixture.socket.connectCountValue()
        XCTAssertEqual(finalConnects, initialConnects, "连接正常: 回前台不得重连")
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(30))
    }

    private func drainTasks() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }

    private func waitUntil(
        timeout: Duration = .milliseconds(500),
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition timed out")
    }
}

@MainActor
private struct Fixture {
    let controller: VoiceSessionController
    let socket: TestVoiceWebSocketClient
    let capture: TestCapture
    let playback: TestPlayback
    let audioSession: TestAudioSession
}

@MainActor
private struct SharedAudioFixture {
    let controller: VoiceSessionController
    let socket: TestVoiceWebSocketClient
    let audio: TestRealtimeAudioIO
    let audioSession: TestAudioSession
}

private final class TestTokenStore: AuthTokenStoring, @unchecked Sendable {
    private var token: String?
    init(token: String) { self.token = token }
    func load() -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func clear() throws { token = nil }
}

private final class TestCapture: AudioCapturing {
    var onPacket: ((CapturedAudioPacket) -> Void)?
    private(set) var captureGeneration = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() throws {
        startCount += 1
        captureGeneration &+= 1
    }
    func stop() {
        stopCount += 1
        captureGeneration &+= 1
    }
    func emit(_ data: Data) {
        onPacket?(.pcm16(data, captureGeneration: captureGeneration))
    }
}

private final class TestPlayback: AudioPlaying {
    private(set) var enqueueCount = 0
    private(set) var cancelCount = 0
    func enqueue(_ data: Data, responseID: String, chunkIndex: Int) {
        _ = data
        _ = responseID
        _ = chunkIndex
        enqueueCount += 1
    }
    func cancel(responseID: String?) {
        _ = responseID
        cancelCount += 1
    }
}

private final class TestRealtimeAudioIO: AudioCapturing, AudioPlaying, RealtimeAudioIOHealthReporting {
    var onPacket: ((CapturedAudioPacket) -> Void)?
    private(set) var captureGeneration = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var enqueueCount = 0
    private(set) var cancelCount = 0
    private(set) var recoverCount = 0
    private(set) var shutdownCount = 0
    private(set) var tapInstallCount = 0
    private(set) var callbackCount = 0
    private(set) var restartCount = 0
    private(set) var engineStartCount = 0
    private(set) var engineStopCount = 0
    private(set) var playbackStartCount = 0
    private(set) var interruptionCount = 0
    private(set) var configurationChangeCount = 0
    var shouldFailRecovery = false
    private(set) var engineRunning = false
    private(set) var tapInstalled = false
    private var captureRequested = false
    private var interrupted = false
    private var lastCallbackAt: Date?
    private var currentResponseID = ""

    var healthSnapshot: RealtimeAudioIOHealthSnapshot {
        RealtimeAudioIOHealthSnapshot(
            captureEngineRunning: engineRunning,
            captureTapInstalled: tapInstalled,
            captureCallbackCount: callbackCount,
            lastCaptureCallbackAt: lastCallbackAt,
            captureRestartCount: restartCount,
            audioEngineStartCount: engineStartCount,
            audioEngineStopCount: engineStopCount,
            playbackStartCount: playbackStartCount,
            audioInterruptionCount: interruptionCount,
            engineConfigurationChangeCount: configurationChangeCount,
            isInterrupted: interrupted
        )
    }

    func start() throws {
        captureRequested = true
        startCount += 1
        if !engineRunning {
            engineRunning = true
            engineStartCount += 1
        }
        if !tapInstalled {
            tapInstalled = true
            tapInstallCount += 1
            captureGeneration &+= 1
        }
    }

    func stop() {
        stopCount += 1
        captureRequested = false
        tapInstalled = false
        captureGeneration &+= 1
    }

    func enqueue(_ data: Data, responseID: String, chunkIndex: Int) {
        _ = data
        _ = chunkIndex
        enqueueCount += 1
        if currentResponseID != responseID {
            currentResponseID = responseID
            playbackStartCount += 1
        }
    }

    func cancel(responseID: String?) {
        _ = responseID
        cancelCount += 1
        currentResponseID = ""
    }

    func recoverCapture() throws {
        recoverCount += 1
        if shouldFailRecovery {
            throw AppError.audio("synthetic_capture_recovery_failed")
        }
        restartCount += 1
        captureRequested = true
        if !engineRunning {
            engineRunning = true
            engineStartCount += 1
        }
        if !tapInstalled {
            tapInstalled = true
            tapInstallCount += 1
            captureGeneration &+= 1
        }
    }

    func shutdownAudioIO() {
        shutdownCount += 1
        captureRequested = false
        tapInstalled = false
        captureGeneration &+= 1
        if engineRunning {
            engineRunning = false
            engineStopCount += 1
        }
        currentResponseID = ""
    }

    func emit(_ data: Data) {
        guard captureRequested, engineRunning, tapInstalled, !interrupted else { return }
        callbackCount += 1
        lastCallbackAt = Date()
        onPacket?(.pcm16(data, captureGeneration: captureGeneration))
    }

    func simulateCaptureStall() {
        engineRunning = false
        tapInstalled = false
        lastCallbackAt = Date(timeIntervalSinceNow: -10)
    }

    func simulateInterruptionBegan() {
        interruptionCount += 1
        interrupted = true
        engineRunning = false
        tapInstalled = false
    }

    func simulateInterruptionEnded() {
        interrupted = false
        if captureRequested {
            engineRunning = true
            tapInstalled = true
            captureGeneration &+= 1
        }
    }
}

@MainActor
private final class TestAudioSession: AudioSessionControlling {
    var permissionState: MicrophonePermissionState
    private(set) var isActive = false
    private(set) var routeDescription = "Test Speaker"
    init(permission: MicrophonePermissionState) { permissionState = permission }
    func requestPermission() async -> Bool { permissionState == .granted }
    func activate() throws { isActive = true }
    func deactivate() { isActive = false }
    func refreshRoute() {}
}

@MainActor
private final class TestNetworkMonitor: NetworkMonitoring {
    var connectionType: NetworkConnectionType = .wifi
    func start() {}
    func stop() {}
}

private actor TestVoiceWebSocketClient: VoiceAdapter {
    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>
    private nonisolated let eventBroadcaster = BoundedAsyncStreamBroadcaster<VoiceEvent>(bufferLimit: 256)
    private let lifecycleContinuation: AsyncStream<VoiceWebSocketLifecycleEvent>.Continuation
    private var autoReady: Bool
    private var autoResume: Bool
    private var autoLifecycleConnected: Bool
    private var connected = false
    private var connectCount = 0
    private var serverSequence = 0
    private var sentTypes: [VoiceEventType] = []
    private var sentEvents: [VoiceEvent] = []
    // P2.8A-CI-FIX-2: 失败注入 — 指定类型的下一条 send 抛错 (消费后移除)
    private var failNextSendTypes: [VoiceEventType] = []
    private var shouldFailNextPing = false
    private var pingCount = 0
    private var lastSessionStart: VoiceEvent?
    private var lastSessionResume: VoiceEvent?
    private var connectWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var sentEventWaiters: [(type: VoiceEventType, count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(autoReady: Bool, autoResume: Bool, autoLifecycleConnected: Bool) {
        self.autoReady = autoReady
        self.autoResume = autoResume
        self.autoLifecycleConnected = autoLifecycleConnected
        let lifecyclePair = AsyncStream<VoiceWebSocketLifecycleEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        lifecycleEvents = lifecyclePair.stream
        lifecycleContinuation = lifecyclePair.continuation
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> {
        eventBroadcaster.makeStream()
    }

    func connect() async throws {
        connectCount += 1
        connected = true
        lifecycleContinuation.yield(.connecting)
        if autoLifecycleConnected {
            lifecycleContinuation.yield(.connected)
        }
        resumeConnectWaiters()
    }

    func connect(url: URL, token: String, deviceID: String) async throws {
        _ = url
        _ = token
        _ = deviceID
        try await connect()
    }

    func send(_ event: VoiceEvent) async throws {
        guard connected else { throw AppError.networkUnavailable }
        // P2.8A-CI-FIX-2: 失败注入 — 命中指定类型时抛错且不记录 (消费后移除)
        if let idx = failNextSendTypes.firstIndex(of: event.type) {
            failNextSendTypes.remove(at: idx)
            throw AppError.networkUnavailable
        }
        sentTypes.append(event.type)
        sentEvents.append(event)
        if event.type == .sessionStart {
            lastSessionStart = event
            if autoReady { emit(.sessionReady, event: event) }
        } else if event.type == .sessionResume {
            lastSessionResume = event
            if autoResume {
                emit(
                    .sessionResumed,
                    event: event,
                    payload: [
                        "provider_session_recreated": .bool(true),
                        "audio_chunk_index_reset": .bool(true),
                        "next_audio_chunk_index": .int(0)
                    ]
                )
            }
        } else if event.type == .interrupt {
            var payload: [String: JSONValue] = ["success": .bool(true)]
            if let responseID = event.payload["response_id"] {
                payload["response_id"] = responseID
            }
            emit(.interrupted, event: event, payload: payload)
        } else if event.type == .sessionEnd {
            emit(.sessionClosed, event: event)
        }
        resumeSentEventWaiters()
    }

    func ping() async throws {
        guard connected else { throw AppError.networkUnavailable }
        pingCount += 1
        if shouldFailNextPing {
            shouldFailNextPing = false
            throw AppError.networkUnavailable
        }
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

    func snapshot() async -> VoiceAdapterSnapshot {
        VoiceAdapterSnapshot(
            mode: .mock,
            isConnected: connected,
            connectCallCount: connectCount,
            sendCallCount: sentEvents.count,
            disconnectCallCount: 0,
            networkConnectionCount: 0
        )
    }

    func simulateDisconnect(_ info: VoiceWebSocketDisconnectInfo) {
        connected = false
        lifecycleContinuation.yield(.disconnected(info))
    }

    func simulateFailure(_ info: VoiceWebSocketDisconnectInfo) {
        connected = false
        lifecycleContinuation.yield(.failed(info))
    }

    func emitStaleDisconnect(_ info: VoiceWebSocketDisconnectInfo) {
        lifecycleContinuation.yield(.disconnected(info))
    }

    func emitServerEvent(
        _ type: VoiceEventType,
        sessionID: String,
        traceID: String,
        payload: [String: JSONValue] = [:]
    ) {
        serverSequence += 1
        eventBroadcaster.yield(VoiceEvent(
            version: VoiceEvent.protocolVersion,
            eventID: UUID().uuidString,
            traceID: traceID,
            sessionID: sessionID,
            sequence: serverSequence,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: type,
            payload: payload
        ))
    }

    func setAutomaticEvents(
        ready: Bool? = nil,
        resume: Bool? = nil,
        lifecycleConnected: Bool? = nil
    ) {
        if let ready { autoReady = ready }
        if let resume { autoResume = resume }
        if let lifecycleConnected { autoLifecycleConnected = lifecycleConnected }
    }

    func emitConnected() {
        lifecycleContinuation.yield(.connected)
    }

    func emitReady() {
        guard let event = lastSessionStart else { return }
        emit(.sessionReady, event: event)
    }

    func emitResumed() {
        guard let event = lastSessionResume else { return }
        emit(
            .sessionResumed,
            event: event,
            payload: [
                "provider_session_recreated": .bool(true),
                "audio_chunk_index_reset": .bool(true),
                "next_audio_chunk_index": .int(0)
            ]
        )
    }

    func waitForConnectCount(_ target: Int) async {
        if connectCount >= target { return }
        await withCheckedContinuation { continuation in
            connectWaiters.append((target, continuation))
        }
    }

    func waitForSentEvent(_ type: VoiceEventType, count: Int = 1) async {
        if sentTypes.filter({ $0 == type }).count >= count { return }
        await withCheckedContinuation { continuation in
            sentEventWaiters.append((type, count, continuation))
        }
    }

    func waitForSentEvent(
        _ type: VoiceEventType,
        count: Int,
        timeout: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if sentTypes.filter({ $0 == type }).count >= count {
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return false
            }
        }
        return sentTypes.filter({ $0 == type }).count >= count
    }

    func clearSentEvents() {
        sentTypes.removeAll(keepingCapacity: true)
        sentEvents.removeAll(keepingCapacity: true)
    }

    func connectCountValue() -> Int { connectCount }
    func pingCountValue() -> Int { pingCount }
    func sentTypesValue() -> [VoiceEventType] { sentTypes }

    // P2.8A-CI-FIX-2: 注入下一次指定类型 send 失败 (消费后自动移除)
    func failNextSend(_ type: VoiceEventType) {
        failNextSendTypes.append(type)
    }
    func failNextPing() {
        shouldFailNextPing = true
    }
    func sentEventsValue() -> [VoiceEvent] { sentEvents }

    private func resumeConnectWaiters() {
        var pending: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in connectWaiters {
            if connectCount >= waiter.target {
                waiter.continuation.resume()
            } else {
                pending.append(waiter)
            }
        }
        connectWaiters = pending
    }

    private func resumeSentEventWaiters() {
        var pending: [(type: VoiceEventType, count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in sentEventWaiters {
            let count = sentTypes.filter { $0 == waiter.type }.count
            if count >= waiter.count {
                waiter.continuation.resume()
            } else {
                pending.append(waiter)
            }
        }
        sentEventWaiters = pending
    }

    private func emit(
        _ type: VoiceEventType,
        event: VoiceEvent,
        payload: [String: JSONValue] = [:]
    ) {
        serverSequence += 1
        eventBroadcaster.yield(VoiceEvent(
            version: VoiceEvent.protocolVersion,
            eventID: UUID().uuidString,
            traceID: event.traceID,
            sessionID: event.sessionID,
            sequence: serverSequence,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: type,
            payload: payload
        ))
    }
}
