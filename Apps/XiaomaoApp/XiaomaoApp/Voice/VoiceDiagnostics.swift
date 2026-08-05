import CryptoKit
import Foundation

struct VoiceDiagnosticSnapshot: Sendable {
    let appBuildSHA: String
    let appBuildTime: String
    let state: VoiceSessionState
    let webSocketState: VoiceWebSocketState
    let adapterMode: String
    let sessionHash: String
    let lastCloseCode: Int?
    let lastErrorCategory: String
    let lastReasonCategory: String
    let lastDisconnectRecoverable: Bool
    let reconnectAttempt: Int
    let reconnectCount: Int
    let microphonePermission: MicrophonePermissionState
    let audioSessionActive: Bool
    let audioRouteDescription: String
    let lastServerEventType: String
    let lastServerEventAt: Date?
    let inputAudioChunks: Int
    let outputAudioChunks: Int
    let providerErrorCount: Int
    let networkType: NetworkConnectionType
    let vadState: VoiceActivityState
    let vadEnergyBand: String
    let vadNormalizedRMS: Double
    let vadConfiguration: VoiceActivityConfiguration
    let speechStartCount: Int
    let automaticCommitCount: Int
    let rejectedNoiseCount: Int
    let bargeInDetectionCount: Int
    let interruptSentCount: Int
    let interruptSuccessCount: Int
    let ignoredInterruptedAudioChunks: Int
    let webSocketResourceTimeoutSeconds: Int
    let webSocketConnectedDurationMilliseconds: Int?
    let lastDisconnectUptimeMilliseconds: Int?
    let endToFirstAudioMilliseconds: Int?
    let firstInputChunkSentAt: Date?
    let audioCommitSentAt: Date?
    let firstAudioDeltaReceivedAt: Date?
    let responseNextSentCount: Int
    let serverPushAudioChunks: Int
    let continuousCaptureActive: Bool
    let captureEngineRunning: Bool
    let captureTapInstalled: Bool
    let captureCallbackCount: Int
    let lastCaptureCallbackAt: Date?
    let captureRestartCount: Int
    let audioEngineStartCount: Int
    let audioEngineStopCount: Int
    let playbackStartCount: Int
    let audioInterruptionCount: Int
    let engineConfigurationChangeCount: Int
    let uploadConnectionGeneration: Int
    let uploadCaptureGeneration: Int
    let uploadNextChunkIndex: Int
    let uploadNextClientSequence: Int
    let uploadQueueDepth: Int
    let uploadQueueHighWater: Int
    let uploadSentAudioChunks: Int
    let uploadSentControlCommands: Int
    let uploadDroppedStaleGenerationChunks: Int
    let uploadRejectedAfterCloseCommands: Int
    let uploadStaleGenerationSendFailureCount: Int
    let uploadActiveGenerationSendFailureCount: Int
    let uploadInputBackpressureCount: Int
    let uploadMaxActiveDrainTasks: Int
    let uploadLastFiveSentChunkIndices: [Int]
    let uploadLastSendFailureCategory: String
    let uploadGenerationStartedAt: Date?
    let playbackActive: Bool
    let lastSpeechDurationMilliseconds: Int
    let lastEndingSilenceMilliseconds: Int
    let generatedAt: Date

    var text: String {
        let formatter = ISO8601DateFormatter()
        let lastEventTime = lastServerEventAt.map(formatter.string(from:)) ?? "none"
        return [
            "Xiaomao iOS voice diagnostics",
            "app_commit=\(safe(appBuildSHA, fallback: "unknown"))",
            "app_build_time=\(safe(appBuildTime, fallback: "unknown"))",
            "state=\(state.rawValue)",
            "websocket_state=\(webSocketState.rawValue)",
            "adapter_mode=\(safe(adapterMode, fallback: "Empty"))",
            "session_hash=\(sessionHash)",
            "last_close_code=\(lastCloseCode.map(String.init) ?? "none")",
            "last_error_category=\(safe(lastErrorCategory, fallback: "none"))",
            "last_reason_category=\(safe(lastReasonCategory, fallback: "none"))",
            "recoverable=\(lastDisconnectRecoverable)",
            "reconnect_attempt=\(reconnectAttempt)",
            "reconnect_count=\(reconnectCount)",
            "route=b",
            "microphone_permission=\(microphonePermission.rawValue)",
            "audio_session_active=\(audioSessionActive)",
            "audio_route=\(safe(audioRouteDescription, fallback: "unknown"))",
            "last_server_event=\(safe(lastServerEventType, fallback: "none"))",
            "last_server_event_time=\(lastEventTime)",
            "input_audio_chunks=\(inputAudioChunks)",
            "output_audio_chunks=\(outputAudioChunks)",
            "provider_error_count=\(providerErrorCount)",
            "network_type=\(networkType.rawValue)",
            "vad_state=\(vadState.rawValue)",
            "vad_energy_band=\(safe(vadEnergyBand, fallback: "unknown"))",
            "vad_rms=\(String(format: "%.4f", vadNormalizedRMS))",
            "vad_pre_roll_ms=\(vadConfiguration.preRollMilliseconds)",
            "vad_min_speech_ms=\(vadConfiguration.minimumSpeechMilliseconds)",
            "vad_barge_min_speech_ms=\(vadConfiguration.bargeInMinimumSpeechMilliseconds)",
            "vad_end_silence_ms=\(vadConfiguration.endSilenceMilliseconds)",
            "vad_max_utterance_ms=\(vadConfiguration.maximumUtteranceMilliseconds)",
            "vad_speech_threshold=\(String(format: "%.4f", vadConfiguration.speechRMSThreshold))",
            "vad_barge_threshold=\(String(format: "%.4f", vadConfiguration.bargeInRMSThreshold))",
            "speech_start_count=\(speechStartCount)",
            "automatic_commit_count=\(automaticCommitCount)",
            "rejected_noise_count=\(rejectedNoiseCount)",
            "barge_in_detection_count=\(bargeInDetectionCount)",
            "interrupt_sent_count=\(interruptSentCount)",
            "interrupt_success_count=\(interruptSuccessCount)",
            "ignored_interrupted_audio_chunks=\(ignoredInterruptedAudioChunks)",
            "websocket_resource_timeout_seconds=\(webSocketResourceTimeoutSeconds)",
            "websocket_connected_duration_ms=\(optional(webSocketConnectedDurationMilliseconds))",
            "last_disconnect_uptime_ms=\(optional(lastDisconnectUptimeMilliseconds))",
            "end_to_first_audio_ms=\(optional(endToFirstAudioMilliseconds))",
            "first_input_chunk_sent_at=\(date(firstInputChunkSentAt, formatter: formatter))",
            "audio_commit_sent_at=\(date(audioCommitSentAt, formatter: formatter))",
            "first_audio_delta_received_at=\(date(firstAudioDeltaReceivedAt, formatter: formatter))",
            "response_next_sent_count=\(responseNextSentCount)",
            "server_push_audio_chunks=\(serverPushAudioChunks)",
            "continuous_capture_active=\(continuousCaptureActive)",
            "capture_engine_running=\(captureEngineRunning)",
            "capture_tap_installed=\(captureTapInstalled)",
            "capture_callback_count=\(captureCallbackCount)",
            "last_capture_callback_at=\(date(lastCaptureCallbackAt, formatter: formatter))",
            "last_capture_callback_age_ms=\(captureCallbackAgeMilliseconds())",
            "capture_restart_count=\(captureRestartCount)",
            "audio_engine_start_count=\(audioEngineStartCount)",
            "audio_engine_stop_count=\(audioEngineStopCount)",
            "playback_start_count=\(playbackStartCount)",
            "audio_interruption_count=\(audioInterruptionCount)",
            "engine_configuration_change_count=\(engineConfigurationChangeCount)",
            "upload_connection_generation=\(uploadConnectionGeneration)",
            "upload_capture_generation=\(uploadCaptureGeneration)",
            "upload_next_chunk_index=\(uploadNextChunkIndex)",
            "upload_next_client_sequence=\(uploadNextClientSequence)",
            "upload_queue_depth=\(uploadQueueDepth)",
            "upload_queue_high_water=\(uploadQueueHighWater)",
            "upload_sent_audio_chunks=\(uploadSentAudioChunks)",
            "upload_sent_control_commands=\(uploadSentControlCommands)",
            "upload_dropped_stale_generation_chunks=\(uploadDroppedStaleGenerationChunks)",
            "upload_rejected_after_close_commands=\(uploadRejectedAfterCloseCommands)",
            "upload_stale_generation_send_failure_count=\(uploadStaleGenerationSendFailureCount)",
            "upload_active_generation_send_failure_count=\(uploadActiveGenerationSendFailureCount)",
            "upload_input_backpressure_count=\(uploadInputBackpressureCount)",
            "upload_max_active_drain_tasks=\(uploadMaxActiveDrainTasks)",
            "upload_last_five_sent_chunk_indices=\(uploadLastFiveSentChunkIndices.map(String.init).joined(separator: ","))",
            "upload_last_send_failure_category=\(safe(uploadLastSendFailureCategory, fallback: "none"))",
            "upload_generation_started_at=\(date(uploadGenerationStartedAt, formatter: formatter))",
            "playback_active=\(playbackActive)",
            "last_speech_duration_ms=\(lastSpeechDurationMilliseconds)",
            "last_ending_silence_ms=\(lastEndingSilenceMilliseconds)",
            "generated_at=\(formatter.string(from: generatedAt))"
        ].joined(separator: "\n")
    }

    static func shortHash(_ value: String) -> String {
        guard !value.isEmpty else { return "none" }
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private func optional(_ value: Int?) -> String {
        value.map(String.init) ?? "none"
    }

    private func date(_ value: Date?, formatter: ISO8601DateFormatter) -> String {
        value.map(formatter.string(from:)) ?? "none"
    }

    private func captureCallbackAgeMilliseconds() -> String {
        guard let lastCaptureCallbackAt else { return "none" }
        return String(max(0, Int(generatedAt.timeIntervalSince(lastCaptureCallbackAt) * 1000)))
    }

    private func safe(_ value: String, fallback: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(160))
    }
}
