import Combine
import Foundation

private enum VoiceSessionClientError: Error, Equatable {
    case configurationMissing
    case microphoneDenied
    case audioSessionFailed
    case protocolReadyTimedOut
    case callEnded
}

@MainActor
final class VoiceSessionController: ObservableObject {
    @Published private(set) var state: VoiceSessionState = .idle
    @Published private(set) var route: VoiceRoute = .b
    @Published private(set) var transcript = ""
    @Published private(set) var responseText = ""
    @Published private(set) var errorMessage = ""
    // P2.7B-FINAL-IDLE: 空闲生命周期产品状态 (不占用 errorMessage, 避免红色错误样式)
    @Published private(set) var idleWarningRemainingSeconds: Int?
    @Published private(set) var idleTimeoutEnded = false
    @Published private(set) var isMuted = false
    @Published private(set) var webSocketState: VoiceWebSocketState = .disconnected
    @Published private(set) var microphonePermission: MicrophonePermissionState = .notDetermined
    @Published private(set) var audioSessionActive = false
    @Published private(set) var audioRouteDescription = "未激活"
    @Published private(set) var reconnectAttempt = 0
    @Published private(set) var lastCloseCode: Int?
    @Published private(set) var lastErrorCategory = ""
    @Published private(set) var lastReasonCategory = ""
    @Published private(set) var lastDisconnectRecoverable = false
    @Published private(set) var lastServerEventType = ""
    @Published private(set) var lastServerEventAt: Date?
    @Published private(set) var networkType: NetworkConnectionType = .other
    @Published private(set) var isRecording = false
    @Published private(set) var vadState: VoiceActivityState = .idleListening
    @Published private(set) var vadEnergyBand = "silent"
    @Published private(set) var vadNormalizedRMS = 0.0
    @Published private(set) var speechStartCount = 0
    @Published private(set) var automaticCommitCount = 0
    @Published private(set) var rejectedNoiseCount = 0
    @Published private(set) var bargeInDetectionCount = 0
    @Published private(set) var interruptSentCount = 0
    @Published private(set) var ignoredInterruptedAudioChunks = 0
    @Published private(set) var responseNextSentCount = 0
    @Published private(set) var serverPushAudioChunks = 0
    @Published private(set) var isPlaybackActive = false
    @Published private(set) var lastSpeechDurationMilliseconds = 0
    @Published private(set) var lastEndingSilenceMilliseconds = 0
    @Published private(set) var callIsActive = false
    @Published private(set) var responseCompletionCount = 0
    @Published private(set) var postResponseCaptureRecoveryCount = 0

    private let environment: AppEnvironment
    private let socket: any VoiceAdapter
    private let capture: AudioCapturing
    private let playback: AudioPlaying
    private let audioSession: AudioSessionControlling
    private let networkMonitor: NetworkMonitoring
    private let reconnectDelays: [Duration]
    private let protocolReadyTimeout: Duration
    private let captureWatchdogInterval: Duration
    private let captureStallThresholdSeconds: TimeInterval
    private let maxCaptureRecoveryAttempts: Int
    private let audioIOHealthReporter: RealtimeAudioIOHealthReporting?
    private let usesSharedAudioIO: Bool
    private let audioUploader: AudioUploadActor

    private var voiceActivityDetector: VoiceActivityDetector
    private var receiveTask: Task<Void, Never>?
    private var receiveGeneration = 0
    private var receiveLoopStartCount = 0
    private var receiveLoopStopCount = 0
    private var activeReceiveLoopCount = 0
    private var maxActiveReceiveLoopCount = 0
    private var lifecycleConnectedEventCount = 0
    private var protocolReadyEventCount = 0
    private var lifecycleTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var captureWatchdogTask: Task<Void, Never>?
    private var captureWatchdogStartedAt: Date?
    private var captureRecoveryAttemptCount = 0
    private var lastObservedCaptureCallbackCount = 0
    private var reconnectTask: Task<Void, Never>?
    private var reconnectGeneration: UUID?
    private var sessionID = ""
    private var traceID = ""
    private var responseID = ""
    private var lastServerSequence = 0
    private var metrics = VoiceMetrics(route: .b)
    private var suspendedForBackground = false
    private var commitSentForCurrentPress = false
    private var expectedReadyEvent: VoiceEventType?
    private var lastReadyEvent: VoiceEventType?
    private var interruptedResponseID = ""
    private var interruptedResponseIDs: Set<String> = []
    private var automaticBargeInActive = false
    private var webSocketConnectedAt: Date?
    private var lastDisconnectUptimeMilliseconds: Int?
    private var firstInputChunkSentAt: Date?
    private var audioCommitSentAt: Date?
    private var firstAudioDeltaReceivedAt: Date?
    private var terminalProtocolErrorCode: String?
    private var terminalLocalAudioFailure = false
    private var presentationRequestedAt: Date?
    private var audioSessionActivatedAt: Date?
    private var sessionReadyAt: Date?
    private var microphoneReadyAt: Date?
    private var lastResponseCompletionCaptureCallbacks = 0
    private var postResponseCaptureCallbackDelta = 0
    private var postResponseCaptureCheckTask: Task<Void, Never>?
    private var microphoneReadinessTask: Task<Void, Never>?

    init(
        environment: AppEnvironment,
        socket: any VoiceAdapter,
        capture: AudioCapturing,
        playback: AudioPlaying,
        audioSession: AudioSessionControlling,
        networkMonitor: NetworkMonitoring,
        reconnectDelays: [Duration] = [
            .milliseconds(400),
            .milliseconds(800),
            .milliseconds(1_600),
            .milliseconds(3_200),
            .milliseconds(6_400)
        ],
        protocolReadyTimeout: Duration = .seconds(8),
        voiceActivityConfiguration: VoiceActivityConfiguration = .realtimeDefault,
        captureWatchdogInterval: Duration = .seconds(1),
        captureStallThreshold: Duration = .seconds(2),
        maxCaptureRecoveryAttempts: Int = 2
    ) {
        self.environment = environment
        self.socket = socket
        self.capture = capture
        self.playback = playback
        self.audioSession = audioSession
        self.networkMonitor = networkMonitor
        self.reconnectDelays = reconnectDelays
        self.protocolReadyTimeout = protocolReadyTimeout
        self.captureWatchdogInterval = captureWatchdogInterval
        self.captureStallThresholdSeconds = captureStallThreshold.timeInterval
        self.maxCaptureRecoveryAttempts = max(1, maxCaptureRecoveryAttempts)
        self.audioIOHealthReporter = capture as? RealtimeAudioIOHealthReporting
        self.usesSharedAudioIO = (capture as AnyObject) === (playback as AnyObject)
        let audioUploader = AudioUploadActor(socket: socket)
        self.audioUploader = audioUploader
        self.voiceActivityDetector = VoiceActivityDetector(
            configuration: voiceActivityConfiguration
        )
        self.capture.onPacket = { packet in
            _ = audioUploader.offer(packet)
        }
        let lifecycleEvents = socket.lifecycleEvents
        lifecycleTask = Task { @MainActor [weak self] in
            for await event in lifecycleEvents {
                guard let self else { return }
                await self.handleLifecycleEvent(event)
            }
        }
    }

    var canStartRecording: Bool {
        return callIsActive
            && state == .ready
            && microphonePermission == .granted
            && audioSessionActive
            && webSocketState == .connected
            && !isMuted
            && !isRecording
    }

    var canMute: Bool {
        callIsActive && webSocketState == .connected && state != .connecting && state != .closing
    }

    var canInterrupt: Bool {
        callIsActive && state == .speaking && !responseID.isEmpty
    }

    var canCommitAudio: Bool { callIsActive && isRecording && state == .listening }

    var shouldShowReconnect: Bool {
        callIsActive && (state == .failed || state == .closed || state == .reconnecting)
    }

    var reconnectStatusText: String {
        reconnectAttempt > 0 ? "正在重连 \(reconnectAttempt)/\(reconnectDelays.count)" : "正在重连"
    }

    var isConversationReady: Bool {
        let audioHealth = audioIOHealthReporter?.healthSnapshot
        let captureHealthy = audioHealth.map {
            $0.captureEngineRunning
                && $0.captureTapInstalled
                && $0.captureCallbackCount > 0
        } ?? isRecording
        return callIsActive
            && webSocketState == .connected
            && audioSessionActive
            && isRecording
            && captureHealthy
            && (state == .ready || state == .listening || state == .speaking)
    }

    var diagnosticText: String {
        let audioHealth = audioIOHealthReporter?.healthSnapshot ?? .unavailable
        let uploadHealth = audioUploader.diagnostics.snapshot
        return VoiceDiagnosticSnapshot(
            appBuildSHA: environment.appBuildSHA,
            appBuildTime: environment.appBuildTime,
            state: state,
            webSocketState: webSocketState,
            adapterMode: environment.hostAdapters.mode.diagnosticLabel,
            sessionHash: VoiceDiagnosticSnapshot.shortHash(sessionID),
            lastCloseCode: lastCloseCode,
            lastErrorCategory: lastErrorCategory,
            lastReasonCategory: lastReasonCategory,
            lastDisconnectRecoverable: lastDisconnectRecoverable,
            reconnectAttempt: reconnectAttempt,
            reconnectCount: metrics.reconnectCount,
            microphonePermission: audioSession.permissionState,
            audioSessionActive: audioSession.isActive,
            audioRouteDescription: audioSession.routeDescription,
            lastServerEventType: lastServerEventType,
            lastServerEventAt: lastServerEventAt,
            inputAudioChunks: metrics.inputFrames,
            outputAudioChunks: metrics.outputChunks,
            providerErrorCount: metrics.degradedCount,
            networkType: networkMonitor.connectionType,
            vadState: vadState,
            vadEnergyBand: vadEnergyBand,
            vadNormalizedRMS: vadNormalizedRMS,
            vadConfiguration: voiceActivityDetector.configuration,
            speechStartCount: speechStartCount,
            automaticCommitCount: automaticCommitCount,
            rejectedNoiseCount: rejectedNoiseCount,
            bargeInDetectionCount: bargeInDetectionCount,
            interruptSentCount: interruptSentCount,
            interruptSuccessCount: metrics.interruptSuccessCount,
            ignoredInterruptedAudioChunks: ignoredInterruptedAudioChunks,
            webSocketResourceTimeoutSeconds: Int(VoiceWebSocketConfiguration.resourceTimeoutSeconds),
            webSocketConnectedDurationMilliseconds: elapsedMilliseconds(since: webSocketConnectedAt),
            lastDisconnectUptimeMilliseconds: lastDisconnectUptimeMilliseconds,
            endToFirstAudioMilliseconds: elapsedMilliseconds(
                from: audioCommitSentAt,
                to: firstAudioDeltaReceivedAt
            ),
            firstInputChunkSentAt: firstInputChunkSentAt,
            audioCommitSentAt: audioCommitSentAt,
            firstAudioDeltaReceivedAt: firstAudioDeltaReceivedAt,
            responseNextSentCount: responseNextSentCount,
            serverPushAudioChunks: serverPushAudioChunks,
            continuousCaptureActive: isRecording,
            captureEngineRunning: audioHealth.captureEngineRunning,
            captureTapInstalled: audioHealth.captureTapInstalled,
            captureCallbackCount: audioHealth.captureCallbackCount,
            lastCaptureCallbackAt: audioHealth.lastCaptureCallbackAt,
            captureRestartCount: audioHealth.captureRestartCount,
            audioEngineStartCount: audioHealth.audioEngineStartCount,
            audioEngineStopCount: audioHealth.audioEngineStopCount,
            playbackStartCount: audioHealth.playbackStartCount,
            audioInterruptionCount: audioHealth.audioInterruptionCount,
            engineConfigurationChangeCount: audioHealth.engineConfigurationChangeCount,
            uploadConnectionGeneration: uploadHealth.connectionGeneration,
            uploadCaptureGeneration: uploadHealth.captureGeneration,
            uploadNextChunkIndex: uploadHealth.nextChunkIndex,
            uploadNextClientSequence: uploadHealth.nextClientSequence,
            uploadQueueDepth: uploadHealth.queueDepth,
            uploadQueueHighWater: uploadHealth.queueHighWater,
            uploadSentAudioChunks: uploadHealth.sentAudioChunks,
            uploadSentControlCommands: uploadHealth.sentControlCommands,
            uploadDroppedStaleGenerationChunks: uploadHealth.droppedStaleGenerationChunks,
            uploadRejectedAfterCloseCommands: uploadHealth.rejectedAfterCloseCommands,
            uploadStaleGenerationSendFailureCount: uploadHealth.staleGenerationSendFailureCount,
            uploadActiveGenerationSendFailureCount: uploadHealth.activeGenerationSendFailureCount,
            uploadInputBackpressureCount: uploadHealth.inputBackpressureCount,
            uploadMaxActiveDrainTasks: uploadHealth.maxActiveDrainTasks,
            uploadLastFiveSentChunkIndices: uploadHealth.lastFiveSentChunkIndices,
            uploadLastSendFailureCategory: uploadHealth.lastSendFailureCategory,
            uploadGenerationStartedAt: uploadHealth.generationStartedAt,
            playbackActive: isPlaybackActive,
            lastSpeechDurationMilliseconds: lastSpeechDurationMilliseconds,
            lastEndingSilenceMilliseconds: lastEndingSilenceMilliseconds,
            presentationToAudioSessionMilliseconds: elapsedMilliseconds(
                from: presentationRequestedAt,
                to: audioSessionActivatedAt
            ),
            presentationToWebSocketMilliseconds: elapsedMilliseconds(
                from: presentationRequestedAt,
                to: webSocketConnectedAt
            ),
            presentationToSessionReadyMilliseconds: elapsedMilliseconds(
                from: presentationRequestedAt,
                to: sessionReadyAt
            ),
            presentationToMicrophoneReadyMilliseconds: elapsedMilliseconds(
                from: presentationRequestedAt,
                to: microphoneReadyAt
            ),
            responseCompletionCount: responseCompletionCount,
            postResponseCaptureRecoveryCount: postResponseCaptureRecoveryCount,
            lastResponseCompletionCaptureCallbacks: lastResponseCompletionCaptureCallbacks,
            postResponseCaptureCallbackDelta: postResponseCaptureCallbackDelta,
            generatedAt: Date()
        ).text
    }

    func markPresentationRequested() {
        presentationRequestedAt = Date()
        audioSessionActivatedAt = nil
        sessionReadyAt = nil
        microphoneReadyAt = nil
    }

    func startNewCall() async {
        await tearDownCurrentCall(sendSessionEnd: callIsActive, finalState: nil)
        resetForNewCall()
        await audioUploader.configure(
            processor: { [weak self] frame in
                await self?.uploadIntents(for: frame) ?? []
            },
            notificationHandler: { [weak self] notification in
                await self?.handleUploadNotification(notification)
            }
        )
        callIsActive = true
        suspendedForBackground = false
        networkMonitor.start()
        networkType = networkMonitor.connectionType
        await startReceiveLoop()
        state = .connecting
        expectedReadyEvent = .sessionReady
        lastReadyEvent = nil
        guard await authorizeMicrophone() else {
            networkMonitor.stop()
            return
        }
        async let audioPrepared = activateAudioSession()
        async let socketConnected = connectSocketForNewSession()
        let (audioReady, connected) = await (audioPrepared, socketConnected)
        guard audioReady, connected else {
            if connected {
                await socket.disconnect()
                webSocketState = .disconnected
            }
            if !audioReady { networkMonitor.stop() }
            return
        }
        await startProtocolSessionOnConnectedSocket()
    }

    func reconnectCurrentCall() {
        guard callIsActive else { return }
        if terminalLocalAudioFailure {
            Task { @MainActor [weak self] in await self?.startNewCall() }
            return
        }
        if state == .closed {
            Task { @MainActor [weak self] in await self?.startNewCall() }
            return
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectGeneration = nil
        beginReconnect(immediate: true)
    }

    func endCurrentCall() async {
        await tearDownCurrentCall(sendSessionEnd: callIsActive, finalState: .closed)
    }

    // Retained only as an internal compatibility hook for existing tests/debug tools.
    // The production UI never requires press-to-talk.
    func startListening() {
        Task { @MainActor [weak self] in
            await self?.startContinuousCaptureIfPossible()
        }
    }

    func commitAudio() async {
        guard callIsActive, isRecording, !commitSentForCurrentPress else { return }
        commitSentForCurrentPress = true
        voiceActivityDetector.suspend()
        vadState = .endpointing
        state = .processing
        do {
            try await audioUploader.commit()
        } catch {
            recordSendFailure(error)
        }
    }

    func finishPress(cancelled: Bool) async {
        _ = cancelled
        await commitAudio()
    }

    func interrupt() async {
        guard canInterrupt else { return }
        metrics.interruptCount += 1
        state = .interrupting
        playback.cancel(responseID: responseID)
        isPlaybackActive = false
        do {
            try await audioUploader.interrupt(responseID: responseID)
        } catch {
            recordSendFailure(error)
        }
    }

    /// P2.8A-CI-FIX: 静音/取消静音的确定性控制流.
    /// 设置静音: 本地停采 → 仅连接正常时发送 mute (断开时不向失效连接发送).
    /// 取消静音: 连接正常 → 发 unmute + 恢复采集; 断开且可恢复 → 不发送 unmute, 直接走现有重连;
    ///           已关闭/空闲结束/不可恢复 → 无效, 不重连、不新建 Session.
    func setMuted(_ muted: Bool) async {
        guard callIsActive else { return }
        // 幂等: 重复设置相同状态不重复停启采集/不重复发送静音命令/不重复创建重连任务
        guard isMuted != muted else { return }
        isMuted = muted

        if muted {
            // 静音: 先本地停采
            await audioUploader.pauseCapture()
            stopContinuousCapture(resetVAD: true)
            // 仅连接正常才向服务端发送 mute; 断开的失效连接不发送
            guard webSocketState == .connected else { return }
            do {
                try await audioUploader.setMuted(true)
            } catch {
                recordSendFailure(error)
            }
            return
        }

        // 取消静音
        if webSocketState == .connected {
            do {
                try await audioUploader.setMuted(false)
            } catch {
                // P2.8A-CI-FIX-2: 只有 unmute 发送成功后才能恢复采集;
                // 发送失败走现有发送失败处理(触发重连流程), 不因本地已置 false 而恢复采集.
                recordSendFailure(error)
                return
            }
            await startContinuousCaptureIfPossible()
        } else if lastDisconnectRecoverable,
                  state != .closed,
                  state != .failed,
                  lastReasonCategory != "idle_timeout" {
            // P2.8A-CI-FIX: 断开但可恢复 → 不向旧连接发送 unmute, 直接走现有重连
            // (session.resume, 不新建 Session / 不新发 session.start / 不新增重连循环)
            reconnectCurrentCall()
        }
    }

    func appDidEnterBackground() async {
        guard callIsActive else { return }
        // The app declares the audio background mode and keeps an active play-and-record
        // session, so an in-progress voice call can continue while locked or backgrounded.
        suspendedForBackground = false
        VoiceLog.lifecycle.info("app_background_call_continues")
    }

    func appWillEnterForeground() async {
        guard callIsActive else { return }
        suspendedForBackground = false
        if webSocketState != .connected {
            reconnectCurrentCall()
        }
    }

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
        commitSentForCurrentPress = false
        expectedReadyEvent = nil
        lastReadyEvent = nil
        interruptedResponseID = ""
        interruptedResponseIDs.removeAll(keepingCapacity: false)
        automaticBargeInActive = false
        reconnectAttempt = 0
        lastCloseCode = nil
        lastErrorCategory = ""
        lastReasonCategory = ""
        lastDisconnectRecoverable = false
        lastServerEventType = ""
        lastServerEventAt = nil
        webSocketState = .disconnected
        route = .b
        state = .idle
        voiceActivityDetector.resetForListening()
        vadState = .idleListening
        vadEnergyBand = "silent"
        vadNormalizedRMS = 0
        speechStartCount = 0
        automaticCommitCount = 0
        rejectedNoiseCount = 0
        bargeInDetectionCount = 0
        interruptSentCount = 0
        ignoredInterruptedAudioChunks = 0
        responseNextSentCount = 0
        serverPushAudioChunks = 0
        webSocketConnectedAt = nil
        lastDisconnectUptimeMilliseconds = nil
        firstInputChunkSentAt = nil
        audioCommitSentAt = nil
        firstAudioDeltaReceivedAt = nil
        terminalProtocolErrorCode = nil
        terminalLocalAudioFailure = false
        isPlaybackActive = false
        lastSpeechDurationMilliseconds = 0
        lastEndingSilenceMilliseconds = 0
        responseCompletionCount = 0
        postResponseCaptureRecoveryCount = 0
        lastResponseCompletionCaptureCallbacks = 0
        postResponseCaptureCallbackDelta = 0
        postResponseCaptureCheckTask?.cancel()
        postResponseCaptureCheckTask = nil
        microphoneReadinessTask?.cancel()
        microphoneReadinessTask = nil
        metrics = VoiceMetrics(
            traceID: traceID,
            sessionID: sessionID,
            route: .b,
            startedAt: Date()
        )
        stopCaptureWatchdog()
        playback.cancel(responseID: nil)
        capture.stop()
        VoiceLog.lifecycle.info("new_call_created")
    }

    private func authorizeMicrophone() async -> Bool {
        microphonePermission = audioSession.permissionState
        if microphonePermission == .notDetermined {
            microphonePermission = await audioSession.requestPermission() ? .granted : .denied
        }
        guard microphonePermission == .granted else {
            state = .failed
            errorMessage = microphoneDeniedMessage
            audioSessionActive = false
            audioRouteDescription = "未激活"
            VoiceLog.audio.error("microphone_permission_denied")
            return false
        }
        return true
    }

    private func activateAudioSession() -> Bool {
        do {
            try audioSession.activate()
            audioSession.refreshRoute()
            syncAudioSessionState()
            audioSessionActivatedAt = Date()
            return true
        } catch {
            state = .failed
            errorMessage = "无法激活语音通话音频会话。"
            syncAudioSessionState()
            VoiceLog.audio.error("audio_session_activation_failed")
            return false
        }
    }

    private func connectSocketForNewSession() async -> Bool {
        do {
            try await socket.connect()
            markWebSocketConnected()
            return true
        } catch {
            handleConnectionFailure(error, allowReconnect: true)
            return false
        }
    }

    private func startProtocolSessionOnConnectedSocket() async {
        do {
            try await audioUploader.openConnection(
                sessionID: sessionID,
                traceID: traceID
            )
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
        for (index, delay) in reconnectDelays.enumerated() {
            guard callIsActive, !suspendedForBackground, !Task.isCancelled else { return }
            reconnectAttempt = index + 1
            metrics.reconnectCount += 1
            state = .reconnecting
            if !(immediate && index == 0) {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            guard callIsActive, !Task.isCancelled else { return }
            expectedReadyEvent = .sessionResumed
            lastReadyEvent = nil
            do {
                try await socket.connect()
                markWebSocketConnected()
                try await audioUploader.openConnection(
                    sessionID: sessionID,
                    traceID: traceID,
                    resumeFrom: lastServerSequence
                )
                startHeartbeat()
                try await waitForReady(expected: .sessionResumed)
                reconnectAttempt = 0
                errorMessage = ""
                VoiceLog.lifecycle.info("reconnect_succeeded")
                return
            } catch let info as VoiceWebSocketDisconnectInfo {
                applyDisconnectInfo(info)
                if !info.recoverable {
                    state = .failed
                    return
                }
            } catch VoiceSessionClientError.callEnded {
                return
            } catch is CancellationError {
                return
            } catch {
                lastErrorCategory = "connection_lost"
                lastReasonCategory = "reconnect_attempt_failed"
                lastDisconnectRecoverable = true
            }
        }
        state = .failed
        errorMessage = "连接失败，已达到最大重连次数。"
        VoiceLog.lifecycle.error("reconnect_exhausted attempts=\(self.reconnectDelays.count)")
    }

    private func waitForReady(expected: VoiceEventType) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: protocolReadyTimeout)
        while clock.now < deadline {
            guard callIsActive else { throw VoiceSessionClientError.callEnded }
            if lastReadyEvent == expected, state == .ready { return }
            if state == .failed, !lastDisconnectRecoverable {
                throw VoiceWebSocketDisconnectInfo(
                    closeCode: lastCloseCode,
                    recoverable: false,
                    errorCategory: lastErrorCategory.isEmpty ? "unknown" : lastErrorCategory,
                    reasonCategory: lastReasonCategory.isEmpty ? "protocol_failed" : lastReasonCategory
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw VoiceSessionClientError.protocolReadyTimedOut
    }

    private func startReceiveLoop() async {
        await stopReceiveLoop()
        receiveGeneration &+= 1
        let generation = receiveGeneration
        let events = socket.makeEventStream()
        receiveLoopStartCount += 1
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.activeReceiveLoopCount += 1
            self.maxActiveReceiveLoopCount = max(
                self.maxActiveReceiveLoopCount,
                self.activeReceiveLoopCount
            )
            defer {
                self.activeReceiveLoopCount -= 1
                self.receiveLoopStopCount += 1
            }
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
            VoiceLog.websocket.info("websocket_connected")
        }
    }

    private func handleLifecycleEvent(_ event: VoiceWebSocketLifecycleEvent) async {
        switch event {
        case .connecting:
            if webSocketState != .connected {
                webSocketState = .connecting
            }
            VoiceLog.websocket.info("websocket_connecting")
        case .connected:
            lifecycleConnectedEventCount += 1
            markWebSocketConnected()
        case .disconnected(let info):
            if await socket.isConnected() {
                VoiceLog.websocket.info("stale_disconnected_lifecycle_ignored")
                return
            }
            webSocketState = .disconnected
            await audioUploader.pauseCapture()
            await audioUploader.abortConnection()
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
            if await socket.isConnected() {
                VoiceLog.websocket.info("stale_failed_lifecycle_ignored")
                return
            }
            webSocketState = .failed
            await audioUploader.pauseCapture()
            await audioUploader.abortConnection()
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

    private func applyDisconnectInfo(_ info: VoiceWebSocketDisconnectInfo) {
        lastDisconnectUptimeMilliseconds = elapsedMilliseconds(since: webSocketConnectedAt)
        webSocketConnectedAt = nil
        lastCloseCode = info.closeCode
        if !callIsActive, lastReasonCategory == "idle_timeout" {
            // The normal client-side close that follows session.ended is transport
            // cleanup, not a new terminal reason. Preserve the server-confirmed
            // idle outcome so diagnostics cannot misclassify it as client_closed.
            return
        }
        lastErrorCategory = info.errorCategory
        lastReasonCategory = info.reasonCategory
        lastDisconnectRecoverable = info.recoverable
        if info.errorCategory != "cancelled" {
            errorMessage = userMessage(for: info)
        }
        VoiceLog.websocket.error(
            "websocket_closed code=\(info.closeCode ?? 0) category=\(info.errorCategory) recoverable=\(info.recoverable)"
        )
    }

    private func handleConnectionFailure(_ error: Error, allowReconnect: Bool) {
        if let info = error as? VoiceWebSocketDisconnectInfo {
            applyDisconnectInfo(info)
            if allowReconnect, info.recoverable {
                beginReconnect(immediate: false)
            } else {
                state = .failed
            }
            return
        }
        if let clientError = error as? VoiceSessionClientError,
           clientError == .protocolReadyTimedOut {
            lastErrorCategory = "timed_out"
            lastReasonCategory = "session_ready_timeout"
            lastDisconnectRecoverable = true
            errorMessage = "连接已建立，但服务器会话未就绪。"
            if allowReconnect { beginReconnect(immediate: false) }
            return
        }
        lastErrorCategory = "unknown"
        lastReasonCategory = "connection_failed"
        lastDisconnectRecoverable = true
        errorMessage = "语音连接失败。"
        if allowReconnect { beginReconnect(immediate: false) } else { state = .failed }
    }

    private func handle(_ event: VoiceEvent) async {
        guard event.sessionID == sessionID else { return }
        lastServerEventType = event.type.rawValue
        lastServerEventAt = Date()
        if event.sequence <= lastServerSequence {
            metrics.duplicateFrames += 1
            return
        }
        lastServerSequence = event.sequence
        if terminalProtocolErrorCode != nil, event.type != .sessionClosed {
            return
        }

        switch event.type {
        case .sessionReady where expectedReadyEvent == .sessionReady:
            protocolReadyEventCount += 1
            state = .ready
            reconnectAttempt = 0
            errorMessage = ""
            await audioUploader.markReady()
            await startContinuousCaptureIfPossible()
            sessionReadyAt = Date()
            markMicrophoneReadyIfPossible()
            lastReadyEvent = .sessionReady
        case .sessionResumed where expectedReadyEvent == .sessionResumed:
            protocolReadyEventCount += 1
            resetProviderGenerationAfterResume()
            // P2.8A-CI-FIX-3: 保持 .reconnecting 状态进入 markReady (不提前提升为 .ready)
            await audioUploader.markReady()
            // P2.8A-CI-FIX: Resume 成功后同步静音状态到已恢复的连接
            // (未静音 → 发一次 unmute 后恢复采集; 静音 → 发一次 mute 不启动采集)
            // P2.8A-CI-FIX-3: 同步失败立即返回 — 保持 .reconnecting, 不得清空 errorMessage /
            // reconnectAttempt, 不恢复采集, 不标记 Resume 成功 (lastReadyEvent 不设);
            // 由当前重连流程的 waitForReady 超时可靠进入下一次恢复或明确失败
            // (不会因 reconnectTask 已存在而丢失: 现有任务继续循环).
            guard await syncMuteStateAfterResume() else { return }
            // 仅同步成功后提升就绪状态, 再恢复/激活采集
            state = .ready
            reconnectAttempt = 0
            errorMessage = ""
            if isRecording {
                await audioUploader.activateCaptureGeneration(capture.captureGeneration)
            } else {
                await startContinuousCaptureIfPossible()
            }
            sessionReadyAt = Date()
            markMicrophoneReadyIfPossible()
            lastReadyEvent = .sessionResumed
        case .listeningStarted:
            state = .listening
        case .listeningStopped, .thinkingStarted:
            state = .processing
        case .transcriptPartial, .transcriptFinal:
            transcript = event.payload.string("text") ?? transcript
        case .responseStarted:
            responseID = event.payload.string("response_id") ?? ""
            metrics.responseID = responseID
            automaticBargeInActive = false
            isPlaybackActive = false
            voiceActivityDetector.resetForListening()
            vadState = .idleListening
            state = .speaking
            await startContinuousCaptureIfPossible()
        case .responseAudioDelta:
            guard let eventResponseID = event.payload.string("response_id") else { return }
            if shouldIgnoreInterruptedResponse(eventResponseID) {
                ignoredInterruptedAudioChunks += 1
                VoiceLog.audio.info(
                    "interrupted_audio_ignored count=\(self.ignoredInterruptedAudioChunks)"
                )
                return
            }
            guard eventResponseID == responseID,
                  let encoded = event.payload.string("audio"),
                  let data = Data(base64Encoded: encoded) else { return }
            let index = event.payload.int("chunk_index") ?? 0
            playback.enqueue(data, responseID: eventResponseID, chunkIndex: index)
            metrics.outputChunks += 1
            metrics.outputBytes += data.count
            serverPushAudioChunks += 1
            let receivedAt = Date()
            if metrics.firstAudioAt == nil { metrics.firstAudioAt = receivedAt }
            if firstAudioDeltaReceivedAt == nil {
                firstAudioDeltaReceivedAt = receivedAt
            }
            isPlaybackActive = true
            state = .speaking
        case .responseAudioDone, .responseCancelled:
            let eventResponseID = event.payload.string("response_id") ?? responseID
            if shouldIgnoreInterruptedResponse(eventResponseID) {
                playback.cancel(responseID: eventResponseID)
                if responseID == eventResponseID {
                    responseID = ""
                    isPlaybackActive = false
                }
                break
            }
            guard eventResponseID == responseID else { break }
            isPlaybackActive = false
            if automaticBargeInActive,
               vadState == .speechDetected || vadState == .sendingSpeech || vadState == .endpointing {
                break
            }
            metrics.finishedAt = Date()
            responseID = ""
            automaticBargeInActive = false
            voiceActivityDetector.resetForListening()
            vadState = .idleListening
            state = .ready
            await startContinuousCaptureIfPossible()
            responseCompletionCount += 1
            schedulePostResponseCaptureCheck()
        case .responseTextDelta, .responseTextDone:
            responseText = event.payload.string("text") ?? responseText
        case .interrupted:
            let eventResponseID = event.payload.string("response_id") ?? interruptedResponseID
            if shouldIgnoreInterruptedResponse(eventResponseID) {
                playback.cancel(responseID: eventResponseID)
                if responseID == eventResponseID {
                    responseID = ""
                    isPlaybackActive = false
                }
                if event.payload.bool("success") == true {
                    metrics.interruptSuccessCount += 1
                }
                if vadState == .endpointing {
                    state = .processing
                } else if vadState == .sendingSpeech || vadState == .speechDetected {
                    state = .listening
                }
                break
            }
            playback.cancel(responseID: responseID)
            isPlaybackActive = false
            if event.payload.bool("success") == true { metrics.interruptSuccessCount += 1 }
            responseID = ""
            automaticBargeInActive = false
            voiceActivityDetector.resetForListening()
            vadState = .idleListening
            state = .ready
        case .routeChanged:
            route = .b
        case .degraded:
            metrics.degradedCount += 1
            lastErrorCategory = "provider_degraded"
            state = .degraded
        case .serverIdleWarning:
            let remainingSeconds = event.payload.int("remaining_seconds") ?? 30
            idleWarningRemainingSeconds = max(1, remainingSeconds)
            idleTimeoutEnded = false
            lastReasonCategory = "idle_warning"
            // 产品化: 不写入 errorMessage (不显示红色错误), 不改变通话状态,
            // 不暂停麦克风, 不断开连接, 不自行启动本地倒计时 (服务端为唯一超时来源)
        case .sessionEnded:
            guard event.payload.string("reason") == "idle_timeout" else { break }
            idleWarningRemainingSeconds = nil
            idleTimeoutEnded = true
            callIsActive = false
            lastReasonCategory = "idle_timeout"
            lastErrorCategory = "none"
            lastDisconnectRecoverable = false
            // 产品化: 空闲结束由专用弹窗呈现, 不写入 errorMessage (不按普通错误/网络失败归类)
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectGeneration = nil
            heartbeatTask?.cancel()
            heartbeatTask = nil
            await audioUploader.pauseCapture()
            await audioUploader.abortConnection()
            stopContinuousCapture(resetVAD: true)
            playback.cancel(responseID: nil)
            isPlaybackActive = false
            responseID = ""
            interruptedResponseID = ""
            interruptedResponseIDs.removeAll(keepingCapacity: false)
            automaticBargeInActive = false
            audioIOHealthReporter?.shutdownAudioIO()
            await socket.disconnect()
            webSocketState = .disconnected
            audioSession.deactivate()
            syncAudioSessionState()
            networkMonitor.stop()
            expectedReadyEvent = nil
            lastReadyEvent = nil
            state = .closed
        case .sessionClosed:
            responseID = ""
            isPlaybackActive = false
            await audioUploader.pauseCapture()
            await audioUploader.abortConnection()
            stopContinuousCapture(resetVAD: true)
            heartbeatTask?.cancel()
            heartbeatTask = nil
            await socket.disconnect()
            webSocketState = .disconnected
            state = .closed
        case .error:
            let code = event.payload.string("code") ?? "protocol_error"
            let retryable = event.payload.bool("retryable") ?? false
            if !retryable {
                guard terminalProtocolErrorCode == nil else { break }
                terminalProtocolErrorCode = code
                metrics.degradedCount += 1
                lastErrorCategory = code
                lastReasonCategory = "non_retryable_server_error"
                lastDisconnectRecoverable = false
                errorMessage = "语音服务返回不可恢复错误：\(code)"
                reconnectTask?.cancel()
                reconnectTask = nil
                reconnectGeneration = nil
                heartbeatTask?.cancel()
                heartbeatTask = nil
                await audioUploader.pauseCapture()
                await audioUploader.abortConnection()
                stopContinuousCapture(resetVAD: true)
                playback.cancel(responseID: nil)
                isPlaybackActive = false
                responseID = ""
                interruptedResponseID = ""
                interruptedResponseIDs.removeAll(keepingCapacity: false)
                automaticBargeInActive = false
                state = .failed
                break
            }
            metrics.degradedCount += 1
            lastErrorCategory = code
            lastReasonCategory = "retryable_server_error"
            lastDisconnectRecoverable = true
            errorMessage = "语音服务暂时不可用：\(code)"
            state = .degraded
        default:
            break
        }
        VoiceLog.lifecycle.info("server_event=\(event.type.rawValue) state=\(self.state.rawValue)")
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.callIsActive, !self.suspendedForBackground {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                do {
                    try await self.audioUploader.ping()
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

    private func uploadIntents(for data: Data) -> [AudioUploadIntent] {
        guard callIsActive,
              isRecording,
              !isMuted,
              webSocketState == .connected else { return [] }

        let mode: VoiceActivityMode
        if state == .speaking, !responseID.isEmpty {
            mode = .bargeIn
        } else if state == .ready || state == .listening {
            mode = .listening
        } else {
            return []
        }

        let analysis = voiceActivityDetector.process(data, mode: mode)
        vadState = analysis.state
        vadNormalizedRMS = analysis.normalizedRMS
        vadEnergyBand = analysis.energyBand
        var intents: [AudioUploadIntent] = []

        for action in analysis.actions {
            switch action {
            case .rejectedNoise:
                rejectedNoiseCount += 1
                VoiceLog.audio.info("vad_noise_rejected count=\(self.rejectedNoiseCount)")

            case .speechStarted(let frames, let bargeIn):
                speechStartCount += 1
                commitSentForCurrentPress = false
                if lastReasonCategory == "idle_warning" {
                    lastReasonCategory = ""
                    idleWarningRemainingSeconds = nil
                }
                Task { [audioUploader] in
                    do {
                        try await audioUploader.sendClientState([
                            "vad_state": .string("speech_start")
                        ])
                    } catch {
                        VoiceLog.websocket.error("vad_activity_report_failed")
                    }
                }
                let interruptResponseID = bargeIn ? prepareAutomaticBargeIn() : nil
                if !bargeIn { state = .listening }
                intents.append(.beginUtterance(interruptResponseID: interruptResponseID))
                intents.append(contentsOf: frames.map(AudioUploadIntent.audio))

            case .audio(let frame):
                intents.append(.audio(frame))

            case .commit(_, let speechDuration, let endingSilence):
                automaticCommitCount += 1
                lastSpeechDurationMilliseconds = speechDuration
                lastEndingSilenceMilliseconds = endingSilence
                vadState = .endpointing
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
        bargeInDetectionCount += 1
        interruptedResponseID = oldResponseID
        if interruptedResponseIDs.count >= 32,
           let oldestRetainedID = interruptedResponseIDs.first {
            interruptedResponseIDs.remove(oldestRetainedID)
        }
        interruptedResponseIDs.insert(oldResponseID)
        metrics.interruptCount += 1
        playback.cancel(responseID: oldResponseID)
        isPlaybackActive = false
        state = .interrupting
        return oldResponseID
    }

    private func handleUploadNotification(_ notification: AudioUploadNotification) {
        switch notification {
        case .audioSent(let bytes, _):
            metrics.inputFrames += 1
            metrics.inputBytes += bytes
            if metrics.firstInputAt == nil {
                let now = Date()
                metrics.firstInputAt = now
                firstInputChunkSentAt = now
            }
        case .commitSent:
            audioCommitSentAt = Date()
            firstAudioDeltaReceivedAt = nil
            VoiceLog.audio.info("audio_commit_sent chunks=\(self.metrics.inputFrames)")
        case .interruptSent:
            interruptSentCount += 1
            state = .listening
            VoiceLog.audio.info(
                "automatic_barge_in interrupt_count=\(self.interruptSentCount)"
            )
        case .sendFailed:
            metrics.droppedFrames += 1
            recordSendFailure(AudioUploadActorError.sendFailed)
        case .backpressure:
            terminalLocalAudioFailure = true
            stopContinuousCapture(resetVAD: true)
            lastErrorCategory = "local_audio_upload_backpressure"
            lastReasonCategory = "audio_upload_queue_full"
            lastDisconnectRecoverable = false
            errorMessage = "本地语音上传队列已满，请结束通话后重试。"
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
        commitSentForCurrentPress = false
        playback.cancel(responseID: nil)
        isPlaybackActive = false
        voiceActivityDetector.resetForListening()
        vadState = .idleListening
        vadEnergyBand = "silent"
        vadNormalizedRMS = 0
        terminalProtocolErrorCode = nil
    }

    /// P2.8A-CI-FIX: Resume 成功后向已恢复的连接同步静音状态.
    /// 未静音 → 发送一次 unmute (随后恢复采集); 静音 → 发送一次 mute (不启动采集).
    /// 同步失败走现有发送失败处理 (recordSendFailure), 不新增独立重试循环.
    /// 返回是否同步成功: 失败时调用方不得恢复采集、不得标记 Resume 成功.
    @discardableResult
    private func syncMuteStateAfterResume() async -> Bool {
        do {
            try await audioUploader.setMuted(isMuted)
            return true
        } catch {
            recordSendFailure(error)
            return false
        }
    }

    private func startContinuousCaptureIfPossible() async {
        guard callIsActive,
              !suspendedForBackground,
              !isMuted,
              !isRecording,
              microphonePermission == .granted,
              audioSessionActive,
              webSocketState == .connected,
              // P2.8A: 允许 .listening 状态恢复采集, 避免用户在聆听期静音后无法重新启动
              state == .ready || state == .listening || state == .speaking else { return }
        do {
            try capture.start()
            isRecording = true
            await audioUploader.activateCaptureGeneration(capture.captureGeneration)
            startCaptureWatchdogIfNeeded()
            voiceActivityDetector.resetForListening()
            vadState = .idleListening
            vadEnergyBand = "silent"
            vadNormalizedRMS = 0
            scheduleMicrophoneReadinessCheck()
            VoiceLog.audio.info("continuous_capture_started")
        } catch {
            state = .failed
            errorMessage = "无法启动持续麦克风采集。"
            VoiceLog.audio.error("continuous_capture_start_failed")
        }
    }

    private func stopContinuousCapture(resetVAD: Bool) {
        stopCaptureWatchdog()
        capture.stop()
        isRecording = false
        if resetVAD {
            voiceActivityDetector.suspend()
            vadState = .idleListening
            vadEnergyBand = "silent"
            vadNormalizedRMS = 0
        }
        VoiceLog.audio.info("continuous_capture_stopped")
    }

    private func startCaptureWatchdogIfNeeded() {
        guard audioIOHealthReporter != nil, captureWatchdogTask == nil else { return }
        let snapshot = audioIOHealthReporter?.healthSnapshot ?? .unavailable
        captureWatchdogStartedAt = Date()
        lastObservedCaptureCallbackCount = snapshot.captureCallbackCount
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

    private func markMicrophoneReadyIfPossible() {
        let health = audioIOHealthReporter?.healthSnapshot
        let callbackConfirmed = health.map {
            $0.captureEngineRunning
                && $0.captureTapInstalled
                && $0.captureCallbackCount > 0
        } ?? isRecording
        guard microphoneReadyAt == nil,
              callIsActive,
              audioSessionActive,
              isRecording,
              webSocketState == .connected,
              callbackConfirmed else { return }
        microphoneReadyAt = Date()
    }

    private func scheduleMicrophoneReadinessCheck() {
        markMicrophoneReadyIfPossible()
        guard microphoneReadyAt == nil else { return }
        microphoneReadinessTask?.cancel()
        microphoneReadinessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<10 {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard self.callIsActive else { return }
                self.markMicrophoneReadyIfPossible()
                if self.microphoneReadyAt != nil { return }
            }
        }
    }

    private func schedulePostResponseCaptureCheck() {
        postResponseCaptureCheckTask?.cancel()
        let expectedSessionID = sessionID
        let baseline = audioIOHealthReporter?.healthSnapshot.captureCallbackCount ?? 0
        lastResponseCompletionCaptureCallbacks = baseline
        postResponseCaptureCheckTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard let self,
                  self.callIsActive,
                  self.sessionID == expectedSessionID,
                  !self.isMuted,
                  self.webSocketState == .connected,
                  self.state == .ready || self.state == .listening else { return }

            self.syncAudioSessionState()
            if !self.audioSessionActive {
                do {
                    try self.audioSession.activate()
                    self.audioSession.refreshRoute()
                    self.syncAudioSessionState()
                } catch {
                    VoiceLog.audio.error("post_response_audio_session_reactivation_failed")
                }
            }
            if !self.isRecording {
                await self.startContinuousCaptureIfPossible()
            }

            guard let reporter = self.audioIOHealthReporter else { return }
            let snapshot = reporter.healthSnapshot
            self.postResponseCaptureCallbackDelta = max(
                0,
                snapshot.captureCallbackCount - baseline
            )
            let captureHealthy = snapshot.captureEngineRunning
                && snapshot.captureTapInstalled
                && self.postResponseCaptureCallbackDelta > 0
            guard !captureHealthy else {
                self.markMicrophoneReadyIfPossible()
                return
            }

            do {
                try reporter.recoverCapture()
                self.isRecording = true
                await self.audioUploader.activateCaptureGeneration(
                    self.capture.captureGeneration
                )
                self.voiceActivityDetector.resetForListening()
                self.vadState = .idleListening
                self.vadEnergyBand = "silent"
                self.vadNormalizedRMS = 0
                self.postResponseCaptureRecoveryCount += 1
                self.markMicrophoneReadyIfPossible()
                VoiceLog.audio.info("post_response_capture_recovered")
            } catch {
                VoiceLog.audio.error("post_response_capture_recovery_failed")
            }
        }
    }

    private func checkCaptureHealth() async {
        guard callIsActive,
              !suspendedForBackground,
              !isMuted,
              isRecording,
              audioSessionActive,
              state != .failed,
              state != .closed,
              state != .closing,
              let audioIOHealthReporter else { return }

        let snapshot = audioIOHealthReporter.healthSnapshot
        guard !snapshot.isInterrupted else { return }
        if snapshot.captureCallbackCount > lastObservedCaptureCallbackCount {
            lastObservedCaptureCallbackCount = snapshot.captureCallbackCount
            captureRecoveryAttemptCount = 0
            captureWatchdogStartedAt = Date()
            return
        }

        let now = Date()
        let watchdogReference = captureWatchdogStartedAt ?? now
        let lastActivity = max(
            snapshot.lastCaptureCallbackAt ?? watchdogReference,
            watchdogReference
        )
        let callbackAge = now.timeIntervalSince(lastActivity)
        let stalled = !snapshot.captureEngineRunning
            || !snapshot.captureTapInstalled
            || callbackAge >= captureStallThresholdSeconds
        guard stalled else { return }

        guard captureRecoveryAttemptCount < maxCaptureRecoveryAttempts else {
            await failForCaptureStall()
            return
        }
        captureRecoveryAttemptCount += 1
        do {
            try audioIOHealthReporter.recoverCapture()
            await audioUploader.activateCaptureGeneration(capture.captureGeneration)
            captureWatchdogStartedAt = Date()
            VoiceLog.audio.info(
                "capture_watchdog_recovered attempt=\(self.captureRecoveryAttemptCount)"
            )
        } catch {
            VoiceLog.audio.error(
                "capture_watchdog_recovery_failed attempt=\(self.captureRecoveryAttemptCount)"
            )
            if captureRecoveryAttemptCount >= maxCaptureRecoveryAttempts {
                await failForCaptureStall()
            }
        }
    }

    private func failForCaptureStall() async {
        terminalLocalAudioFailure = true
        await audioUploader.pauseCapture()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        postResponseCaptureCheckTask?.cancel()
        postResponseCaptureCheckTask = nil
        microphoneReadinessTask?.cancel()
        microphoneReadinessTask = nil
        reconnectTask = nil
        reconnectGeneration = nil
        stopContinuousCapture(resetVAD: true)
        playback.cancel(responseID: nil)
        isPlaybackActive = false
        lastErrorCategory = "local_audio_capture_stalled"
        lastReasonCategory = "capture_watchdog_exhausted"
        lastDisconnectRecoverable = false
        errorMessage = "本地麦克风采集已停止，请结束通话后重试。"
        state = .failed
        VoiceLog.audio.error("capture_watchdog_exhausted")
    }

    private func recordSendFailure(_ error: Error) {
        let info = error as? VoiceWebSocketDisconnectInfo
        lastErrorCategory = info?.errorCategory ?? "connection_lost"
        lastReasonCategory = info?.reasonCategory ?? "send_failed"
        lastDisconnectRecoverable = info?.recoverable ?? true
        errorMessage = "语音数据发送失败，正在尝试恢复连接。"
        beginReconnect(immediate: false)
    }

    private func tearDownCurrentCall(
        sendSessionEnd: Bool,
        finalState: VoiceSessionState?
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
        await audioUploader.pauseCapture()
        stopContinuousCapture(resetVAD: true)
        playback.cancel(responseID: nil)
        isPlaybackActive = false
        audioIOHealthReporter?.shutdownAudioIO()
        if sendSessionEnd, await socket.isConnected() {
            try? await audioUploader.endSession()
        }
        await audioUploader.abortConnection()
        await stopReceiveLoop()
        await socket.disconnect()
        webSocketState = .disconnected
        audioSession.deactivate()
        syncAudioSessionState()
        networkMonitor.stop()
        responseID = ""
        expectedReadyEvent = nil
        lastReadyEvent = nil
        if let finalState { state = finalState }
        VoiceLog.lifecycle.info("call_resources_released")
    }

    private func syncAudioSessionState() {
        audioSessionActive = audioSession.isActive
        audioRouteDescription = audioSession.routeDescription
        microphonePermission = audioSession.permissionState
    }

    private func elapsedMilliseconds(since start: Date?) -> Int? {
        guard let start else { return nil }
        return max(0, Int(Date().timeIntervalSince(start) * 1000))
    }

    private func elapsedMilliseconds(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return max(0, Int(end.timeIntervalSince(start) * 1000))
    }

    private func userMessage(for info: VoiceWebSocketDisconnectInfo) -> String {
        switch info.errorCategory {
        case "unauthorized": return "语音鉴权失败，请重新输入开发 Token。"
        case "tls_failed": return "安全连接失败，请检查系统时间和网络证书。"
        case "network_unavailable": return "当前网络不可用。"
        case "connection_lost": return "语音连接意外中断，正在尝试重连。"
        case "timed_out": return "语音连接超时，正在尝试重连。"
        case "server_closed": return "语音连接已由服务器关闭。"
        case "protocol_error": return "语音协议响应异常。"
        default: return "语音连接发生异常。"
        }
    }

    private var microphoneDeniedMessage: String {
        "麦克风权限未开启，请前往系统设置允许小猫访问麦克风。"
    }

    // Internal-only observability used by unit tests. Never rendered directly.
    var sessionIDForTesting: String { sessionID }
    var traceIDForTesting: String { traceID }
    var clientSequenceForTesting: Int {
        audioUploader.diagnostics.snapshot.nextClientSequence
    }
    var chunkIndexForTesting: Int {
        audioUploader.diagnostics.snapshot.nextChunkIndex
    }
    var lastServerSequenceForTesting: Int { lastServerSequence }
    var responseIDForTesting: String { responseID }
    var hasReconnectTaskForTesting: Bool { reconnectTask != nil }
    var hasReceiveTaskForTesting: Bool { receiveTask != nil }
    var receiveGenerationForTesting: Int { receiveGeneration }
    var receiveLoopStartCountForTesting: Int { receiveLoopStartCount }
    var receiveLoopStopCountForTesting: Int { receiveLoopStopCount }
    var activeReceiveLoopCountForTesting: Int { activeReceiveLoopCount }
    var maxActiveReceiveLoopCountForTesting: Int { maxActiveReceiveLoopCount }
    var lifecycleConnectedEventCountForTesting: Int { lifecycleConnectedEventCount }
    var protocolReadyEventCountForTesting: Int { protocolReadyEventCount }
    var providerErrorCountForTesting: Int { metrics.degradedCount }
    var hasHeartbeatTaskForTesting: Bool { heartbeatTask != nil }
    var hasCaptureWatchdogTaskForTesting: Bool { captureWatchdogTask != nil }
    var usesSharedAudioIOForTesting: Bool { usesSharedAudioIO }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let value = components
        return TimeInterval(value.seconds)
            + TimeInterval(value.attoseconds) / 1_000_000_000_000_000_000
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
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
